import UIKit
import SwiftUI

// Uncomment the line below once the AzureAIVisionFaceUI SPM package has been
// added to the Xcode workspace. See README for setup instructions.
// import AzureAIVisionFaceUI

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
///
/// ## Setup
/// Before this class can function, the `AzureAIVisionFaceUI` Swift Package must
/// be added to the host application's Xcode workspace.  See the README for
/// step-by-step instructions (Option A — Flutter SPM support, or Option B —
/// manual Xcode package addition).
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
        // -----------------------------------------------------------------------
        // PRODUCTION: uncomment the block below and delete the placeholder block
        // once AzureAIVisionFaceUI has been added via SPM.
        // -----------------------------------------------------------------------
        //
        // let hostingController = UIHostingController(rootView:
        //     FaceLivenessDetectorView(
        //         sessionAuthorizationToken: sessionToken,
        //         verifyImageFileContent: verifyImageData,
        //         onSuccess: { [weak self] success in
        //             self?.completion?(.success(LivenessSuccess(
        //                 digest: success.digest,
        //                 resultId: success.resultId
        //             )))
        //             self?.dismiss(animated: true)
        //         },
        //         onError: { [weak self] error in
        //             self?.completion?(.failure(LivenessError(
        //                 errorCode: error.kind.rawValue,
        //                 errorMessage: error.message
        //             )))
        //             self?.dismiss(animated: true)
        //         }
        //     )
        // )
        // addChild(hostingController)
        // hostingController.view.frame = view.bounds
        // hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // view.addSubview(hostingController.view)
        // hostingController.didMove(toParent: self)
        // -----------------------------------------------------------------------
        //
        // PLACEHOLDER — shown when the SDK is not yet linked:
        // -----------------------------------------------------------------------
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "AzureAIVisionFaceUI SDK not yet linked.\n\nSee README for SPM setup instructions."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    @objc private func closeButtonTapped() {
        completion?(.failure(LivenessError(
            errorCode: "UserCanceled",
            errorMessage: "User closed the liveness screen."
        )))
        dismiss(animated: true)
    }
}
