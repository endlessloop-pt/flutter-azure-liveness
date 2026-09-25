## 1.0.10

* **Vendor the Azure SDK binaries — builds no longer need a Microsoft token.**
  The Android `azure-ai-vision-face-ui-assets` artifact (published only to Microsoft's
  gated Azure DevOps feed) is mirrored into `android/m2/`, and the iOS xcframework
  (a Git LFS object on `msface.visualstudio.com`) is committed as a zip under
  `ios/Frameworks/` and expanded by the podspec at `pod install` time.
* iOS: link the SDK via `vendored_frameworks` instead of Swift Package Manager. Apps no
  longer need to add AzureAIVisionFaceUI as a Swift Package, and the `FRAMEWORK_SEARCH_PATHS`
  workaround that globbed DerivedData for the SPM checkout can be deleted from their Podfile.
* Android: pin the SDK to `1.5.1` (was the dynamic version `+`, which is incompatible with
  vendoring and could silently resolve to an unmirrored version). Apps should drop any
  `resolutionStrategy.force` rules for `com.azure:azure-ai-vision-face-ui*`.
* Add `scripts/vendor-sdk.sh` to refresh both platforms' binaries; it is the only step that
  uses a credential.
* Consuming apps must declare the vendored Maven mirror — see README "Consuming app setup".

## 1.0.9

* Fix (Android): catch the same `RuntimeException` when the user taps the close (X) button during an active liveness session. The close button is handled inside the Azure SDK's own UI and does not route through `onBackPressed`, so it bypassed the 1.0.8 fix; it is now caught via `dispatchTouchEvent` and treated as user-cancellation.

## 1.0.8

* Fix (Android): catch `RuntimeException` thrown by Azure SDK v1.4.8 when the user presses Back during an active liveness session, preventing a crash. The session is now treated as user-cancelled.

## 1.0.7

* Add support to inform a locale to use on liveness check

## 1.0.3

* Fix Swift code to make it work with iOS

## 1.0.0

* First version of the library with complete functionality

## 0.1.0

* Initial release.
* `AzureLiveness.startLivenessCheck` — launches the Azure AI Vision Face Liveness
  native UI and returns a `LivenessResult`.
* Supports liveness-only and liveness-with-verify modes.
* iOS 14+ / Android API 24+ / Flutter 3.x / Dart 3.x.
