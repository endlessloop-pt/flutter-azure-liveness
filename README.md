# flutter_azure_liveness

A Flutter plugin that wraps the **Azure AI Vision Face Liveness UI SDK** for iOS and Android.

Provides a simple Dart API to launch the native liveness detection UI and receive a structured
`LivenessResult` — without bundling any backend or session logic in the plugin.

---

## Prerequisites

### Gated SDK access

Both the iOS and Android Azure AI Vision Face Liveness SDKs are **gated artifacts** distributed
by Microsoft. You must request access before the packages can be resolved via your Microsoft Azure contact.

### iOS

Follow the setup and access request instructions in the [AzureAIVisionFaceUI repository](https://github.com/Azure/AzureAIVisionFaceUI).

### Android

Follow the setup and access request instructions in the [Azure AI Vision Face UI for Android documentation](https://azure.github.io/azure-sdk-for-android/azure-ai-vision-face-ui/index.html).

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
