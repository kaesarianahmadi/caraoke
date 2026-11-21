import SwiftUI
import UIKit

/// Home screen with live lyrics, full lyric access, music sources and playback controls.
struct HomeView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showSpotifySetup = false
    @State private var showHelp = false
    @State private var showLyricsPage = false
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var compactPreviewMinHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg(scheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    liveLyricsSection
                    setupHelpLink
                    fullLyricsPreview
                    musicSourceSection
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            // Floating mini-player at bottom. Hosted in the scroll view's
            // bottom safe-area inset so the content inset IS the miniplayer's
            // measured height — no guessed height constants.
            .safeAreaInset(edge: .bottom) {
                floatingMiniPlayer
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(model: model, presentingPaywall: $showPaywall,
                         spotifyAuth: model.spotifyAuth)
        }
        .sheet(isPresented: $showHelp) {
            NavigationStack {
                HelpView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showHelp = false }
                        }
                    }
            }
            .tint(AppTheme.accent(scheme))
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
        HStack(spacing: 12) {
            Text("Caraoke")
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(AppTheme.fg(scheme))
            Spacer(minLength: 8)

            Button { showHelp = true } label: {
                Image(systemName: "questionmark")
                    .font(.body.weight(.bold))
                    .foregroundColor(AppTheme.fg(scheme))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.surface(scheme)))
                    .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Help and setup")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundColor(AppTheme.fg(scheme))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.surface(scheme)))
                    .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Live Lyrics

    private var liveLyricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Live Lyrics")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppTheme.fg(scheme))
                Spacer(minLength: 8)

                Button(intent: SetRideModeIntent(enabled: !model.isOn)) {
                    ZStack(alignment: model.isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(model.isOn ? AppTheme.accent(scheme)
                                  : AppTheme.muted(scheme).opacity(0.3))
                        Circle()
                            .fill(.white)
                            .frame(width: 27, height: 27)
                            .padding(2)
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    }
                    .frame(width: 51, height: 31)
                    .frame(minHeight: 44)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                               value: model.isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Live Lyrics")
                .accessibilityValue(!model.isOn ? "Off" : model.hasActiveActivity ? "On, Live Activity active" : "On, no active Live Activity")
                .accessibilityHint(model.isOn ? "Turn off live lyrics" : "Start live lyrics")
            }

            compactLivePreview

            if let gate = model.liveActivityGateMessage {
                gateNotice(gate)
            } else if model.isOn, !model.hasActiveActivity {
                Label(model.liveActivityIssue ?? "Live Activity isn’t active yet.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundColor(AppTheme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.transportError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(AppTheme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compactLivePreview: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverArtworkView(artworkData: model.artworkData,
                             cornerRadius: 10,
                             artworkColorHex: model.artworkColorHex)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.border(scheme), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(compactIdentity)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.isOn ? AppTheme.accent(scheme)
                                  : AppTheme.muted(scheme).opacity(0.5))
                            .frame(width: 5, height: 5)
                        Text(compactStatus)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppTheme.muted(scheme))
                            .lineLimit(1)
                    }
                }

                Text(compactCurrentLine)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.fg(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let next = compactNextLine {
                    Text(next)
                        .font(.caption)
                        .foregroundColor(AppTheme.muted(scheme))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: compactPreviewMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(AppTheme.border(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live lyrics preview: \(compactStatus). \(compactCurrentLine)")
    }

    private var compactIdentity: String {
        if !model.trackTitle.isEmpty { return model.trackTitle }
        if !model.trackArtist.isEmpty { return model.trackArtist }
        return "Caraoke"
    }

    private var compactStatus: String {
        model.isOn ? model.lyricStatus.homeBadge : "Off"
    }

    private var compactCurrentLine: String {
        guard model.isOn else { return "Turn on Live Lyrics to stream lyrics." }
        switch model.lyricStatus {
        case .loading:
            return "Finding lyrics…"
        case .noLyrics:
            return "No lyrics found for this song."
        case .stale:
            return "Ride ended."
        case .expired:
            return "Lyrics are out of date."
        case .paused:
            return model.currentLine.isEmpty ? "Paused." : model.currentLine
        case .idle:
            return "Waiting for playback…"
        case .playing:
            return model.currentLine.isEmpty ? "Lyrics will appear when the song starts." : model.currentLine
        }
    }

    private var compactNextLine: String? {
        guard model.isOn else { return nil }
        switch model.lyricStatus {
        case .playing, .paused:
            return model.nextLine
        default:
            return nil
        }
    }

    private func gateNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundColor(AppTheme.warn)
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                Text("Live Activities are disabled in iOS Settings. Enable them to show lyrics on the Lock Screen and CarPlay.")
                    .font(.caption)
                    .foregroundColor(AppTheme.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(AppTheme.accent(scheme))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.warn.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.warn.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Setup help

    private var setupHelpLink: some View {
        Button { showHelp = true } label: {
            HStack(spacing: 8) {
                Text("Lock Screen & CarPlay")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.muted(scheme))
                Spacer(minLength: 8)
                Text("Setup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.accent(scheme))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.accent(scheme))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lock Screen and CarPlay setup")
        .accessibilityHint("Opens setup help")
    }

    // MARK: - Full lyrics preview

    private var fullLyricsPreview: some View {
        Button { showLyricsPage = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full lyrics")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AppTheme.muted(scheme))
                        if !model.trackTitle.isEmpty {
                            Text(fullIdentity)
                                .font(.caption)
                                .foregroundColor(AppTheme.muted(scheme).opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 12) {
                    if let previous = fullPreviousLine {
                        Text(previous)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.muted(scheme))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(fullCurrentLine)
                        .font(.title2.weight(.bold))
                        .foregroundColor(AppTheme.fg(scheme))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 16)
                        .overlay(alignment: .leading) {
                            if showsFullLyricMarker {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(AppTheme.accent(scheme))
                                    .frame(width: 3)
                                    .padding(.vertical, 4)
                            }
                        }

                    if let next = fullNextLine {
                        Text(next)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.muted(scheme))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 20)

                HStack(spacing: 6) {
                    Text("Open full lyrics")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AppTheme.accent(scheme))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppTheme.accent(scheme))
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full lyrics")
        .accessibilityHint("Shows the full lyric sheet and playback controls")
    }

    private var fullIdentity: String {
        if model.trackArtist.isEmpty { return model.trackTitle }
        return "\(model.trackTitle) — \(model.trackArtist)"
    }

    private var fullCurrentLine: String {
        guard model.isOn else { return "Live Lyrics is off" }
        switch model.lyricStatus {
        case .loading:
            return "Finding lyrics…"
        case .noLyrics:
            return "No lyrics found for this song"
        case .stale:
            return "Ride ended"
        case .expired:
            return "Lyrics are out of date"
        case .paused:
            return model.currentLine.isEmpty ? "Paused" : model.currentLine
        case .idle:
            return "Waiting for playback…"
        case .playing:
            if !model.currentLine.isEmpty { return model.currentLine }
            return model.trackTitle.isEmpty ? "Waiting for playback…" : "Waiting for the first line…"
        }
    }

    private var fullPreviousLine: String? {
        guard isShowingLyricWindow else { return nil }
        return model.previousLines.last
    }

    private var fullNextLine: String? {
        guard isShowingLyricWindow else { return nil }
        return model.nextLine
    }

    private var isShowingLyricWindow: Bool {
        guard model.isOn, !model.currentLine.isEmpty else { return false }
        return model.lyricStatus == .playing || model.lyricStatus == .paused
    }

    private var showsFullLyricMarker: Bool {
        isShowingLyricWindow
    }

    // MARK: - Floating Mini-Player

    private var floatingMiniPlayer: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    floatingIdentity
                    floatingTransport
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                HStack(spacing: 12) {
                    floatingIdentity
                    floatingTransport
                }
            }
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

    private var floatingIdentity: some View {
        let hasTrack = !model.trackTitle.isEmpty
        return Button { showLyricsPage = true } label: {
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Connected app indicator badge
                        if model.spotifyConnected {
                            HStack(spacing: 3) {
                                Circle().fill(Color(hex: 0x1DB954)).frame(width: 6, height: 6)
                                Text("Spotify")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundColor(Color(hex: 0x1DB954))
                        } else if model.appleMusicConnected {
                            HStack(spacing: 3) {
                                Circle().fill(Color(hex: 0xFA233B)).frame(width: 6, height: 6)
                                Text("Apple Music")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundColor(Color(hex: 0xFA233B))
                        } else {
                            Text(hasTrack ? model.trackArtist : "Not playing")
                                .font(.caption)
                                .foregroundColor(Color(hex: 0x8E8E93))
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open lyrics page")
    }

    private var floatingTransport: some View {
        // Transport drives the active source (Apple Music or Spotify).
        HStack(spacing: 0) {
            Button {
                Task { await model.transport(.previous) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous song")

            Button {
                Task { await model.transport(.playPause) }
            } label: {
                Image(systemName: model.isPlaybackActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(model.isPlaybackActive ? "Pause" : "Play")

            Button {
                Task { await model.transport(.next) }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next song")
        }
    }

    // MARK: - Music Sources

    private var musicSourceSection: some View {
        Menu {
            Button("Apple Music") {
                model.selectMusicSource(.appleMusic)
            }
            if FeatureFlags.spotifyEnabled {
                Button("Spotify") {
                    if model.spotifyAuth.isConnected {
                        model.selectMusicSource(.spotify)
                    } else {
                        showSpotifySetup = true
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Music source")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.muted(scheme))
                Spacer(minLength: 8)
                Text(activeSourceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.muted(scheme))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Music source")
        .accessibilityValue(activeSourceName)
        .accessibilityHint("Choose Apple Music or Spotify")
    }

    private var activeSourceName: String {
        model.spotifyConnected ? "Spotify" : "Apple Music"
    }

    private var footnote: some View {
        Text("Use while parked · Designed for passengers")
            .font(.caption)
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
