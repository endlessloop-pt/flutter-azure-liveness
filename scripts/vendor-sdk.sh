#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# scripts/vendor-sdk.sh
#
# Refresh the vendored Azure AI Vision Face SDK binaries for both platforms.
#
# This is the ONLY step that needs a Microsoft credential, and it is run once per
# SDK upgrade by one person — never by other developers and never in CI. Builds
# consume the committed binaries and need no token at all.
#
# Why each platform needs vendoring:
#   Android  `com.azure:azure-ai-vision-face-ui` is public on Maven Central, but its
#            mandatory transitive dep `azure-ai-vision-face-ui-assets` (native libs +
#            models) is published only to Microsoft's gated Azure DevOps feed.
#   iOS      The SPM repo github.com/Azure/AzureAIVisionFaceUI is public, but the
#            xcframework itself is a Git LFS object hosted on msface.visualstudio.com.
#
# Usage:
#   AZ_PAT='<azure devops PAT>' ./scripts/vendor-sdk.sh [version]
#
# Defaults to the version currently pinned in android/build.gradle.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEED="https://pkgs.dev.azure.com/msface/SDK/_packaging/AzureAIVision/maven/v1/com/azure"
SDK_REPO="https://github.com/Azure/AzureAIVisionFaceUI.git"

# ── Resolve version ───────────────────────────────────────────────────────────
PINNED=$(sed -n 's/.*com\.azure:azure-ai-vision-face-ui:\([0-9][^"]*\)".*/\1/p' \
         "$REPO_ROOT/android/build.gradle" | head -1)
VERSION="${1:-$PINNED}"

if [[ -z "$VERSION" ]]; then
  echo "✗ Could not determine a version. Pass one explicitly: $0 1.5.1" >&2
  exit 1
fi

# The PAT may be supplied either in AZ_PAT, or — preferably — in a file named by
# AZ_PAT_FILE, which keeps it out of argv, the environment and shell history.
if [[ -n "${AZ_PAT_FILE:-}" ]]; then
  if [[ ! -r "$AZ_PAT_FILE" ]]; then
    echo "✗ AZ_PAT_FILE=$AZ_PAT_FILE is not readable." >&2
    exit 1
  fi
  AZ_PAT=$(tr -d '\r\n' < "$AZ_PAT_FILE")
fi

if [[ -z "${AZ_PAT:-}" ]]; then
  echo "✗ No Azure DevOps PAT supplied. Either:" >&2
  echo "    AZ_PAT_FILE=~/.azure-face-pat $0     # preferred: token stays in a file" >&2
  echo "    AZ_PAT='<pat>' $0" >&2
  echo "  The PAT needs read access to the msface/SDK AzureAIVision feed." >&2
  exit 1
fi

echo "▶ Vendoring Azure Face SDK $VERSION"
if [[ "$VERSION" != "$PINNED" ]]; then
  echo "  ⚠ android/build.gradle pins $PINNED — update it to $VERSION to keep"
  echo "    the two platforms in lockstep."
fi

# ── Android: mirror the one coordinate missing from Maven Central ─────────────
M2="$REPO_ROOT/android/m2/com/azure/azure-ai-vision-face-ui-assets/$VERSION"
BASE="azure-ai-vision-face-ui-assets-$VERSION"
if [[ -f "$M2/$BASE.aar" && -f "$M2/$BASE.pom" ]] && unzip -tq "$M2/$BASE.aar" >/dev/null 2>&1; then
  echo "▶ Android: $BASE already vendored and valid — skipping"
  echo "  (delete android/m2/.../$VERSION to force a re-fetch)"
  SKIP_ANDROID=1
fi

if [[ -z "${SKIP_ANDROID:-}" ]]; then
echo "▶ Android: fetching $BASE from the gated feed"
mkdir -p "$M2"
for ext in aar pom; do
  if ! curl -sfSL -u ":$AZ_PAT" \
       -o "$M2/$BASE.$ext" \
       "$FEED/azure-ai-vision-face-ui-assets/$VERSION/$BASE.$ext"; then
    echo "✗ Failed to download $BASE.$ext." >&2
    echo "  Check that $VERSION exists on the feed and the PAT is valid." >&2
    rm -f "$M2/$BASE.$ext"
    exit 1
  fi
done

# An AAR is a zip; if we were served an HTML error page this catches it.
if ! unzip -tq "$M2/$BASE.aar" >/dev/null 2>&1; then
  echo "✗ $M2/$BASE.aar is not a valid archive (auth failure?)." >&2
  exit 1
fi
echo "  ✓ $(du -h "$M2/$BASE.aar" | cut -f1)  $BASE.aar"
echo "  ✓ $(du -h "$M2/$BASE.pom" | cut -f1)  $BASE.pom"
fi

# ── iOS: pull the xcframework out of gated LFS and commit it as a zip ─────────
FRAMEWORKS="$REPO_ROOT/ios/Frameworks"
ARCHIVE="$FRAMEWORKS/AzureAIVisionFaceUI.xcframework.zip"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▶ iOS: cloning $SDK_REPO at tag $VERSION"
# GIT_LFS_SKIP_SMUDGE is essential. Without it the clone tries to fetch the LFS
# objects itself, using whatever credential helper happens to be configured
# globally for msface.visualstudio.com. A helper that supplies only a password
# and no username makes git prompt for one, and in a non-interactive shell
# (stdin at /dev/null) that blocks forever instead of failing. We skip smudge on
# clone and do the download below with an explicit username+password.
# GIT_TERMINAL_PROMPT=0 turns any remaining auth gap into an immediate error.
GIT_LFS_SKIP_SMUDGE=1 GIT_TERMINAL_PROMPT=0 \
  git clone --quiet --depth 1 --branch "$VERSION" "$SDK_REPO" "$WORK/sdk"

echo "▶ iOS: pulling the xcframework from gated LFS (~128 MB)"
# The PAT is passed via the environment, never as an argv entry.
GIT_TERMINAL_PROMPT=0 git -C "$WORK/sdk" \
    -c 'credential.helper=' \
    -c 'credential.helper=!f() { test "$1" = get && printf "username=pat\npassword=%s\n" "$AZ_PAT"; }; f' \
    lfs pull

BIN="$WORK/sdk/AzureAIVisionFaceUI.xcframework/ios-arm64_arm64e/AzureAIVisionFaceUI.framework/AzureAIVisionFaceUI"
if [[ ! -f "$BIN" ]]; then
  echo "✗ xcframework binary not found after 'git lfs pull'." >&2
  exit 1
fi
# A smudge failure leaves a ~130-byte pointer file instead of the real binary.
BYTES=$(stat -f%z "$BIN" 2>/dev/null || stat -c%s "$BIN")
if (( BYTES < 10000000 )); then
  echo "✗ $BIN is only $BYTES bytes — this is a Git LFS pointer, not the binary." >&2
  echo "  The PAT was likely rejected by msface.visualstudio.com." >&2
  exit 1
fi

echo "▶ iOS: archiving the xcframework"
mkdir -p "$FRAMEWORKS"
# Build the archive in the temp dir and move it into place only on success, so a
# failed zip cannot destroy the previously vendored archive.
( cd "$WORK/sdk" && zip -qr9 "$WORK/new.zip" AzureAIVisionFaceUI.xcframework )
if ! unzip -tq "$WORK/new.zip" >/dev/null 2>&1; then
  echo "✗ Produced archive failed its integrity check; keeping the existing one." >&2
  exit 1
fi
mv "$WORK/new.zip" "$ARCHIVE"
# Ship Microsoft's notices beside the binary (licence requires they stay intact).
cp "$WORK/sdk/LICENSE.md" "$WORK/sdk/ThirdPartyNotices.txt" "$WORK/sdk/REDIST.txt" "$FRAMEWORKS/"
# Drop any stale expansion so the next `pod install` unpacks the new archive.
rm -rf "$FRAMEWORKS/AzureAIVisionFaceUI.xcframework"

echo "  ✓ $(du -h "$ARCHIVE" | cut -f1)  $(basename "$ARCHIVE")"
echo ""
echo "────────────────────────────────────────"
echo "  Vendored Azure Face SDK $VERSION"
echo "  Android : android/m2/…/$VERSION/"
echo "  iOS     : ios/Frameworks/AzureAIVisionFaceUI.xcframework.zip"
echo "────────────────────────────────────────"
echo ""
echo "Next:"
echo "  1. Confirm android/build.gradle pins $VERSION"
echo "  2. git add android/m2 ios/Frameworks && git commit"
echo "  3. Unset AZ_PAT — no build needs it"
