import UIKit
import SwiftUI
import AzureAIVisionFaceUI

// MARK: - Result types (mirroring the SDK's types for the completion callback)

/// Returned to [AzureLivenessPlugin] on a successful liveness session.
struct LivenessSuccess {
    let digest: String
    let resultId: String?
}

/// Returned to [AzureLivenessPlugin] when the session ends with an error.
struct LivenessError: Error {
    let errorCode: String
    let errorMessage: String?
}

// MARK: - SwiftUI container

/// Wraps `FaceLivenessDetectorView` with the Binding-based API introduced in v1.4.7.
private struct LivenessContainerView: View {
    let sessionToken: String
    let verifyImageData: Data?
    let locale: String?
    let onResult: (LivenessDetectionResult) -> Void

    @State private var result: LivenessDetectionResult?

    var body: some View {
        let resolvedLocale = locale.map { Locale(identifier: $0) } ?? Locale.current
        FaceLivenessDetectorView(
            result: $result,
            sessionAuthorizationToken: sessionToken,
            verifyImageFileContent: verifyImageData
        )
        .environment(\.locale, resolvedLocale)
        .onChange(of: result, perform: { newResult in
            if let newResult = newResult {
                onResult(newResult)
            }
        })
    }
}

// MARK: - LivenessViewController

/// A UIViewController that embeds `FaceLivenessDetectorView` (SwiftUI) from the
/// Azure AI Vision Face UI SDK via a UIHostingController.
class LivenessViewController: UIViewController {

    // MARK: - Properties

    /// Session authorisation token obtained from the Azure Face service.
    var sessionToken: String = ""

    /// Optional reference image for liveness-with-verify mode.
    var verifyImageData: Data?

    /// Optional BCP 47 locale tag (e.g. "pt-BR") to override the device locale
    /// for the liveness UI. When nil, the device locale is used.
    var locale: String?

    /// Called on the main thread when the liveness session ends (success or error).
    var completion: ((Result<LivenessSuccess, LivenessError>) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        embedLivenessView()
    }

    // MARK: - Private

    private func embedLivenessView() {
        let containerView = LivenessContainerView(
            sessionToken: sessionToken,
            verifyImageData: verifyImageData,
            locale: locale
        ) { [weak self] sdkResult in
            switch sdkResult {
            case .success(let success):
                self?.completion?(.success(LivenessSuccess(
                    digest: success.digest,
                    resultId: success.resultId
                )))
            case .failure(let error):
                self?.completion?(.failure(LivenessError(
                    errorCode: String(describing: error.livenessError),
                    errorMessage: error.livenessError.localizedDescription
                )))
            }
            self?.dismiss(animated: true)
        }

        let hostingController = UIHostingController(rootView: containerView)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}
