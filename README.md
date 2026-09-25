# flutter_azure_liveness

A Flutter plugin that wraps the **Azure AI Vision Face Liveness UI SDK** for iOS and Android.

Provides a simple Dart API to launch the native liveness detection UI and receive a structured
`LivenessResult` — without bundling any backend or session logic in the plugin.

---

## Vendored SDK binaries

This plugin **vendors** the Azure AI Vision Face SDK for both platforms, so building it
requires no Microsoft credentials on developer machines or CI.

Microsoft gates the two SDKs unevenly, and vendoring is what closes the gap:

| Platform | Public | Gated — and therefore vendored here |
|---|---|---|
| Android | `com.azure:azure-ai-vision-face-ui` (Maven Central) | Its mandatory transitive dep `azure-ai-vision-face-ui-assets` (native libs + models) is published **only** to Microsoft's Azure DevOps feed → mirrored into `android/m2/` |
| iOS | The SPM repo [Azure/AzureAIVisionFaceUI](https://github.com/Azure/AzureAIVisionFaceUI) | Its `.lfsconfig` points Git LFS at `msface.visualstudio.com` → the xcframework is committed as `ios/Frameworks/AzureAIVisionFaceUI.xcframework.zip` |

The iOS archive is committed zipped (~33 MB, vs 134 MB expanded) to stay under GitHub's
100 MB per-file limit without Git LFS. `ios/flutter_azure_liveness.podspec` expands it at
`pod install` time; the expanded `.xcframework` is gitignored.

> The SDK is redistributable under Microsoft's licence (see `ios/Frameworks/REDIST.txt`),
> but only for internal use. **Keep this repository private** — publishing these binaries,
> including to pub.dev, is not permitted.

### Consuming app setup

Gradle resolves a library's transitive dependencies using the *consuming* project's
repositories, so your app must point at the vendored mirror. In `android/build.gradle`:

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("${project(':flutter_azure_liveness').projectDir}/m2") }
    }
}
```

No iOS setup is needed — CocoaPods links the vendored xcframework automatically. Do **not**
add AzureAIVisionFaceUI as a Swift Package; an `XCRemoteSwiftPackageReference` left in the
Xcode project will resolve against the gated LFS endpoint and reintroduce the token.

### Refreshing the SDK

Needs an Azure DevOps PAT with read access to the `msface/SDK` `AzureAIVision` feed. This is
the only step that uses a credential, and it is run once per upgrade by one person:

Set the version in `android/build.gradle` **first**, then run the script with no
argument so it picks that version up for both platforms:

```bash
AZ_PAT='<pat>' ./scripts/vendor-sdk.sh
```

Passing a version explicitly (`./scripts/vendor-sdk.sh 1.5.0`) is supported and warns if it
disagrees with the pin, but it cannot tell that the pin itself is the wrong target — so
changing the pin first is the safer order.

Then commit `android/m2/` and `ios/Frameworks/`, and unset `AZ_PAT`. Keep both platforms on
the same SDK version; a mismatch compiles fine and diverges only at runtime.

AzureAIVisionFaceUI is a **static** framework (`ar archive`, no `LC_ID_DYLIB`) despite
shipping as an `.xcframework`. Under `use_frameworks!` its code is linked into
`flutter_azure_liveness.framework` rather than embedded as a framework of its own, so its
absence from `Pods-Runner-frameworks.sh` and from `Runner.app/Frameworks/` is correct, not a
misconfiguration — there is no embed step and no code-signing implication. After the first
`pod install`, the wiring to expect is:

```bash
grep OTHER_LDFLAGS ios/Pods/Target\ Support\ Files/flutter_azure_liveness/flutter_azure_liveness.debug.xcconfig
#   OTHER_LDFLAGS = $(inherited) -framework "AzureAIVisionFaceUI"
```

CocoaPods also generates `flutter_azure_liveness-xcframeworks.sh`, which selects the device or
simulator slice at build time. That is what replaces the old hand-written
`FRAMEWORK_SEARCH_PATHS` workaround.

Because nothing is embedded, the SDK's 75 `.lproj` localization bundles would not reach the
app on their own. The podspec copies them in via `s.resources`, so they land in
`flutter_azure_liveness.framework` where `Bundle(for:)` resolves them. If you ever change how
the framework is vendored, check this still holds — missing localizations compile and link
cleanly and only surface as untranslated liveness screens at runtime:

```bash
find build/ios/iphonesimulator/Runner.app -name Localizable.strings | wc -l   # expect 75
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

// Force a specific UI language
final result = await AzureLiveness.startLivenessCheck(
  sessionToken: authToken,
  locale: 'pt-BR',
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
| `locale` | `String?` | No | BCP 47 locale tag for the liveness UI (e.g. `"pt-BR"`, `"en-US"`). Defaults to the device locale when omitted. |

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
