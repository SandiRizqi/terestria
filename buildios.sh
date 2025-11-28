# 1. Hapus Podfile.lock dan folder Pods
cd ios
rm -rf Podfile.lock
rm -rf Pods
rm -rf ~/Library/Caches/CocoaPods
rm -rf ~/Library/Developer/Xcode/DerivedData

# 2. Update repository CocoaPods
pod repo update

# 3. Install ulang pods
pod install

# 4. Kembali ke root project
cd ..

# 5. Clean Flutter
flutter clean

# 6. Get dependencies
flutter pub get

# 7. Coba run lagi
flutter run --release