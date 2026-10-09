#!/usr/bin/env bash
# Run on the host with the phone connected and USB debugging enabled.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
cp build/app/outputs/flutter-apk/app-release.apk smart_doc_search-v0.1.9.apk
adb_args=()
if [[ $# -gt 0 ]]; then adb_args=(-s "$1"); fi
adb "${adb_args[@]}" install -r smart_doc_search-v0.1.9.apk
adb "${adb_args[@]}" shell am start -n com.smartdoc.search.smart_doc_search/.MainActivity
