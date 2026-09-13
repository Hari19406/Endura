# ── Endura release R8/ProGuard rules ────────────────────────────────────────
# Applied on top of Flutter's own proguard-android-optimize.txt (see
# app/build.gradle.kts). Enabling minifyEnabled/shrinkResources without these
# risks stripping classes that the SDKs below reach via reflection at
# runtime, which shows up as a crash only in release builds — never in debug.

# ── RevenueCat / purchases_flutter, purchases_ui_flutter ────────────────────
# The SDK deserializes its models (offerings, entitlements, customer info)
# from JSON via reflection; obfuscating/stripping them causes runtime crashes
# or silently empty offerings.
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# ── PostHog / posthog_flutter ────────────────────────────────────────────────
# Event payload and config models are (de)serialized reflectively.
-keep class com.posthog.** { *; }
-dontwarn com.posthog.**

# ── Supabase / supabase_flutter (gotrue, postgrest, realtime, storage) ──────
# Deliberately no Android keep rules here: the Supabase client is pure Dart
# (JSON decoding happens in Dart via manual/generated fromJson, not via any
# Android-side reflection), so R8 on the Java/Kotlin layer never touches it.
# Flutter's Dart AOT compiler has its own separate obfuscation flag
# (`flutter build appbundle --obfuscate`), unrelated to this file.

# ── Firebase Crashlytics ─────────────────────────────────────────────────────
# Firebase's own AARs ship consumer rules, but keep stack traces symbolicated
# and exception types intact so Crashlytics reports stay readable.
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── flutter_foreground_task ──────────────────────────────────────────────────
# Backs the location-typed foreground service that keeps run tracking alive
# with the screen off (see AndroidManifest.xml) — never strip it.
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**
