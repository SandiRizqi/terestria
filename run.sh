#cd /Users/sandi/VScode/Android/geoform_app

# Clean project
flutter clean
rm -rf android/.gradle
rm -rf android/build
rm -rf android/app/build

# Get dependencies
flutter pub get
flutter build apk --release
# Build
flutter run