import Foundation

/// Build-time feature flags.
enum FeatureFlags {
    /// Spotify connection is ON for public builds (user decision, 2026-08-31).
    ///
    /// Accepted, documented reality: Spotify development mode allows only
    /// **5 allowlisted users** (dashboard → Settings → Users Management);
    /// every other user's API calls return **403**. Extended quota — which
    /// lifts the cap — has been organization-only since May 2025 (250k MAU,
    /// revenue proof, up to 6 weeks review), so an individual cannot qualify
    /// at launch. Therefore the public build ships Spotify as a **beta
    /// feature with graceful degradation**: users who hit the allowlist wall
    /// see a clear "limited beta" state (see `SpotifyAvailability`) instead
    /// of silent breakage, and Apple Music remains the always-works path.
    /// Revisit extended quota once the business can qualify (org + scale).
    static let spotifyEnabled = true

    /// Background lyric relay (mechanism #2, research/background-update-
    /// strategy.md): the app POSTs the lyric schedule + activity push token
    /// here once per session; the relay fires APNs live-activity pushes at
    /// each line boundary so lyrics survive app-process suspension (driving
    /// case). Deployed 2026-09-02: relay/worker.js on caraoke-lyrics.
    /// workers.dev with APNs key 4QTX8TX9K5 (see relay/README.md).
    static let relayBaseURL: URL? = URL(string: "https://caraoke-lyrics-relay.caraoke-lyrics.workers.dev")

    /// Reserved for other build-gated surfaces.
    static let developmentOnlyFeatures = false
}
