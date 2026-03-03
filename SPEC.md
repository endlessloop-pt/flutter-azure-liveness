# flutter-azure-liveness — Project Specification

## Context

This project creates a Flutter plugin that wraps the Azure AI Vision Face Liveness UI SDKs
for iOS (AzureAIVisionFaceUI) and Android (azure-ai-vision-face-ui). The goal is to give
Flutter apps a simple, idiomatic Dart API to trigger the native liveness detection UI and
receive a structured result — without bundling any backend/session logic inside the plugin.

---

## Objectives

- Expose a single `Future<LivenessResult> AzureLiveness.startLivenessCheck(...)` method
- Support both **Liveness-only** and **Liveness-with-Verify** modes
- Target iOS 14+ and Android API 24+, Flutter 3.x / Dart 3.x
- Include an `example/` app demonstrating integration
- Internal/private distribution (no pub.dev publishing required)

---

## Architecture

**Plugin type:** Standard single-package Flutter plugin with platform channels
**Communication:** `MethodChannel("azure_liveness")` — one method `startLivenessCheck`

```
flutter-azure-liveness/
├── lib/
│   ├── flutter_azure_liveness.dart          # Public barrel export
│   └── src/
│       ├── azure_liveness.dart              # AzureLiveness static class + MethodChannel
│       └── liveness_result.dart             # LivenessResult / LivenessError models
├── android/
│   ├── src/main/
│   │   ├── kotlin/dev/endlessloop/azure_liveness/
│   │   │   ├── AzureLivenessPlugin.kt       # FlutterPlugin + MethodChannel handler
│   │   │   └── LivenessActivity.kt          # Compose Activity with FaceLivenessDetector
│   │   └── AndroidManifest.xml              # CAMERA, INTERNET, VIBRATE permissions + Activity declaration
│   └── build.gradle                         # Maven dependency on azure-ai-vision-face-ui
├── ios/
│   ├── Classes/
│   │   ├── AzureLivenessPlugin.swift        # FlutterPlugin + MethodChannel handler
│   │   └── LivenessViewController.swift     # UIHostingController wrapping FaceLivenessDetectorView
│   └── flutter_azure_liveness.podspec       # Podspec (SPM dependency note documented)
├── example/
│   ├── lib/main.dart                        # Demo: token input field → trigger → show result
│   └── pubspec.yaml
├── test/
│   └── flutter_azure_liveness_test.dart     # Unit tests via mock MethodChannel
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
└── LICENSE
```

---

## Dart API (lib/)

### `AzureLiveness` — `lib/src/azure_liveness.dart`

```dart
class AzureLiveness {
  static const _channel = MethodChannel('azure_liveness');

  static Future<LivenessResult> startLivenessCheck({
    required String sessionToken,
    Uint8List? verifyImageBytes,   // null → liveness-only; non-null → liveness-with-verify
    String? deviceCorrelationId,
  }) async { /* invoke channel, parse result */ }
}
```

### `LivenessResult` — `lib/src/liveness_result.dart`

```dart
class LivenessResult {
  final bool isSuccess;
  // Populated on success:
  final String? digest;        // cryptographic integrity string
  final String? resultId;      // session result tracking ID
  // Populated on failure:
  final String? errorCode;     // e.g. "FaceWithMaskDetected", "UserCanceled"
  final String? errorMessage;  // human-readable description

  const LivenessResult._({required this.isSuccess, ...});

  factory LivenessResult.success({required String digest, String? resultId});
  factory LivenessResult.failure({required String errorCode, String? errorMessage});
}
```

**Method channel contract (map returned by native → Dart):**
```json
// success
{ "success": true, "digest": "B0A803...", "resultId": "abc123" }
// failure
{ "success": false, "errorCode": "UserCanceled", "errorMessage": "User closed the liveness screen" }
```

---

## Android Implementation (`android/`)

### Dependency — `android/build.gradle`

```groovy
dependencies {
  implementation 'com.azure:azure-ai-vision-face-ui:+'  // pin to latest stable
}
```

> **Note:** The SDK is on Maven Central but is a **gated artifact**. Developers must request
> access from Microsoft and configure their Maven credentials accordingly.

### Permissions — `android/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.VIBRATE" />
<activity android:name=".LivenessActivity" android:exported="false" />
```

### `AzureLivenessPlugin.kt`

- Implements `FlutterPlugin`, `MethodCallHandler`, `ActivityAware`
- Stores pending `MethodChannel.Result` when `startLivenessCheck` is called
- Launches `LivenessActivity` via `startActivityForResult` with extras:
  `sessionToken`, `verifyImageBytes` (ByteArray?), `deviceCorrelationId`
- In `onActivityResult`: parses result extras and calls `result.success(map)` or `result.error(...)`

### `LivenessActivity.kt`

- Jetpack Compose Activity
- Sets content to `FaceLivenessDetector(sessionAuthorizationToken, verifyImageFileContent, onSuccess, onError)`
- `onSuccess(success: LivenessDetectionSuccess)` → puts `digest`, `resultId` into intent extras, `setResult(RESULT_OK)`, finish
- `onError(error: LivenessDetectionError)` → puts error info into extras, `setResult(RESULT_CANCELED)`, finish

---

## iOS Implementation (`ios/`)

### Dependency

The SDK is distributed as a Swift Package from:
`https://github.com/Azure/AzureAIVisionFaceUI`

Because CocoaPods does not natively resolve SPM packages, the consuming app must either:

**Option A (Recommended for Flutter ≥ 3.22):** Enable Flutter's experimental SPM support and
add a `Package.swift` alongside the podspec.

**Option B (Fallback):** In their Xcode workspace, manually add the SPM package
(`File → Add Package Dependencies → paste the repo URL`) and link `AzureAIVisionFaceUI`
to the Runner target. The podspec's `s.pod_target_xcconfig` references the framework.

> This is a **gated artifact** — developers need a GitHub PAT with repo access granted by
> Microsoft before the package can be resolved.

### `AzureLivenessPlugin.swift`

- Registers `FlutterMethodChannel` for `"azure_liveness"`
- On `startLivenessCheck`: extracts args, instantiates `LivenessViewController`, presents it
  modally from the root view controller
- Stores the pending `FlutterResult` closure; resolved when the view controller calls the completion handler

### `LivenessViewController.swift`

```swift
class LivenessViewController: UIViewController {
  var sessionToken: String
  var verifyImageData: Data?
  var completion: (Result<LivenessSuccess, LivenessError>) -> Void

  override func viewDidLoad() {
    // Embed FaceLivenessDetectorView (SwiftUI) via UIHostingController
    // Pass $livenessResult binding; observe changes to resolve completion
  }
}
```

Returns to plugin:
- **Success:** `{ "success": true, "digest": "...", "resultId": "..." }`
- **Failure:** `{ "success": false, "errorCode": "...", "errorMessage": "..." }`

---

## End-to-End Session Flow (Documented in README, not implemented in plugin)

```
Host App              Plugin               Azure Face Service
────────────────────────────────────────────────────────────
1. POST /detectLiveness-sessions  ──────────────────────────► Returns { sessionId, authToken }
2. AzureLiveness.startLivenessCheck(token: authToken)
   │
3. [Native SDK UI launches, guides user, communicates with Azure]
   │                          ────────────────────────────────►
   │                                                           (SDK calls Face service directly)
   ◄─ LivenessResult(digest, resultId) or error
4. GET /livenessSessions/{sessionId}/result ────────────────► Returns { livenessDecision }
5. DELETE /livenessSessions/{sessionId}   ──────────────────►
```

> The liveness **decision** (`realface` / `spoof`) is NOT in the client result — the app server
> must query the Azure REST API (step 4) to obtain it.

---

## Example App (`example/`)

`example/lib/main.dart` provides:
- A text field to paste a `sessionAuthorizationToken`
- An optional "Browse" button to select a verify image (triggers liveness-with-verify mode)
- A "Start Liveness Check" button that calls `AzureLiveness.startLivenessCheck(...)`
- A result panel showing `digest`, `resultId`, or error details

---

## Tests (`test/`)

`test/flutter_azure_liveness_test.dart` uses `TestWidgetsFlutterBinding` and mocks the
`MethodChannel` to:
- Assert correct arguments are sent for liveness-only calls
- Assert correct arguments are sent for liveness-with-verify calls
- Test `LivenessResult.success(...)` and `LivenessResult.failure(...)` parsing
- Test that exceptions propagate correctly on channel errors

### Coverage requirement

**Line coverage must remain at or above 80%.** The current baseline is 100%.

Run the coverage script to measure, generate an HTML report, and enforce the threshold:

```bash
./scripts/coverage.sh           # check against default 80% threshold
./scripts/coverage.sh --open    # also open the HTML report in the browser
./scripts/coverage.sh --threshold 90  # override threshold
```

The script (`scripts/coverage.sh`) requires `lcov` / `genhtml` (`brew install lcov`).
Generated coverage artefacts land in `coverage/` which is gitignored.

Use `// coverage:ignore-line` (single line) or `// coverage:ignore-start` /
`// coverage:ignore-end` (block) to suppress coverage on provably untestable lines
(e.g. private utility-class constructors). All suppressions must be justified.

---

## `pubspec.yaml` (key fields)

```yaml
name: flutter_azure_liveness
description: Flutter plugin wrapping the Azure AI Vision Face Liveness UI SDK for iOS and Android.
version: 0.1.0
environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.0.0"
flutter:
  plugin:
    platforms:
      android:
        package: dev.endlessloop.azure_liveness
        pluginClass: AzureLivenessPlugin
      ios:
        pluginClass: AzureLivenessPlugin
```

---

## Step-by-Step Implementation Plan

1. **Scaffold the plugin**
   - `flutter create --template=plugin --platforms=android,ios --org=dev.endlessloop flutter_azure_liveness`
   - Rename default boilerplate classes to match spec

2. **Dart layer**
   - Create `lib/src/liveness_result.dart` (models + factories)
   - Create `lib/src/azure_liveness.dart` (static class + MethodChannel)
   - Update `lib/flutter_azure_liveness.dart` to export both

3. **Android layer**
   - Add `com.azure:azure-ai-vision-face-ui` to `android/build.gradle`
   - Add permissions + `<activity>` to `android/src/main/AndroidManifest.xml`
   - Implement `LivenessActivity.kt` (Compose + SDK callbacks → Activity result)
   - Implement `AzureLivenessPlugin.kt` (MethodChannel → launch activity → resolve result)

4. **iOS layer**
   - Set `s.ios_deployment_target = '14.0'` in podspec
   - Document SPM dependency setup (Option A / Option B) in podspec comments and README
   - Implement `LivenessViewController.swift` (UIHostingController + SwiftUI binding)
   - Implement `AzureLivenessPlugin.swift` (MethodChannel → present VC → resolve FlutterResult)

5. **Example app**
   - Add token input UI + optional image picker + "Start" button
   - Consume `AzureLiveness.startLivenessCheck(...)` and display raw result

6. **Tests**
   - Mock MethodChannel and test argument marshalling + result parsing

7. **Documentation**
   - `README.md`: prerequisites (gated access), iOS SPM setup, Android permissions,
     usage snippet, session flow diagram
   - `CHANGELOG.md`: initial 0.1.0 entry
   - `LICENSE`: choose appropriate license (e.g., MIT)

---

## Constraints & Key Risks

| Constraint | Detail |
|---|---|
| Gated SDK access | Both iOS and Android SDKs require Microsoft approval. Plugin code will compile but the SDK artifacts won't resolve without access. |
| iOS SPM-only distribution | No CocoaPod for AzureAIVisionFaceUI; requires manual Xcode SPM setup or Flutter SPM experimental support. |
| Liveness decision not in client | `livenessDecision` (realface/spoof) is server-side only; the plugin only returns `digest` and `resultId`. |
| Android Activity result pattern | The pending `FlutterResult` must survive Activity recreation; plugin must handle this carefully with `ActivityResultLauncher` or store state safely. |
| Camera permissions | Android 6+ requires runtime permission; the SDK may handle this internally, but the plugin should document fallback behavior. |

---

## Verification

1. Run `flutter analyze` — zero warnings/errors
2. Run `flutter test` — all mock channel tests pass
3. Run `./scripts/coverage.sh` — coverage ≥ 80% (baseline: 100%)
4. Open `example/` on an iOS 14+ simulator/device:
   - Paste a valid `sessionAuthorizationToken` → tap "Start" → native liveness UI appears
   - On completion → result panel shows `digest` or error code
5. Open `example/` on an Android API 24+ emulator/device and repeat step 4
6. Test liveness-with-verify by selecting a reference image before starting
