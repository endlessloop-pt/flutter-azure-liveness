import Flutter
import UIKit

/// AzureLivenessPlugin
///
/// Registers the `azure_liveness` MethodChannel and bridges calls from Flutter
/// to [LivenessViewController], which hosts the Azure AI Vision Face Liveness UI.
public class AzureLivenessPlugin: NSObject, FlutterPlugin {

    private var pendingResult: FlutterResult?

    // MARK: - FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
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

        // Resolve the locale to a full BCP-47 tag supported by the Azure SDK bundle
        // (e.g. "pt" → "pt-PT", "fr" → "fr-FR"). This is required because:
        // 1. The SDK's .lproj folders use region-specific identifiers (pt-PT, fr-FR, …)
        //    with no bare "pt" or "fr" folder.
        // 2. iOS NSBundle localisation (used internally by the SDK) is driven by
        //    Bundle.preferredLocalizations / UserDefaults "AppleLanguages", NOT by
        //    SwiftUI's \.locale environment value.  We therefore temporarily override
        //    "AppleLanguages" — mirroring the Android plugin's attachBaseContext approach —
        //    so that all NSLocalizedString calls inside the SDK pick up the right language.
        let resolvedLocale = locale.map { expandLocale($0) }
        let savedLanguages = UserDefaults.standard.stringArray(forKey: "AppleLanguages")
        if let tag = resolvedLocale {
            UserDefaults.standard.set([tag], forKey: "AppleLanguages")
        }

        let livenessVC = LivenessViewController()
        livenessVC.sessionToken = sessionToken
        livenessVC.verifyImageData = verifyImageData
        livenessVC.locale = resolvedLocale
        livenessVC.modalPresentationStyle = .fullScreen
        livenessVC.completion = { [weak self] outcome in
            guard let self = self else { return }

            // Restore the previous preferred-language list so the rest of the
            // app is unaffected.
            if let saved = savedLanguages {
                UserDefaults.standard.set(saved, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }

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
    /// iOS UserDefaults "AppleLanguages" does not fall back from bare "pt" to
    /// "pt-PT" automatically, so we resolve the mapping explicitly here.
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
