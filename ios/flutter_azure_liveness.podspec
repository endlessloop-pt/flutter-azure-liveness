#
# flutter_azure_liveness.podspec
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_azure_liveness.podspec` to validate before publishing.
#
# ──────────────────────────────────────────────────────────────────────────────
# IMPORTANT — AzureAIVisionFaceUI dependency
# ──────────────────────────────────────────────────────────────────────────────
# The Azure AI Vision Face UI SDK is distributed **as a Swift Package only**
# (https://github.com/Azure/AzureAIVisionFaceUI). CocoaPods cannot resolve
# SPM packages natively, so consumers must add the dependency to Xcode manually:
#
#   Option A (recommended — Flutter ≥ 3.22 with SPM support enabled):
#     Enable Flutter's experimental SPM support and place a Package.swift
#     alongside this podspec that declares the AzureAIVisionFaceUI dependency.
#     See https://docs.flutter.dev/packages-and-plugins/swift-package-manager
#
#   Option B (manual Xcode setup):
#     1. Open the Runner.xcworkspace in Xcode.
#     2. File → Add Package Dependencies…
#     3. Paste: https://github.com/Azure/AzureAIVisionFaceUI
#     4. Select the Runner target and add AzureAIVisionFaceUI to "Link Binary
#        With Libraries".
#     5. Then uncomment the import in LivenessViewController.swift.
#
# Access to the SDK is GATED — request access from Microsoft before the package
# can be resolved. See README for instructions.
# ──────────────────────────────────────────────────────────────────────────────

Pod::Spec.new do |s|
  s.name             = 'flutter_azure_liveness'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin wrapping the Azure AI Vision Face Liveness UI SDK.'
  s.description      = <<-DESC
    A Flutter plugin that wraps the Azure AI Vision Face Liveness UI SDK for iOS
    and Android. Provides a simple Dart API to trigger the native liveness
    detection UI and receive a structured LivenessResult.
  DESC
  s.homepage         = 'https://github.com/endlessloop/flutter-azure-liveness'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Endless Loop' => 'dev@endlessloop.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'AzureAIVisionFaceUI'
  s.platform         = :ios, '14.0'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                      => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.9'
end
