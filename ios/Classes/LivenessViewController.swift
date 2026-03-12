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

// MARK: - LivenessViewController

/// A UIViewController that embeds `FaceLivenessDetectorView` (SwiftUI) from the
/// Azure AI Vision Face UI SDK via a UIHostingController.
class LivenessViewController: UIViewController {

    // MARK: - Properties

    /// Session authorisation token obtained from the Azure Face service.
    var sessionToken: String = ""

    /// Optional reference image for liveness-with-verify mode.
    var verifyImageData: Data?

    /// Called on the main thread when the liveness session ends (success or error).
    var completion: ((Result<LivenessSuccess, LivenessError>) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        embedLivenessView()
    }

    // MARK: - Private

    private func embedLivenessView() {
        let hostingController = UIHostingController(rootView:
            FaceLivenessDetectorView(
                sessionAuthorizationToken: sessionToken,
                verifyImageFileContent: verifyImageData,
                onSuccess: { [weak self] success in
                    self?.completion?(.success(LivenessSuccess(
                        digest: success.digest,
                        resultId: success.resultId
                    )))
                    self?.dismiss(animated: true)
                },
                onError: { [weak self] error in
                    self?.completion?(.failure(LivenessError(
                        errorCode: error.kind.rawValue,
                        errorMessage: error.message
                    )))
                    self?.dismiss(animated: true)
                }
            )
        )
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}
