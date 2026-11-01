# Shared native recognition models

Android and iOS compile these exact files into their native app resources:

- `gesture_recognizer.task`: hand landmarks, world landmarks, handedness and gesture scores.
- `blaze_face_short_range.tflite`: face position and association box.
- `face_landmarker.task`: eye blendshapes and lip/eye landmarks.

Android's source set is configured in `android/app/build.gradle`. Xcode's Models
group references this directory. Native loaders use the same filenames, so keep
model filename changes synchronized with both hosts. Do not create per-platform
copies. Source URLs and checksums for the face models are in the adjacent JSON
files; hand model provenance is in `gesture_recognizer.task` and the bundled MediaPipe license. License:
`MediaPipe-LICENSE.txt` (Apache 2.0).
