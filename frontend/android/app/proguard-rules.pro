# Keep Flutter engine and platform integration classes
-keep class io.flutter.embedding.engine.FlutterEngine { *; }
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }
-keep class io.flutter.plugin.common.MethodChannel { *; }

# Keep classes used by plugins via reflection
-keep class io.flutter.plugin.** { *; }
-keep class com.google.android.material.** { *; }

# Keep app entry points and generated plugins
-keep class com.dixit.monophone.** { *; }
-keep class com.yourcompany.minimalist_launcher.** { *; }

# Keep native library loading
-keep class java.lang.ClassLoader {
    public java.lang.Class loadClass(java.lang.String);
}

# Remove logging in production
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# Keep parcelable classes from Kotlin
-keepclassmembers class * implements android.os.Parcelable {
  public static final ** CREATOR;
}
