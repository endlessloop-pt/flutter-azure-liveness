import Flutter
import UIKit
import ObjectiveC

// MARK: - Module-level state

/// Non-nil during an active liveness session: the BCP-47 tag that the Azure SDK
/// must use for all its localised string lookups.
///
/// How the Azure SDK localises strings (from binary analysis):
///   1. Calls `Foundation.NSLocalizedString(key, bundle: Bundle.main)`.
///      Because the main bundle has no Azure strings this always returns the key.
///   2. On first call it lazily initialises `Strings.locale` (a `swift_once`
///      static var) by reading `Bundle.main.preferredLocalizations.first`.
///   3. Looks up `Localizable[Strings.locale][key]` in its pre-loaded
///      `[String: [String: String]]` dictionary (keyed by full BCP-47 tags
///      such as "pt-PT", "en-GB", "fr-FR" — NOT bare "pt" / "fr").
///
/// Therefore, to force the locale we swizzle `Bundle.preferredLocalizations`
/// so that, while this variable is set, `Bundle.main` returns `[_azureForceLocale]`.
/// This makes `Strings.locale` initialise to (e.g.) "pt-PT", which matches the
/// key that exists in `Localizable`, returning the correct translated string.
private var _azureForceLocale: String? = nil

// MARK: - Bundle.preferredLocalizations swizzle

extension Bundle {
    /// Swizzled replacement for the `preferredLocalizations` property getter.
    ///
    /// While `_azureForceLocale` is non-nil **and** the receiver is `Bundle.main`,
    /// returns `[_azureForceLocale]` so the Azure SDK's `Strings.locale` static
    /// property is initialised with the forced BCP-47 tag, which in turn drives
    /// the `Localizable` dictionary lookup to the correct language.
    ///
    /// For every other bundle the original getter is called unchanged.
    @objc var azl_preferredLocalizations: [String] {
        if let forceTag = _azureForceLocale, self === Bundle.main {
            return [forceTag]
        }
        // Call the original implementation (methods have been exchanged).
        return azl_preferredLocalizations
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

    /// Installs the `Bundle.preferredLocalizations` swizzle exactly once.
    ///
    /// After installation, every call to `Bundle.main.preferredLocalizations`
    /// goes through `azl_preferredLocalizations`, which can force the Azure SDK
    /// to initialise its `Strings.locale` cached property with the locale set
    /// in `_azureForceLocale`.
    private static func installBundleSwizzle() {
        guard !swizzleInstalled else { return }
        swizzleInstalled = true
        guard
            let orig = class_getInstanceMethod(
                Bundle.self,
                NSSelectorFromString("preferredLocalizations")),
            let swiz = class_getInstanceMethod(
                Bundle.self,
                #selector(getter: Bundle.azl_preferredLocalizations))
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

        // Map bare language code → full BCP-47 tag that matches a key in the
        // Azure SDK's Localizable dictionary (e.g. "pt" → "pt-PT").
        let resolvedLocale = locale.map { expandLocale($0) }

        // Activate the Bundle.preferredLocalizations swizzle so that
        // Strings.locale (a swift_once static inside the Azure SDK) is
        // initialised with the correct BCP-47 tag on first access.
        _azureForceLocale = resolvedLocale

        let livenessVC = LivenessViewController()
        livenessVC.sessionToken = sessionToken
        livenessVC.verifyImageData = verifyImageData
        livenessVC.locale = resolvedLocale
        livenessVC.modalPresentationStyle = .fullScreen
        livenessVC.completion = { [weak self] outcome in
            guard let self = self else { return }

            // Deactivate the swizzle — restore transparent behaviour.
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

    /// Maps a bare BCP-47 language subtag to the full locale identifier used
    /// as a key in the Azure AI Vision Face UI SDK's Localizable dictionary.
    ///
    /// The SDK's Localizable dictionary uses region-specific keys (e.g. "pt-PT",
    /// "fr-FR") but the Flutter caller sends only the language subtag ("pt", "fr").
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
