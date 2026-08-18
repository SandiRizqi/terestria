# ============================================================================
# ProGuard / R8 keep rules — Terestria
# ----------------------------------------------------------------------------
# Aktif hanya saat `minifyEnabled true` di build.gradge (build release).
# Menjaga kelas yang dipakai lewat refleksi/JNI agar tidak dihapus/obfuscate
# oleh R8 (mencegah crash release-only). Tambah rule bila muncul "Missing
# class" atau crash ClassNotFound/NoSuchMethod di build release.
# ============================================================================

# ── Flutter engine & plugin registrant ──────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── Firebase / Crashlytics ──────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── GraphHopper 7.0 + JTS + hppc (routing offline, pure-Java tanpa consumer rules) ──
-keep class com.graphhopper.** { *; }
-dontwarn com.graphhopper.**
-keep class com.carrotsearch.hppc.** { *; }
-dontwarn com.carrotsearch.hppc.**
-keep class org.locationtech.jts.** { *; }
-dontwarn org.locationtech.jts.**
# GraphHopper mereferensi kelas Java desktop yang tidak ada di Android:
-dontwarn java.awt.**
-dontwarn javax.**
-dontwarn org.slf4j.**

# Jackson — GraphHopper memakainya (refleksi penuh) untuk serialisasi
# EncodingManager/EncodedValues saat importOrLoad(). TANPA keep ini, R8 meng-
# obfuscate & menghapus no-arg constructor Jackson → runtime error release-only
# "Class ... has no default (no arg) constructor" saat build routing engine.
-keep class com.fasterxml.jackson.** { *; }
-keepclassmembers class com.fasterxml.jackson.** { *; }
-keepattributes *Annotation*,Signature,EnclosingMethod,InnerClasses
-dontwarn com.fasterxml.jackson.**

# ── flutter_local_notifications (pakai Gson + reflection) ────────────────────
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature

# ── mobile_scanner / ML Kit (barcode) ───────────────────────────────────────
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── in_app_update (Play Core / Play In-App Update) ──────────────────────────
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# ── printing / pdf ──────────────────────────────────────────────────────────
-dontwarn com.itextpdf.**

# ── Plugin native lain (umumnya sudah ada consumer rules; jaga-jaga) ────────
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }

# ── Umum: jaga anotasi, inner class, enum ───────────────────────────────────
-keepattributes EnclosingMethod,InnerClasses,Signature
-keepclassmembers enum * { *; }
