# Hapus build folder secara manual
rm -rf build/
rm -rf android/.gradle/
rm -rf android/app/build/

# Build ulang
flutter build apk --release