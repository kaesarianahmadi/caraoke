# Privacy Policy — Caraoke (draft for publication)

Effective date: [launch date]. Contact: support@caraoke.app

## The short version

Caraoke has no server and no accounts. We do not collect, store, or share your
personal data. Trading personal data is antithetical to a utility product, so
the entire product is designed to function on-device.

## What the app processes, and where it stays

| Data | Where it lives | Purpose |
|---|---|---|
| Spotify OAuth tokens | Your device's Keychain only | Read what song is playing (official Spotify Web API) |
| Currently-playing track (title/artist/position) | On-device, in memory | Keep lyrics synchronized; sent as part of HTTPS requests to LRCLIB and Spotify |
| Cached lyrics | Your device's Caches folder (clearable in Settings) | Offline rides + respectful use of LRCLIB |
| Purchase/subscription state | Processed by Apple via StoreKit | Entitlements; Apple's privacy policy governs this |

## Third parties

- **LRCLIB (lrclib.net):** when a song plays, Caraoke requests matching lyrics
  over HTTPS. Requests include the track's title, artist, and duration. LRCLIB
  is a free community lyrics database; its own terms apply. No account, no
  identifier beyond standard connection metadata.
- **Apple (Apple Music via MediaPlayer, StoreKit):** playback is read with
  Apple's public framework; purchases are processed by Apple.
- **Spotify (Web API):** only if you connect Spotify yourself. Read-only
  scopes. Disconnect in Settings at any time (removes the Keychain token).

## What we never do

- No analytics SDKs, no advertising, no tracking, no third-party SDKs at all
- No listening history, no user profiles, no server-side storage
- No data sales or sharing

## Your controls

Settings → "Clear downloaded lyrics cache" removes all cached lyrics.
Disconnecting Spotify removes the stored token. Deleting the app removes
everything.

Children: the app is rated 4+ and collects nothing.

Changes to this policy will be posted on this page with a new effective date.
