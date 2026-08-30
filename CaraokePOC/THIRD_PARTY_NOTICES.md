# Third-party notices

Portions of this software are adapted from **DriveVerse**
(https://github.com/praveetgupta/driveverse), used under the MIT License.

MIT License

Copyright (c) 2026 Praveet Gupta

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Adapted files

| Caraoke file | Adapted from DriveVerse |
|---|---|
| `Sources/CaraokeCore/ActivityUpdatePolicy.swift` | `DriveVerse/LiveActivity/LiveActivityUpdatePolicy.swift` |
| `Sources/CaraokeCore/ActivityUpdateThrottle.swift` | `DriveVerse/LiveActivity/LiveActivityUpdateThrottle.swift` |
| `Sources/CaraokeCore/LRCParser.swift` | `DriveVerse/Core/Lyrics/LRCParser.swift` |
| `Sources/CaraokeCore/TrackMatcher.swift` | `DriveVerse/Core/Lyrics/LyricsMatcher.swift` (vendor type decoupled) |
| `iOS/LyricsActivityController.swift` | `DriveVerse/LiveActivity/LiveActivityController.swift` (reworked to `LyricSnapshot`) |
| `Sources/CaraokeCore/NowPlaying.swift` | `DriveVerse/Core/NowPlaying/NowPlayingSource.swift` (moved to Core for testability) |
| `iOS/AppleMusicSource.swift` | `DriveVerse/Core/NowPlaying/AppleMusicSource.swift` |
| `iOS/RideModeIntents.swift` | `DriveVerse/App/DriveModeIntents.swift` (Ride Mode naming) |
| `Sources/CaraokeCore/SpotifyAuthCore.swift` | `DriveVerse/Core/Auth/SpotifyAuth.swift` (PKCE, token policy, token client) |
| `Sources/CaraokeCore/SpotifySource.swift` | `DriveVerse/Core/NowPlaying/SpotifySource.swift` (official Web API polling) |
| `Sources/CaraokeCore/SyncEngine.swift` | `DriveVerse/Core/Sync/SyncEngine.swift` (position extrapolation + line mapping) |
| `Sources/CaraokeCore/NowPlayingCoordinator.swift` | `DriveVerse/Core/NowPlaying/NowPlayingCoordinator.swift` (arbiter + source pin) |
| `iOS/SpotifyAuth.swift` | `DriveVerse/Core/Auth/SpotifyAuth.swift` (Keychain store, OAuth flow, presenter) |

Deliberately **not** ported: driveverse's `LRCLIBClient` (Caraoke implements
its own provider behind `LyricsRepository` — LRCLIB is the chosen lyrics
source per the locked-decisions document) and `BackgroundKeeper`
(background-location keep-alive is App-Review-rejected per Apple policy; a
store build needs push-updated activities — see
`../research/background-update-strategy.md`).

Spotify integration note (locked decisions): the auth flow is the official
OAuth authorization-code + PKCE flow against accounts.spotify.com. Public
launch gates are non-code — Spotify extended-quota approval and platform
policy clearance for lyric-sync display.
