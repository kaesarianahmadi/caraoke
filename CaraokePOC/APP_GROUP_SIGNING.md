# Widget App Group cutover (S7)

Both targets use `group.app.caraoke.ios` for widget state and settings. Spotify credentials remain in Keychain. The TestFlight job requires updated distribution profiles in the repository's `PROFILES_B64` secret.

1. In Apple Developer, register `group.app.caraoke.ios` and enable it on both App IDs: `app.caraoke.ios` and `app.caraoke.ios.widgets`.
2. Regenerate the **Caraoke TF Store Push** and **Caraoke Widgets TF Store** App Store distribution profiles. Both must contain `group.app.caraoke.ios` under `Entitlements:com.apple.security.application-groups`; the app profile must retain production APNs. Keep signing material out of chat and logs.
3. Set `PROFILES_B64` to a base64-encoded ZIP containing exactly these root-level filenames: `Caraoke_TF_Store_Push.mobileprovision` and `Caraoke_Widgets_TF_Store.mobileprovision`. The workflow validates the names, App IDs, App Group, and production push entitlement before signing. Do not commit the profiles.
4. After an authorized signed install, verify both processes read the same state while the phone is locked, and check that widget state no longer makes Keychain calls.

From the directory holding the two verified downloads, a maintainer can update the secret without printing it or triggering CI:

```sh
set -o pipefail
zip -q - Caraoke_TF_Store_Push.mobileprovision Caraoke_Widgets_TF_Store.mobileprovision \
  | base64 | tr -d '\n' | gh secret set PROFILES_B64 --repo kaesarianahmadi/caraoke
```
