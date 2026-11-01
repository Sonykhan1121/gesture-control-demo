# Public iOS native test fixtures

`portrait.jpg` is the official MediaPipe test image, downloaded from
https://storage.googleapis.com/mediapipe-assets/portrait.jpg on 2026-10-27.
SHA256: `a6f11efaa834706db23f275b6115058fa87fc7f14362681e6abe14e82749de3e`.
It is used for local model/serialization regression tests only, not as app UI.
MediaPipe's Apache 2.0 license is retained in `models/MediaPipe-LICENSE.txt`.

iOS also references the existing public hand photos in
`android/app/src/androidTest/assets/` rather than copying them. Their provenance
is documented in `docs/design/fist-live/MODEL.md`. No test fixture here is a
user camera recording or a personal calibration capture.
