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

    /// Reserved for other build-gated surfaces.
    static let developmentOnlyFeatures = false
}
