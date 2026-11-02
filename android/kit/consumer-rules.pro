# The Swift side reaches the generated bindings through JNI, which R8 cannot see
# (swift-java's Android guide).
-keep class com.fouteox.biathlon.kit.** { *; }
-keep interface com.fouteox.biathlon.kit.** { *; }
