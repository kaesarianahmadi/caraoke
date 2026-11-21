# Widget App Group cutover (S7)

The app and widget distribution profiles used by `.github/workflows/ci.yml` do not grant `group.app.caraoke.ios`. The file store is tested, but production still uses Keychain for widget state. Do not switch storage or add entitlements until both signing profiles are ready.

1. In Apple Developer, register `group.app.caraoke.ios` and enable it on both App IDs: `app.caraoke.ios` and `app.caraoke.ios.widgets`.
2. Regenerate the **Caraoke TF Store Push** and **Caraoke Widgets TF Store** App Store distribution profiles. Both must contain `group.app.caraoke.ios` under `Entitlements:com.apple.security.application-groups`; the app profile must retain production APNs. Keep signing material out of chat and logs.
3. Provide the two profiles via the approved signing channel. Verify and update the CI signing inputs before wiring the app and extension to `WidgetStateFiles`. The current workflow copies `CaraokePOC/profiles/*.mobileprovision`; it does not read `PROFILES_B64` despite the older audit guidance.
4. Cut over state and settings to the shared container, keep Spotify credentials in Keychain, and use `WidgetStateFiles.replace` for repair publication. Verify an authorized signed install, both processes reading the same state, and the absence of playback-state Keychain calls.
