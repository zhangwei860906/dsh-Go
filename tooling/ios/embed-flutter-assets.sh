#!/usr/bin/env bash
# Flutter shares its pubspec with the HarmonyOS SDK. Filter only Xcode's staged
# framework and have Flutter embed it normally after its resource seal is current.
set -euo pipefail
framework="$BUILT_PRODUCTS_DIR/App.framework"
changed="$("$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  --packages="$FLUTTER_ROOT/packages/flutter_tools/.dart_tool/package_config.json" \
  "$SRCROOT/../../tooling/ios/select-flutter-assets.dart" "$framework/flutter_assets")"
if [[ "$changed" == 'updated' ]] || ! /usr/bin/codesign --verify "$framework"; then
  identity=-
  if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO && "${CODE_SIGNING_REQUIRED:-YES}" != NO ]]; then
    identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  fi
  /usr/bin/codesign --force --sign "$identity" --timestamp=none "$framework"
fi
exec /bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" embed_and_thin
