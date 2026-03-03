/// The result of a liveness detection session.
class LivenessResult {
  /// Whether the liveness check completed without a platform/system error.
  ///
  /// A `true` value does **not** mean the user is real — it means the SDK
  /// session completed. The caller must query the Azure Face service to obtain
  /// the final `livenessDecision` (realface / spoof).
  final bool isSuccess;

  // --- Success fields ---

  /// Cryptographic integrity string returned by the Azure SDK on success.
  final String? digest;

  /// Session result tracking ID returned by the Azure SDK on success.
  final String? resultId;

  // --- Failure fields ---

  /// Machine-readable error code (e.g. `"UserCanceled"`, `"FaceWithMaskDetected"`).
  final String? errorCode;

  /// Human-readable error description.
  final String? errorMessage;

  const LivenessResult._({
    required this.isSuccess,
    this.digest,
    this.resultId,
    this.errorCode,
    this.errorMessage,
  });

  /// Creates a successful result.
  factory LivenessResult.success({required String digest, String? resultId}) {
    return LivenessResult._(
      isSuccess: true,
      digest: digest,
      resultId: resultId,
    );
  }

  /// Creates a failure result.
  factory LivenessResult.failure({
    required String errorCode,
    String? errorMessage,
  }) {
    return LivenessResult._(
      isSuccess: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  /// Parses the map returned by the native MethodChannel into a [LivenessResult].
  factory LivenessResult.fromMap(Map<String, dynamic> map) {
    if (map['success'] == true) {
      return LivenessResult.success(
        digest: map['digest'] as String,
        resultId: map['resultId'] as String?,
      );
    } else {
      return LivenessResult.failure(
        errorCode: map['errorCode'] as String,
        errorMessage: map['errorMessage'] as String?,
      );
    }
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'LivenessResult.success(digest: $digest, resultId: $resultId)';
    }
    return 'LivenessResult.failure(errorCode: $errorCode, errorMessage: $errorMessage)';
  }
}
