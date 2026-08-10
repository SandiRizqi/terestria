#!/usr/bin/env bash
set -e

# ============================================================================
# Build RILIS Terestria — AAB (Play Store) + obfuscation Dart.
# ----------------------------------------------------------------------------
# - R8 (Android/Java) aktif via build.gradle (minify + shrinkResources).
#   mapping.txt otomatis di-upload ke Crashlytics.
# - --obfuscate mengacak kode Dart; --split-debug-info menaruh SYMBOLS Dart
#   ke folder ber-versi. SYMBOLS WAJIB DISIMPAN per rilis untuk membaca
#   crash report Dart:  flutter symbolize -i <trace> -d <symbols>/app.android-arm64.symbols
# ============================================================================

# Ambil versi dari pubspec.yaml (mis. 4.3.7+33)
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
SYMBOLS_DIR="release_symbols/${VERSION}"

echo "🧹 Membersihkan build lama..."
rm -rf build/
rm -rf android/.gradle/
rm -rf android/app/build/

mkdir -p "${SYMBOLS_DIR}"

echo "🏗️  Build AAB release + obfuscate (symbols → ${SYMBOLS_DIR}) ..."
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info="${SYMBOLS_DIR}"

echo ""
echo "✅ Selesai."
echo "   AAB     : build/app/outputs/bundle/release/app-release.aab"
echo "   Symbols : ${SYMBOLS_DIR}  ← SIMPAN! diperlukan untuk symbolicate crash Dart"
echo ""
echo "Uji AAB sebelum publish (butuh bundletool):"
echo "  bundletool build-apks --bundle=build/app/outputs/bundle/release/app-release.aab \\"
echo "    --output=build/app.apks --local-testing"
echo "  bundletool install-apks --apks=build/app.apks"
