import Flutter
import UIKit
import ObjectiveC

// MARK: - Module-level state for the locale-forcing swizzle

/// Non-nil during an active liveness session: the BCP-47 tag that must be
/// used for every `localizedString` call originating from the Azure AI Vision
/// Face UI framework bundle.  Setting this to nil makes the swizzle a no-op.
private var _azureForceLocale: String? = nil

// MARK: - NSBundle swizzle

extension Bundle {
    /// Swizzled replacement for `localizedString(forKey:value:table:)`.
    ///
    /// When `_azureForceLocale` is non-nil **and** the receiver is (or is a
    /// child of) the AzureAIVisionFaceUI framework bundle, the lookup is
    /// redirected to the matching `.lproj` sub-bundle, bypassing the SDK's
    /// internal `Strings.locale` cached property entirely.
    ///
    /// For every other bundle the call passes straight through to the original
    /// implementation (the methods have been exchanged, so calling
    /// `azl_localizedString` here invokes the original code).
    @objc func azl_localizedString(forKey key: String,
                                   value: String?,
                                   table tableName: String?) -> String {
        guard let forceTag = _azureForceLocale else {
            // Swizzle inactive — call through to the original implementation.
            return azl_localizedString(forKey: key, value: value, table: tableName)
        }

        // Only intercept calls from the Azure AI Vision Face UI bundle.
        let isAzureBundle = (bundleIdentifier?.lowercased().contains("azure") == true)
                         || bundlePath.contains("AzureAIVisionFaceUI")

        guard isAzureBundle else {
            return azl_localizedString(forKey: key, value: value, table: tableName)
        }

        // Normalise to the framework root in case `self` is already a .lproj
        // sub-bundle that the SDK loaded itself for the wrong locale.
        let rootPath: String
        if let lprojRange = bundlePath.range(of: ".lproj", options: .backwards) {
            rootPath = (String(bundlePath[..<lprojRange.upperBound]) as NSString)
                .deletingLastPathComponent
        } else {
            rootPath = bundlePath
        }

        // Try the full tag first (e.g. "pt-PT"), then the bare language ("pt").
        let candidates: [String]
        if forceTag.contains("-") || forceTag.contains("_") {
            let lang = String(forceTag.prefix(while: { $0 != "-" && $0 != "_" }))
            candidates = [forceTag, lang]
        } else {
            candidates = [forceTag]
        }

        for candidate in candidates {
            let lprojPath = rootPath + "/\(candidate).lproj"
            if let lprojBundle = Bundle(path: lprojPath) {
                // Suspend interception while looking up inside the .lproj bundle
                // to avoid infinite recursion through the swizzle.
                _azureForceLocale = nil
                let translated = lprojBundle.azl_localizedString(forKey: key, value: value, table: tableName)
                _azureForceLocale = forceTag
                if translated != key {
                    return translated
                }
            }
        }

        // No locale-specific string found — pass through to the original.
        _azureForceLocale = nil
        let fallback = azl_localizedString(forKey: key, value: value, table: tableName)
        _azureForceLocale = forceTag
        return fallback
    }
}

// MARK: - Plugin

/// AzureLivenessPlugin
///
/// Registers the `azure_liveness` MethodChannel and bridges calls from Flutter
/// to [LivenessViewController], which hosts the Azure AI Vision Face Liveness UI.
public class AzureLivenessPlugin: NSObject, FlutterPlugin {

    private var pendingResult: FlutterResult?
    private static var swizzleInstalled = false

    // MARK: - FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        installBundleSwizzle()
        let channel = FlutterMethodChannel(
            name: "azure_liveness",
            binaryMessenger: registrar.messenger()
        )
        let instance = AzureLivenessPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - MethodCall handling

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startLivenessCheck":
            startLivenessCheck(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Private

    /// Installs the NSBundle swizzle exactly once.
    ///
    /// After this call every invocation of `Bundle.localizedString(forKey:value:table:)`
    /// goes through `azl_localizedString`, which can redirect Azure SDK bundle
    /// lookups to the locale we force via `_azureForceLocale`.
    private static func installBundleSwizzle() {
        guard !swizzleInstalled else { return }
        swizzleInstalled = true
        guard
            let orig = class_getInstanceMethod(Bundle.self,
                #selector(Bundle.localizedString(forKey:value:table:))),
            let swiz = class_getInstanceMethod(Bundle.self,
                #selector(Bundle.azl_localizedString(forKey:value:table:)))
        else { return }
        method_exchangeImplementations(orig, swiz)
    }

    private func startLivenessCheck(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard pendingResult == nil else {
            result(FlutterError(
                code: "ALREADY_RUNNING",
                message: "A liveness check is already in progress.",
                details: nil
            ))
            return
        }

        guard
            let args = call.arguments as? [String: Any],
            let sessionToken = args["sessionToken"] as? String,
            !sessionToken.isEmpty
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "sessionToken is required.",
                details: nil
            ))
            return
        }

        // verifyImageBytes is sent as FlutterStandardTypedData (Uint8List on the Dart side).
        let verifyImageData = (args["verifyImageBytes"] as? FlutterStandardTypedData)?.data
        let locale = args["locale"] as? String

        pendingResult = result

        presentLivenessCheck(sessionToken: sessionToken, verifyImageData: verifyImageData, locale: locale)
    }

    private func presentLivenessCheck(sessionToken: String, verifyImageData: Data?, locale: String?) {
        guard let rootVC = findRootViewController() else {
            pendingResult?(FlutterError(
                code: "NO_VIEW_CONTROLLER",
                message: "Could not find a root UIViewController to present the liveness UI.",
                details: nil
            ))
            pendingResult = nil
            return
        }

        // Map bare language code → full BCP-47 tag matching the SDK's .lproj names.
        let resolvedLocale = locale.map { expandLocale($0) }

        // Activate the NSBundle swizzle for this session so that every
        // localizedString call from the Azure SDK bundle is served from the
        // correct .lproj sub-bundle, bypassing the SDK's internal locale cache.
        _azureForceLocale = resolvedLocale

        let livenessVC = LivenessViewController()
        livenessVC.sessionToken = sessionToken
        livenessVC.verifyImageData = verifyImageData
        livenessVC.locale = resolvedLocale
        livenessVC.modalPresentationStyle = .fullScreen
        livenessVC.completion = { [weak self] outcome in
            guard let self = self else { return }

            // Deactivate the NSBundle swizzle — restore transparent behaviour.
            _azureForceLocale = nil

            switch outcome {
            case .success(let success):
                self.pendingResult?([
                    "success": true,
                    "digest": success.digest,
                    "resultId": success.resultId as Any,
                ] as [String: Any])
            case .failure(let error):
                self.pendingResult?([
                    "success": false,
                    "errorCode": error.errorCode,
                    "errorMessage": error.errorMessage as Any,
                ] as [String: Any])
            }
            self.pendingResult = nil
        }

        // Present on the topmost visible controller.
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(livenessVC, animated: true)
    }

    /// Maps a bare BCP-47 language subtag to the best full locale identifier
    /// available in the Azure AI Vision Face UI SDK bundle.
    ///
    /// The SDK ships region-specific .lproj folders (e.g. "pt-PT", "fr-FR") but
    /// the Flutter caller typically sends only the language subtag ("pt", "fr").
    private func expandLocale(_ languageCode: String) -> String {
        // Fast path: already contains a region subtag.
        if languageCode.contains("-") || languageCode.contains("_") {
            return languageCode
        }
        let map: [String: String] = [
            "en": "en-GB",
            "pt": "pt-PT",
            "fr": "fr-FR",
            "es": "es-ES",
            "de": "de-DE",
            "it": "it-IT",
            "nl": "nl-NL",
            "ar": "ar-SA",
            "zh": "zh-CN",
            "ko": "ko-KR",
            "ja": "ja-JP",
            "ru": "ru-RU",
        ]
        return map[languageCode] ?? languageCode
    }

    private func findRootViewController() -> UIViewController? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        } else {
            return UIApplication.shared.keyWindow?.rootViewController
        }
    }
}
