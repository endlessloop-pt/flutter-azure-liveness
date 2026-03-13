import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_azure_liveness/flutter_azure_liveness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('azure_liveness');
  final List<MethodCall> calls = [];

  setUp(() => calls.clear());

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // Helper: register a mock handler that records calls and returns [response].
  void mockChannel(Map<String, dynamic> response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  }

  // ── LivenessResult model ───────────────────────────────────────────────────

  group('LivenessResult', () {
    test('success factory populates fields', () {
      final r = LivenessResult.success(digest: 'abc', resultId: 'rid1');
      expect(r.isSuccess, isTrue);
      expect(r.digest, 'abc');
      expect(r.resultId, 'rid1');
      expect(r.errorCode, isNull);
      expect(r.errorMessage, isNull);
    });

    test('success factory with null resultId', () {
      final r = LivenessResult.success(digest: 'abc');
      expect(r.resultId, isNull);
    });

    test('failure factory populates fields', () {
      final r = LivenessResult.failure(
          errorCode: 'UserCanceled', errorMessage: 'User closed');
      expect(r.isSuccess, isFalse);
      expect(r.errorCode, 'UserCanceled');
      expect(r.errorMessage, 'User closed');
      expect(r.digest, isNull);
      expect(r.resultId, isNull);
    });

    test('failure factory with null errorMessage', () {
      final r = LivenessResult.failure(errorCode: 'FaceNotFound');
      expect(r.errorMessage, isNull);
    });

    test('fromMap parses success response', () {
      final r = LivenessResult.fromMap(
          {'success': true, 'digest': 'B0A803', 'resultId': 'abc123'});
      expect(r.isSuccess, isTrue);
      expect(r.digest, 'B0A803');
      expect(r.resultId, 'abc123');
    });

    test('fromMap parses success with null resultId', () {
      final r = LivenessResult.fromMap(
          {'success': true, 'digest': 'X', 'resultId': null});
      expect(r.resultId, isNull);
    });

    test('fromMap parses failure response', () {
      final r = LivenessResult.fromMap({
        'success': false,
        'errorCode': 'FaceWithMaskDetected',
        'errorMessage': 'Mask detected',
      });
      expect(r.isSuccess, isFalse);
      expect(r.errorCode, 'FaceWithMaskDetected');
      expect(r.errorMessage, 'Mask detected');
    });

    test('fromMap parses failure with null errorMessage', () {
      final r = LivenessResult.fromMap(
          {'success': false, 'errorCode': 'Unknown', 'errorMessage': null});
      expect(r.errorMessage, isNull);
    });

    test('toString describes success', () {
      final r = LivenessResult.success(digest: 'd', resultId: 'r');
      expect(r.toString(), contains('success'));
      expect(r.toString(), contains('d'));
    });

    test('toString describes failure', () {
      final r = LivenessResult.failure(errorCode: 'E', errorMessage: 'msg');
      expect(r.toString(), contains('failure'));
      expect(r.toString(), contains('E'));
    });
  });

  // ── AzureLiveness.startLivenessCheck ──────────────────────────────────────

  group('AzureLiveness.startLivenessCheck', () {
    test('sends correct method name', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(sessionToken: 'tok');
      expect(calls.single.method, 'startLivenessCheck');
    });

    test('sends sessionToken argument', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(sessionToken: 'my-token');
      final args = calls.single.arguments as Map;
      expect(args['sessionToken'], 'my-token');
    });

    test('does not send verifyImageBytes when omitted', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(sessionToken: 'tok');
      final args = calls.single.arguments as Map;
      expect(args.containsKey('verifyImageBytes'), isFalse);
    });

    test('sends verifyImageBytes when provided', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      mockChannel({'success': true, 'digest': 'd', 'resultId': 'r'});
      await AzureLiveness.startLivenessCheck(
        sessionToken: 'tok',
        verifyImageBytes: bytes,
      );
      final args = calls.single.arguments as Map;
      expect(args['verifyImageBytes'], bytes);
    });

    test('does not send deviceCorrelationId when omitted', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(sessionToken: 'tok');
      final args = calls.single.arguments as Map;
      expect(args.containsKey('deviceCorrelationId'), isFalse);
    });

    test('sends deviceCorrelationId when provided', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(
        sessionToken: 'tok',
        deviceCorrelationId: 'corr-123',
      );
      final args = calls.single.arguments as Map;
      expect(args['deviceCorrelationId'], 'corr-123');
    });

    test('does not send locale when omitted', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(sessionToken: 'tok');
      final args = calls.single.arguments as Map;
      expect(args.containsKey('locale'), isFalse);
    });

    test('sends locale when provided', () async {
      mockChannel({'success': true, 'digest': 'd', 'resultId': null});
      await AzureLiveness.startLivenessCheck(
        sessionToken: 'tok',
        locale: 'pt-BR',
      );
      final args = calls.single.arguments as Map;
      expect(args['locale'], 'pt-BR');
    });

    test('returns LivenessResult.success on success response', () async {
      mockChannel({'success': true, 'digest': 'B0A803', 'resultId': 'abc123'});
      final result =
          await AzureLiveness.startLivenessCheck(sessionToken: 'tok');
      expect(result.isSuccess, isTrue);
      expect(result.digest, 'B0A803');
      expect(result.resultId, 'abc123');
    });

    test('returns LivenessResult.failure on failure response', () async {
      mockChannel({
        'success': false,
        'errorCode': 'UserCanceled',
        'errorMessage': 'User closed the liveness screen',
      });
      final result =
          await AzureLiveness.startLivenessCheck(sessionToken: 'tok');
      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'UserCanceled');
      expect(result.errorMessage, 'User closed the liveness screen');
    });

    test('propagates PlatformException on channel error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'NO_ACTIVITY', message: 'No activity');
      });
      expect(
        () => AzureLiveness.startLivenessCheck(sessionToken: 'tok'),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
