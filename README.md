# flutter_azure_liveness

A Flutter plugin that wraps the **Azure AI Vision Face Liveness UI SDK** for iOS and Android.

Provides a simple Dart API to launch the native liveness detection UI and receive a structured
`LivenessResult` — without bundling any backend or session logic in the plugin.

---

## Prerequisites

### Gated SDK access

Both the iOS and Android Azure AI Vision Face Liveness SDKs are **gated artifacts** distributed
by Microsoft. You must request access before the packages can be resolved:

- Request access at the [Azure AI Vision Face GitHub repo](https://github.com/Azure/azure-ai-vision-sdk)
  or via your Microsoft Azure contact.

### iOS — Swift Package (AzureAIVisionFaceUI)

The iOS SDK is distributed **only as a Swift Package** from:
`https://github.com/Azure/AzureAIVisionFaceUI`

Because CocoaPods cannot natively resolve SPM dependencies, you must add the package to the
host application's Xcode workspace using one of the following options:

#### Option A — Flutter experimental SPM support (Flutter ≥ 3.22, recommended)

1. Enable Flutter's SPM support:
   ```
   flutter config --enable-swift-package-manager
   ```
2. Add a `Package.swift` alongside the podspec that declares the `AzureAIVisionFaceUI` dependency.
   See [Flutter SPM documentation](https://docs.flutter.dev/packages-and-plugins/swift-package-manager).

#### Option B — Manual Xcode setup (fallback)

1. Open `example/ios/Runner.xcworkspace` (or your app's workspace) in Xcode.
2. **File → Add Package Dependencies…**
3. Paste the URL: `https://github.com/Azure/AzureAIVisionFaceUI`
4. Select the **Runner** target and add `AzureAIVisionFaceUI` to **Link Binary With Libraries**.
5. In `ios/Classes/LivenessViewController.swift`, uncomment:
   ```swift
   import AzureAIVisionFaceUI
   ```
   and replace the placeholder `embedLivenessView()` body with the production block
   (see the commented-out code in that file).

> **Note:** A GitHub Personal Access Token (PAT) with repo access granted by Microsoft
> is required to resolve this package.

### Android — Maven Central (azure-ai-vision-face-ui)

The Android SDK is published to Maven Central but access is gated:

1. Obtain Maven credentials from Microsoft.
2. Add credentials to your `~/.gradle/gradle.properties`:
   ```
   mavenUser=<your-username>
   mavenPassword=<your-token>
   ```
3. Update `android/build.gradle` if a custom Maven repository URL is required:
   ```groovy
   repositories {
       maven {
           url = uri("https://pkgs.dev.azure.com/...")
           credentials { ... }
       }
   }
   ```

The plugin's `android/build.gradle` already declares:
```groovy
implementation("com.azure:azure-ai-vision-face-ui:+")
```

---

## Usage

### 1. Obtain a session token (server-side)

```
POST https://<endpoint>/face/v1.2-preview.1/detectLiveness-sessions
```

Your server calls the Azure Face REST API and returns the `authToken` to the client.

### 2. Start the liveness check

```dart
import 'package:flutter_azure_liveness/flutter_azure_liveness.dart';

// Liveness-only
final result = await AzureLiveness.startLivenessCheck(
  sessionToken: authToken,
);

// Liveness-with-verify (pass a reference face image)
final result = await AzureLiveness.startLivenessCheck(
  sessionToken: authToken,
  verifyImageBytes: referenceImageBytes, // Uint8List
);
```

### 3. Handle the result

```dart
if (result.isSuccess) {
  print('Digest:    ${result.digest}');
  print('Result ID: ${result.resultId}');
  // → Query your server: GET /livenessSessions/{sessionId}/result
  //   to obtain the final livenessDecision (realface / spoof).
} else {
  print('Error: ${result.errorCode} — ${result.errorMessage}');
}
```

---

## End-to-end session flow

```
Host App                Plugin                Azure Face Service
────────────────────────────────────────────────────────────────
1. POST /detectLiveness-sessions ──────────────────────────────► { sessionId, authToken }
2. AzureLiveness.startLivenessCheck(sessionToken: authToken)
   │
3. [Native SDK UI launches, guides user, communicates with Azure]
   │                              ───────────────────────────────►
   │                                                              (SDK calls Face service)
   ◄── LivenessResult(digest, resultId) OR error
4. GET /livenessSessions/{sessionId}/result ────────────────────► { livenessDecision }
5. DELETE /livenessSessions/{sessionId}    ────────────────────►
```

> The `livenessDecision` (`realface` / `spoof`) is **server-side only** — it is not included
> in the client-side `LivenessResult`. Your app server must query the Azure REST API (step 4).

---

## API reference

### `AzureLiveness.startLivenessCheck`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `sessionToken` | `String` | Yes | Auth token from Azure Face service |
| `verifyImageBytes` | `Uint8List?` | No | Reference face image (enables liveness-with-verify) |
| `deviceCorrelationId` | `String?` | No | Caller-supplied diagnostic identifier |

### `LivenessResult`

| Field | Type | Present when |
|---|---|---|
| `isSuccess` | `bool` | Always |
| `digest` | `String?` | `isSuccess == true` |
| `resultId` | `String?` | `isSuccess == true` |
| `errorCode` | `String?` | `isSuccess == false` |
| `errorMessage` | `String?` | `isSuccess == false` |

---

## Platform requirements

| Platform | Minimum version |
|---|---|
| iOS | 14.0 |
| Android | API 24 (Android 7.0) |
| Flutter | 3.0 |
| Dart | 3.0 |

---

## Permissions

### Android

The plugin declares these permissions in its `AndroidManifest.xml` (merged automatically):

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.VIBRATE" />
```

The Azure SDK handles the runtime `CAMERA` permission request on Android 6+. If the user
denies the permission, the SDK surfaces a `LivenessDetectionError` with an appropriate
`kind`, which the plugin maps to a `LivenessResult.failure`.

### iOS

Add the camera usage description to your app's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for the liveness check.</string>
```

---

## License

MIT — see [LICENSE](LICENSE).
