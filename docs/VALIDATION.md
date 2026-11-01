# Portfolio snapshot validation

Validated on 1 November 2026:

- 402 Flutter tests passed; four tests for the disabled custom color picker skipped.
- Full Flutter analysis reported no issues.
- Android debug APK built successfully as `com.sonykhan.gesture_demo`.
- Unsigned iOS debug app built successfully as `com.sonykhan.gestureDemo`.
- The documentation renderer passed and regenerated 61 portrait/landscape pairs.
- Local auth tests cover sample login, registration, wrong codes, code login,
  reset, old-session rejection, refresh, restart-compatible storage, logout,
  simulated Google/Facebook exchange, and the disabled default HTTP transport.
- Shared camera/recognition Dart, native iOS adapters and all three models match
  the source snapshot exactly. Android native adapters differ only in package
  namespace. Recognition remains camera-driven, not a simulated landmark timer.

These builds do not establish live physical-device acceptance of this separately
identified demo. No installation replaced the production app during preparation.
Historical production test data and recordings are not included.
