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
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg(scheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switchCard
                    featureCardsSection
                    playerCard
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
            WidgetSettingsView()
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
    }

    // MARK: - Header (brand mark + Help "?" + gear)

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                CaraokeLogo(size: 27)
                Text("Caraoke")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.02 * 28)
                    .foregroundColor(AppTheme.fg(scheme))
            }
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

    // MARK: - Live Lyrics switch card

    private var switchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Live Lyrics")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text("Streams synchronized lyrics to CarPlay, Lock Screen, and Home Screen widgets.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.muted(scheme))
                        .lineSpacing(1.4 * 13 - 13)
                        .padding(.top, 5)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { model.isOn },
                    set: { _ in model.toggle() }
                ))
                .labelsHidden()
                .tint(AppTheme.ok)
                .fixedSize()
            }

            if model.liveActivityGateMessage != nil {
                gateBanner
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
    }

    // MARK: - Dedicated Feature Cards (Live Activities, Dynamic Island, Widgets)

    private var featureCardsSection: some View {
        VStack(spacing: 10) {
            // Live Activities card
            HStack(spacing: 12) {
                Circle()
                    .fill(model.liveActivityGateMessage == nil ? AppTheme.ok : AppTheme.warn)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activities")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text(model.liveActivityGateMessage == nil ? "Ready on Lock Screen & CarPlay" : "Permission required")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.ok)
                    .font(.system(size: 16))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))

            // Dynamic Island card
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.ok)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dynamic Island")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text("Compact lyric pills on supported devices")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                Image(systemName: "platter.2.filled.iphone")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.muted(scheme))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))

            // Widgets card (taps to WidgetSettingsView)
            Button {
                showWidgetSettings = true
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: 0xFF9845))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Home Screen & StandBy Widgets")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.fg(scheme))
                        Text("Themes, vinyl style, and live preview")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    /// Gate warning box under the switch
    private var gateBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.liveActivityGateMessage ?? "Live Activities is turned off.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                Text("Enable Live Activities in Settings to stream lyrics to your car screen.")
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
            nextLine: isIdle ? nil : model.nextLine,
            upcomingLines: isIdle ? [] : model.upcomingLines,
            isPlaying: model.isPlaying,
            progress: isIdle ? 0 : model.progress,
            status: isIdle ? .idle : model.lyricStatus,
            positionMs: isIdle ? 0 : model.positionMs,
            durationMs: isIdle ? nil : model.durationMs,
            surface: .home,
            palette: .home(scheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 12, y: 4)
        .accessibilityLabel("Now playing")
    }

    // MARK: - Floating Mini-Player (Competitor Ref: small bottom docked bar)

    private var floatingMiniPlayer: some View {
        let hasTrack = !model.trackTitle.isEmpty
        return HStack(spacing: 12) {
            // Artwork / Vinyl Icon
            ZStack {
                Circle()
                    .fill(Color(hex: 0x18181B))
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(Color(hex: 0xFF9845))
                    .frame(width: 12, height: 12)
            }

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

            Spacer()

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    // Previous song
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }

                Button {
                    model.toggle()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                Button {
                    // Next song
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
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
                    Text("Live Activities is off")
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
