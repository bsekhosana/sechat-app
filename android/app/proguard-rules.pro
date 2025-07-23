# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Keep SessionApi classes from being removed by R8
-keep class com.strapblaque.sechat.SessionApi { *; }
-keep class com.strapblaque.sechat.SessionApi$** { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionApi { *; }
-keep class com.strapblaque.sechat.SessionApi$FlutterError { *; }
-keep class com.strapblaque.sechat.SessionApi$Result { *; }
-keep class com.strapblaque.sechat.SessionApi$NullableResult { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionIdentity { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionMessage { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionContact { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionGroup { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionAttachment { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionIdentity$Builder { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionMessage$Builder { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionContact$Builder { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionGroup$Builder { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionAttachment$Builder { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionIdentity { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionMessage { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionContact { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionGroup { *; }
-keep class com.strapblaque.sechat.SessionApi$SessionAttachment { *; }
-keep class com.strapblaque.sechat.SessionApi$Result { *; }
-keep class com.strapblaque.sechat.SessionApi$NullableResult { *; }
-keep class com.strapblaque.sechat.SessionApi$FlutterError { *; }

# Keep SessionApiImpl class
-keep class com.strapblaque.sechat.SessionApiImpl { *; }

# Keep SessionCallbackApi classes
-keep class com.strapblaque.sechat.SessionCallbackApi { *; }
-keep class com.strapblaque.sechat.SessionCallbackApi$** { *; }

# Keep all classes in the session package
-keep class com.strapblaque.sechat.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable classes
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep R8 rules
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes Exceptions

# Keep Flutter specific classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Google Play Core classes (Android 14 compatible)
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-keep class com.google.android.play.app-update.** { *; }
-keep class com.google.android.play.review.** { *; } 