import SwiftUI
import UIKit

/// Home screen (following competitor layout IMG_5085):
/// - Header: Caraoke logo + Help "?" button (docs/FAQ) + Settings gear (no Shazam)
/// - Master Live Lyrics switch card
/// - Dedicated sections: Live Activities, Dynamic Island, Home Screen Widgets (taps to WidgetSettingsView)
/// - Real-time synced lyric card
/// - Connected music sources (Apple Music / Spotify)
/// - Bottom floating mini-player with artwork, track info, provider badge, and transport controls
struct HomeView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showSpotifySetup = false
    @State private var showWidgetSettings = false
    @State private var showLyricsPage = false
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg(scheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    howToBanner
                    liveActivitiesSection
                    widgetsSection
                    sourcesSection
                    if showsFixes {
                        fixesSection
                    }
                    footnote
                        .padding(.bottom, 80) // Space for floating mini-player
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            // Floating mini-player at bottom
            floatingMiniPlayer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model, presentingPaywall: $showPaywall,
                         spotifyAuth: model.spotifyAuth)
        }
        .sheet(isPresented: $showWidgetSettings) {
            WidgetSettingsView(model: model)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(purchases: purchases, onDismiss: { showPaywall = false })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSpotifySetup) {
            SpotifySetupView(spotifyAuth: model.spotifyAuth, onConnected: {
                model.selectMusicSource(.spotify)
            })
        }
        .fullScreenCover(isPresented: $showLyricsPage) {
            LyricsPageView(model: model)
        }
        // Widgets link here with `caraoke://lyrics`.
        .onOpenURL { url in
            if url.host == "lyrics" || url.path == "/lyrics" {
                // Show what the widget was already displaying instead of an
                // empty page while the pipeline polls the player.
                model.seedFromSharedPayload()
                showLyricsPage = true
            }
        }
    }

    // MARK: - Header (brand mark + Help "?" + gear)

    private var header: some View {
        HStack {
            // Wordmark only — the icon next to it was removed and the type
            // scaled up 25 % (user direction).
            Text("Caraoke")
                .font(.system(size: 35, weight: .bold))
                .tracking(-0.02 * 35)
                .foregroundColor(AppTheme.fg(scheme))
            Spacer()

            // Help & Common Problems "?" button
            Button {
                if let url = URL(string: "https://caraoke.live/docs") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.fg(scheme))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.surface(scheme)))
                    .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))
            }
            .accessibilityLabel("Help and FAQ")

            // Settings gear button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(AppTheme.fg(scheme))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.surface(scheme)))
                    .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var howToBanner: some View {
        Button {
            if let url = URL(string: "https://caraoke.live/docs") { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                Text("How to display lyrics everywhere")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            // Caraoke orange, not the reference app's blue.
            .background(AppTheme.accent(scheme).gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var liveActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Live Lyrics")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(get: { model.isOn }, set: { _ in model.toggle() }))
                    .labelsHidden().tint(AppTheme.ok)
            }
            Text("Show lyrics on the Lock Screen, CarPlay, and Apple Watch.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.muted(scheme))
            if model.liveActivityGateMessage != nil {
                gateBanner
            }
            Button { showLyricsPage = true } label: {
                playerCard
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open lyrics page")
            if let err = model.transportError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.warn)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
    }

    private var widgetsSection: some View {
        Button { showWidgetSettings = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Widget")
                        .font(.system(size: 22, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.muted(scheme))
                }
                Text("Add live lyrics to the Home Screen and CarPlay.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.muted(scheme))
                HomeWidgetPreview(title: model.trackTitle, artist: model.trackArtist,
                                  currentLine: model.currentLine, nextLine: model.nextLine,
                                  previousLine: model.previousLines.last,
                                  artworkData: model.artworkData,
                                  artworkColorHex: model.artworkColorHex,
                                  isSpinning: model.isPlaybackActive)
            }
            .foregroundStyle(AppTheme.fg(scheme))
        }
        .buttonStyle(.plain)
    }

    /// Gate warning box under the switch
    private var gateBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.liveActivityGateMessage ?? "Live Lyrics is turned off.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                Text("Enable Live Lyrics in Settings to stream lyrics to your car screen.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.muted(scheme))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.warn.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.warn.opacity(0.45), lineWidth: 1))
        .padding(.top, 12)
    }

    private var showsFixes: Bool {
        model.liveActivityGateMessage != nil
    }

    // MARK: - Player card

    private var playerCard: some View {
        let isIdle = !model.isOn || (model.trackTitle.isEmpty && model.currentLine.isEmpty)
        return LyricTileView(
            title: isIdle ? (model.isOn ? "Caraoke" : "Live Lyrics Paused") : model.trackTitle,
            artist: isIdle ? (model.isOn ? "Waiting for playback…" : "Switch on to stream to car") : model.trackArtist,
            currentLine: isIdle ? (model.isOn ? "Play a song on Apple Music or Spotify" : "Turn switch on to stream lyrics") : model.currentLine,
            previousLines: isIdle ? [] : model.previousLines,
            nextLine: isIdle ? nil : model.nextLine,
            upcomingLines: isIdle ? [] : model.upcomingLines,
            isPlaying: model.isPlaying,
            progress: isIdle ? 0 : model.progress,
            status: isIdle ? .idle : model.lyricStatus,
            positionMs: isIdle ? 0 : model.positionMs,
            durationMs: isIdle ? nil : model.durationMs,
            surface: .home,
            palette: .activity
        )
        .frame(height: 167)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 12, y: 4)
        .accessibilityLabel("Now playing")
    }

    // MARK: - Floating Mini-Player (competitor ref: small bottom docked bar)

    private var floatingMiniPlayer: some View {
        let hasTrack = !model.trackTitle.isEmpty
        return HStack(spacing: 12) {
            // Tapping the identity opens the full lyrics page.
            Button { showLyricsPage = true } label: {
                HStack(spacing: 12) {
                    // Real cover art of the current song. Rounded SQUARE, not a
                    // circle — user direction, and it matches the rounded-square
                    // mark the large widget already uses.
                    CoverArtworkView(artworkData: model.artworkData,
                                     cornerRadius: 11,
                                     artworkColorHex: model.artworkColorHex)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasTrack ? model.trackTitle : "Caraoke")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Connected app indicator badge
                            if model.spotifyConnected {
                                HStack(spacing: 3) {
                                    Circle().fill(Color(hex: 0x1DB954)).frame(width: 6, height: 6)
                                    Text("Spotify")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: 0x1DB954))
                            } else if model.appleMusicConnected {
                                HStack(spacing: 3) {
                                    Circle().fill(Color(hex: 0xFA233B)).frame(width: 6, height: 6)
                                    Text("Apple Music")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: 0xFA233B))
                            } else {
                                Text(hasTrack ? model.trackArtist : "Not playing")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: 0x8E8E93))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open lyrics page")

            // Transport drives the active source (Apple Music or Spotify).
            HStack(spacing: 16) {
                Button {
                    Task { await model.transport(.previous) }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous song")

                Button {
                    Task { await model.transport(.playPause) }
                } label: {
                    Image(systemName: model.isPlaybackActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.isPlaybackActive ? "Pause" : "Play")

                Button {
                    Task { await model.transport(.next) }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next song")
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0x141416).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    // MARK: - Music Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Music sources")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                Button {
                    model.selectMusicSource(.appleMusic)
                } label: {
                    sourceRow(
                        logo: AnyView(AppleMusicLogo()),
                        title: "Apple Music",
                        subtitle: model.appleMusicConnected ? "Active source" : "Tap to switch",
                        connected: model.appleMusicConnected,
                        showsCheck: model.appleMusicConnected
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(AppTheme.border(scheme))

                if FeatureFlags.spotifyEnabled {
                    Button {
                        if model.spotifyAuth.isConnected {
                            model.selectMusicSource(.spotify)
                        } else {
                            showSpotifySetup = true
                        }
                    } label: {
                        sourceRow(
                            logo: AnyView(SpotifyLogo(size: 34)),
                            title: "Spotify",
                            subtitle: model.spotifyConnected
                                ? "Active source"
                                : (model.spotifyAuth.isConnected ? "Connected (tap to switch)" : "Not connected"),
                            connected: model.spotifyConnected,
                            showsCheck: model.spotifyConnected
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func sourceRow(logo: AnyView, title: String, subtitle: String,
                            connected: Bool, showsCheck: Bool) -> some View {
        HStack(spacing: 12) {
            logo.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.fg(scheme))
                Text(subtitle)
                    .font(.system(size: 13, weight: connected ? .medium : .regular))
                    .foregroundColor(connected ? AppTheme.ok : AppTheme.muted(scheme))
            }
            Spacer()
            if showsCheck && connected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ok)
            } else if !connected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.muted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Needs attention

    @ViewBuilder
    private var fixesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Needs attention")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(AppTheme.fg(scheme).opacity(0.06))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.warn))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Lyrics is off")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text("Lyrics can't reach CarPlay until it's enabled.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                Button("Fix") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.fg(scheme))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }

    private var footnote: some View {
        Text("Use while parked · Designed for passengers")
            .font(.system(size: 11))
            .tracking(0.02 * 11)
            .foregroundColor(AppTheme.muted(scheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

// MARK: - Home widget preview (competitor IMG_5085: lyrics left, record right)

/// Static stand-in for the Home Screen widget, so the Widget section shows what
/// the user gets before they add it.
///
/// Fed the REAL now-playing values — track, artist, lyric window, cover art and
/// the cover's average colour — because build 40's preview hardcoded a blue
/// gradient, a brown disc and a `music.note` glyph, so it never matched the
/// widget it was advertising.
struct HomeWidgetPreview: View {
    let title: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    var previousLine: String?
    var artworkData: Data?
    var artworkColorHex: String?
    /// Spins the record while the active source is playing (app preview only).
    var isSpinning: Bool = false

    @Environment(\.colorScheme) private var scheme

    /// Reads the same shared settings the widget itself uses.
    private var coverStyle: WidgetCoverStyle {
        WidgetCoverStyle(rawValue: SharedWidgetStore.readSettings().coverStyle) ?? .vinyl
    }

    private var theme: WidgetTheme {
        // v1 previews the default theme; the Widget settings screen is where the
        // user picks their own, and the real widget reads it from the payload.
        WidgetTheme(rawValue: SharedWidgetStore.readSettings().theme) ?? .artwork
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(identity)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.mutedTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                // Same 18 pt rows and same weight rule as the real widget.
                VStack(alignment: .leading, spacing: LyricType.lyricRowSpacing) {
                    if let previousLine, !previousLine.isEmpty {
                        Text(previousLine)
                            .font(.system(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                            .foregroundStyle(theme.mutedTextColor.opacity(0.42))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                    }
                    if !currentLyricText.isEmpty {
                        Text(currentLyricText)
                            .font(.system(size: LyricType.lyric, weight: LyricType.lyricWeight))
                            .foregroundStyle(theme.textColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .lineSpacing(LyricType.lyricLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let nextLine, !nextLine.isEmpty {
                        Text(nextLine)
                            .font(.system(size: LyricType.lyric, weight: LyricType.lyricNeighborWeight))
                            .foregroundStyle(theme.mutedTextColor.opacity(0.62))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 6)
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    Image(systemName: isSpinning ? "pause.fill" : "play.fill")
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            cover
        }
        .padding(14)
        .frame(height: 158)
        // The same recipe `WidgetArtworkBackground` paints on the real widget:
        // the song's own average colour when the theme follows the cover.
        // It is a View, not a ShapeStyle, so it goes through the ViewBuilder
        // `background(alignment:content:)` overload and is clipped to the card
        // shape explicitly — `.background(_:in:)` only accepts shape styles.
        .background {
            WidgetArtworkBackground(theme: theme, artworkColorHex: artworkColorHex)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        // Same outline + shadow recipe as the Live Activity card above, so the
        // widget preview reads as the same family of surface.
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 12, y: 4)
    }

    private var currentLyricText: String {
        if !currentLine.isEmpty {
            return currentLine
        }
        if previousLine != nil && isSpinning {
            return "" // outro transition
        }
        if !title.isEmpty {
            return artist.isEmpty ? title : "\(title) — \(artist)"
        }
        return "Play a song to see lyrics"
    }

    private var identity: String {
        artist.isEmpty ? (title.isEmpty ? "Caraoke" : title) : "\(title) — \(artist)"
    }

    @ViewBuilder private var cover: some View {
        if coverStyle == .vinyl {
            VinylRecordView(artworkData: artworkData, diameter: 120, labelDiameter: 84)
                .vinylSpin(isSpinning)
        } else {
            CoverArtworkView(artworkData: artworkData, cornerRadius: 14,
                             artworkColorHex: artworkColorHex)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12)))
        }
    }
}

// MARK: - Source logo (Apple Music)

struct AppleMusicLogo: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFB5C74), Color(hex: 0xFA233B)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
