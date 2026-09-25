#
# flutter_azure_liveness.podspec
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
# ──────────────────────────────────────────────────────────────────────────────
# AzureAIVisionFaceUI is VENDORED, not resolved
# ──────────────────────────────────────────────────────────────────────────────
# Microsoft distributes this SDK as a Swift Package whose xcframework lives behind
# a gated Git LFS endpoint (msface.visualstudio.com), so resolving it requires an
# Azure DevOps token on every machine and CI runner. Instead we commit the
# xcframework to this repo as a zip and link it via `vendored_frameworks`, which
# needs no token, no SPM, and no manual Xcode setup.
#
# The zip is committed (~33 MB); the expanded .xcframework is gitignored and
# recreated below at `pod install` time.
#
# `prepare_command` is NOT used on purpose: CocoaPods does not run it for pods
# installed with `:path` (which is how Flutter installs every plugin), and when it
# does run it is inconsistent between local and CI builds. A podspec is plain Ruby
# evaluated during `pod install`, so unzipping here runs before CocoaPods globs
# `vendored_frameworks`.
#
# To refresh the SDK, see README "Vendored SDK binaries".
# ──────────────────────────────────────────────────────────────────────────────

frameworks_dir = File.join(__dir__, 'Frameworks')
xcframework    = File.join(frameworks_dir, 'AzureAIVisionFaceUI.xcframework')
archive        = "#{xcframework}.zip"

if !File.directory?(xcframework) && File.exist?(archive)
  Dir.chdir(frameworks_dir) do
    system('unzip', '-oq', File.basename(archive)) or
      raise "flutter_azure_liveness: failed to unzip #{archive}"
  end
end

unless File.directory?(xcframework)
  raise "flutter_azure_liveness: AzureAIVisionFaceUI.xcframework is missing and " \
        "#{archive} was not found. The archive is committed to this repo; if it is " \
        "absent your checkout is incomplete. See README \"Vendored SDK binaries\"."
end

Pod::Spec.new do |s|
  s.name             = 'flutter_azure_liveness'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin wrapping the Azure AI Vision Face Liveness UI SDK.'
  s.description      = <<-DESC
    A Flutter plugin that wraps the Azure AI Vision Face Liveness UI SDK for iOS
    and Android. Provides a simple Dart API to trigger the native liveness
    detection UI and receive a structured LivenessResult.
  DESC
  s.homepage         = 'https://github.com/endlessloop-pt/flutter-azure-liveness'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Endless Loop' => 'dev@endlessloop.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'

  # Vendored Azure SDK — see header.
  s.vendored_frameworks = 'Frameworks/AzureAIVisionFaceUI.xcframework'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                      => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.9'
end
