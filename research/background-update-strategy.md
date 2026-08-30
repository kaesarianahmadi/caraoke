# Background Lyric Updates — Strategy Spike (Phase A Step 3)

Status: **decision framework + groundwork** (2026-08-30). The empirical answer
lands in Phase C Step 11 on real hardware; this document defines the options,
the plan, and what is already built so the decision is a flip, not a project.

## The problem

Caraoke reads Apple Music via the public MediaPlayer framework (no token, no
backend). While the app is **foregrounded**, everything works. Once the phone
locks (the normal driving case: phone in pocket/dock, Music playing via
CarPlay), iOS suspends the app and the Live Activity stops receiving lyric
line updates. Every competitor review complaint ("stops updating", "stuck on
the previous song", "have to reopen the app while driving") is this problem
failing.

Constraints:
- Location keep-alive (driveverse's BackgroundKeeper) is explicitly **App
  Review-rejected** — never ported (see driveverse audit).
- Silent-audio keep-alive — same rejection category. Off the table.
- The Live Activity itself CAN be *updated* from the background — the app
  just needs runtime or a push.

## Candidate mechanisms

| # | Mechanism | How | Pros | Cons / Risks | Verdict |
|---|---|---|---|---|---|
| 1 | **Frequent-updates entitlement** | `NSSupportsLiveActivitiesFrequentUpdates = YES` + measured behavior | Zero backend, zero cost; Apple-documented for timer/score-style activities | Apple documents the system budget for frequent updates; effect on background suspension limits is empirical — MUST be measured on device | Test first (Phase C): add key, measure update longevity while locked |
| 2 | **Push-updated Live Activities (APNs relay)** | One session activity + `pushType: .liveActivity`; tiny relay (Cloudflare Worker / Vercel edge, free tier) receives lyric-line requests from… whom? | Store-safe by design (Apple's own recommended path); survives indefinite locking | Needs: APNs key + relay + *the app cannot push to itself* — the relay must generate line updates from song position, meaning the app must send the full lyric schedule + start time ONCE to the relay at session start, or poller-side fetch | Fallback if #1 underdelivers; pre-build the design below |
| 3 | **Foreground-window behavior** | Do nothing extra; iOS grants a short post-backgrounding window | Free | A 3–5 min song outruns any grace window | Not sufficient alone; measure the actual window in Phase C |

## The push-relay design if #2 is needed (pre-built answer)

Stateless, secret-less relay (free tiers only):

```text
App (session start)
  ├─ computes full lyric schedule for the track (lines + startEpochMs)
  ├─ POSTs {activityPushToken, schedule, endAt} to relay (HTTPS, no auth needed
  │   beyond a random capability token embedded in the URL path)
  └─ iOS сама delivers updates meanwhile

Relay (edge function, stateless):
  ├─ receives schedule, schedules line-boundary events via APNs
  │   (auth key stored as relay secret — the ONLY server-side secret)
  └─ sends ActivityKit push payloads {currentLine, nextLine, staleDate}
```

- Cost: ~$0 at MVP scale (Cloudflare Workers free tier = 100k req/day).
- No user accounts, no lyrics stored server-side beyond one session window.
- The relay must be bullet-proof on rate limits: line-level updates only,
  coalescing already implemented client-side maps 1:1 to push payloads.

## Groundwork already in place

- Session-spanning activity design (one activity per ride; track changes are
  plain updates) — ported in `CaraokeActivityController`.
- Line-change-only update policy + throttling/coalescing
  (`ActivityUpdatePolicy`, `ActivityUpdateThrottle`) — exactly the shape
  push payloads need.
- `LyricsRepository` returns the full `LyricTrack` (line schedule) at match
  time — schedule generation for a relay is `track.lines` + a start timestamp.

## Phase C measurement plan (Step 11 checklist)

1. Build with `NSSupportsLiveActivitiesFrequentUpdates = YES`.
2. Start Ride Mode → lock phone → CarPlay playing → stopwatch:
   time until last received line update (mechanism #1 alone).
3. Repeat with app foregrounded-but-screen-off (CarPlay HDMI/wireless case).
4. Repeat for Spotify source (network polling from background — likely
   worse; expect mechanism #2 to be Spotify's requirement).
5. Log every update timestamp; compare against the lyric schedule
   (deterministic probes: write update timestamps into the activity).

## Decision rule

- #1 survives a full 4-minute song with ≤2 s drift → ship MVP with #1 only.
- Else → MVP ships with #2 (relay) from day one; the relay work is
  pre-designed above and small.
