The authoritative native MediaPipe models live in models/ at the project root.
Both Android and iOS bundle the same files from there.

Android loader: android/app/src/main/kotlin/com/grozziie/hand_gesture/HandGestureRecognizer.kt
iOS loader: ios/Runner/Vision/HandGestureRecognizer.swift
Flutter bridge: lib/features/hand_tracking/hand_recognition.dart

This directory does not contain an active Flutter/TFLite model.
See docs/ARCHITECTURE.md and docs/TUTORIALS.md for the current pipeline.
