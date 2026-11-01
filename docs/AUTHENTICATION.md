# Local demonstration authentication

[Project guide](../README.md)

`main.dart` injects `DemoAuthApi` and `DemoSocialBrowser`. The default network
transport is disabled, and its placeholder origin is `demo.invalid`.

- Sample account: `demo@example.com` / `Demo1234!` (prefilled on Login).
- Registration, code login and reset use the visible demo code `12345678`.
- Google/Facebook callbacks are produced in process. No provider page opens.
- Local fictional accounts persist in preferences. Passwords are represented by
  hashes, but this is deliberately not a production credential store.
- Sessions use the platform secure store under the demo's own app ID.
- Logout and password reset invalidate local sessions. Fresh installation and
  system keychain behavior should still be checked on a physical iPhone.

Use fictional information only. No email delivery, OAuth verification, remote
account, recovery assurance or server-side security is provided by this adapter.
