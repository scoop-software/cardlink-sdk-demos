# ============================================================
# R8/ProGuard rules for Cardlink Android demo (releaseOptimized)
# SDK-level rules are provided automatically via consumer-rules.pro
# ============================================================

# --- Strip debug metadata ---
-renamesourcefileattribute ""
-keepattributes !LineNumberTable,!SourceFile

# Remove Kotlin null-check parameter names (leak original variable names)
-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    static void checkNotNullParameter(...);
    static void checkNotNullExpressionValue(...);
    static void checkParameterIsNotNull(...);
    static void checkExpressionValueIsNotNull(...);
}

# --- Credential Manager (password autofill, accessed via reflection) ---
-keep class androidx.credentials.** { *; }
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.gms.auth.api.credentials.** { *; }
-dontwarn androidx.credentials.**

# --- Demo app: Gson-serialized classes (Gson uses reflection for field names) ---
-keep class de.scoopsoftware.cardlink.demo.ui.model.ScanRecordJson { *; }
-keep class de.scoopsoftware.cardlink.demo.ui.model.ApduExchangeJson { *; }
-keepclassmembers class de.scoopsoftware.cardlink.demo.ui.model.** {
    <fields>;
}
