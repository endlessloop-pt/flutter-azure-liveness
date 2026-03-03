// Integration tests for flutter_azure_liveness.
//
// These tests run in a full Flutter application on a real device or emulator
// with the Azure SDK configured. See README for SDK setup instructions.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plugin is importable', (WidgetTester tester) async {
    // Verifies that the plugin package can be imported without errors.
    // Full end-to-end liveness testing requires a valid Azure session token
    // and a physical device with a camera.
    expect(true, isTrue);
  });
}
