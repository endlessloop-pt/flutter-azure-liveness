import 'package:flutter/services.dart';

import 'liveness_result.dart';

/// Entry point for the Azure AI Vision Face Liveness plugin.
///
/// Call [startLivenessCheck] to launch the native liveness detection UI.
/// The host app is responsible for obtaining the [sessionToken] from the
/// Azure Face service **before** calling this method, and for querying the
/// service **after** to retrieve the final `livenessDecision`.
class AzureLiveness {
  AzureLiveness._(); // coverage:ignore-line

  static const _channel = MethodChannel('azure_liveness');

  /// Launches the native liveness detection UI and returns a [LivenessResult].
  ///
  /// - [sessionToken]: Required. The `authToken` returned by the
  ///   `POST /detectLiveness-sessions` Azure Face API call.
  /// - [verifyImageBytes]: Optional. Provide a reference face image (JPEG/PNG
  ///   bytes) to run in **liveness-with-verify** mode. Omit for liveness-only.
  /// - [deviceCorrelationId]: Optional. A caller-supplied identifier logged
  ///   with the session for diagnostics.
  ///
  /// Returns a [LivenessResult] whose [LivenessResult.isSuccess] is `true` when
  /// the SDK session completed (user passed the UI flow). A `true` result does
  /// **not** imply the liveness decision — query the Azure REST API for that.
  ///
  /// Throws a [PlatformException] if the plugin encounters a system-level error
  /// (e.g. no Activity, permissions denied at OS level).
  static Future<LivenessResult> startLivenessCheck({
    required String sessionToken,
    Uint8List? verifyImageBytes,
    String? deviceCorrelationId,
  }) async {
    final args = <String, dynamic>{
      'sessionToken': sessionToken,
      if (verifyImageBytes != null) 'verifyImageBytes': verifyImageBytes,
      if (deviceCorrelationId != null) 'deviceCorrelationId': deviceCorrelationId,
    };

    final result = await _channel.invokeMethod<Map>('startLivenessCheck', args);
    return LivenessResult.fromMap(Map<String, dynamic>.from(result!));
  }
}
