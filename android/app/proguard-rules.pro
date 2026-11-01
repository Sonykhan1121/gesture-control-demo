# MediaPipe uses protobuf-lite message schemas that look up instance fields by
# their generated names. R8 otherwise removes fields such as SystemInfo.platform_
# and recognition fails during native task initialization in release builds.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}

# MediaPipe's JNI entry points and Flogger's stack-based caller lookup also
# depend on class/method identities. Keep this native integration boundary.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.common.flogger.** { *; }

# Optional profiling/template APIs and a source annotation are not shipped in
# the Tasks AAR. None is used by the camera recognizers. R8 lists these exact
# optional references when preserving the JNI framework above.
-dontwarn com.google.auto.value.extension.memoized.Memoized
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
