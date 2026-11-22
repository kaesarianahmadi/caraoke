import SwiftUI
import UIKit

/// Home screen: 3-Zone "Night Cockpit" (Live Surface Deck + Lyrics Stage Card + Scrimmed Docked Console).
struct HomeView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var showSettings = false
    @State private var showSurfaceStudio = false
    @State private var showPaywall = false
    @State private var showSpotifySetup = false
    @State private var showHelp = false
    @State private var showLyricsPage = false
    @State private var selectedSurface: ExternalSurfaceTab = .island
    @StateObject private var purchases = PurchaseManager()
    @Namespace private var stageZoom

    @AppStorage(AppearanceSettings.boldTextKey) private var boldText = true
    @AppStorage(AppearanceSettings.homeLayoutKey) private var layoutRaw = HomeLayoutMode.stageFocus.rawValue
    @AppStorage(AppearanceSettings.backdropStyleKey) private var backdropRaw = LyricsBackdropStyle.ambientCover.rawValue
    @AppStorage(AppearanceSettings.showTranslationsKey) private var showTranslations = true
    @AppStorage("widget.theme") private var widgetThemeRaw = WidgetTheme.artwork.rawValue
    @AppStorage("widget.coverStyle") private var widgetCoverRaw = WidgetCoverStyle.vinyl.rawValue

    @Environment(\.colorScheme) private var scheme
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layoutMode: HomeLayoutMode { HomeLayoutMode(rawValue: layoutRaw) ?? .stageFocus }
    private var backdropStyle: LyricsBackdropStyle { LyricsBackdropStyle(rawValue: backdropRaw) ?? .ambientCover }
    private var useBoldLyrics: Bool { boldText || legibilityWeight == .bold }
    private var widgetTheme: WidgetTheme { WidgetTheme(rawValue: widgetThemeRaw) ?? .artwork }
    private var widgetCoverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: widgetCoverRaw) ?? .vinyl }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg(scheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerBar
                    alertBanner
                    liveSurfaceDeck
                    lyricsStageCard
                    if layoutMode == .surfaceStudio {
                        studioWidgetCard
                    }
                    Text("Use while parked · Designed for passengers")
                        .font(.caption2)
                        .foregroundColor(AppTheme.subtle(scheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) {
                dockedConsole
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.bg(scheme).opacity(0), AppTheme.bg(scheme).opacity(0.94), AppTheme.bg(scheme)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(model: model, presentingPaywall: $showPaywall, spotifyAuth: model.spotifyAuth)
        }
        .navigationDestination(isPresented: $showSurfaceStudio) {
            WidgetSettingsView()
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
                .navigationTransition(.zoom(sourceID: "stageCard", in: stageZoom))
        }
        .onOpenURL { url in
            if url.host == "lyrics" || url.path == "/lyrics" {
                model.seedFromSharedPayload()
                showLyricsPage = true
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            CaraokeLogo(size: 28)
            Text("Caraoke")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.fg(scheme))
                .lineLimit(1)

            if model.isOn {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.hasActiveActivity ? AppTheme.ok : AppTheme.accent(scheme))
                        .frame(width: 6, height: 6)
                    Text(model.hasActiveActivity ? "LIVE" : "ARMED")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(model.hasActiveActivity ? AppTheme.ok : AppTheme.accent(scheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppTheme.surfaceElevated(scheme)))
            }

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                        .frame(width: CockpitMetrics.hitTarget, height: CockpitMetrics.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Help and setup")

                Divider()
                    .frame(height: 18)
                    .overlay(AppTheme.border(scheme))

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.fg(scheme))
                        .frame(width: CockpitMetrics.hitTarget, height: CockpitMetrics.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Settings")
            }
            .background(Capsule().fill(AppTheme.surface(scheme)))
            .overlay(Capsule().stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }

    // MARK: - Truthful Permission & Beta Gate Banner

    @ViewBuilder
    private var alertBanner: some View {
        if model.appleMusicAuthDenied && model.activeSource != .spotify {
            gateBanner(
                icon: "exclamationmark.triangle.fill",
                tint: AppTheme.warn,
                title: "Media & Apple Music permission denied",
                cta: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } else if model.spotifyNeedsAllowlist && model.activeSource != .appleMusic {
            gateBanner(
                icon: "key.fill",
                tint: AppTheme.warn,
                title: "Spotify shared beta limit (403) — add your free Client ID",
                cta: "Setup"
            ) {
                showSpotifySetup = true
            }
        } else if let issue = model.liveActivityGateMessage {
            gateBanner(
                icon: "lock.slash.fill",
                tint: AppTheme.err,
                title: "\(issue) — enable Live Activities in iOS Settings",
                cta: "Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func gateBanner(icon: String, tint: Color, title: String, cta: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.fg(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button(cta, action: action)
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(tint))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Zone 1: Live Surface Deck

    private var liveSurfaceDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Live Lyrics")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(AppTheme.fg(scheme))

                Spacer(minLength: 8)

                Button { showSurfaceStudio = true } label: {
                    HStack(spacing: 3) {
                        Text("Tune")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.muted(scheme))
                    .frame(minHeight: 32)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(AppTheme.surface(scheme)))
                    .overlay(Capsule().stroke(AppTheme.border(scheme), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(intent: SetRideModeIntent(enabled: !model.isOn)) {
                    ZStack(alignment: model.isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(model.isOn ? AppTheme.accent(scheme) : AppTheme.muted(scheme).opacity(0.3))
                        Circle()
                            .fill(.white)
                            .frame(width: 26, height: 26)
                            .padding(2)
                            .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
                    }
                    .frame(width: 50, height: 30)
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: model.isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Live Lyrics")
                .accessibilityValue(model.isOn ? "On" : "Off")
            }

            if layoutMode != .minimalCockpit {
                VStack(spacing: 12) {
                    // Surface family pills
                    HStack(spacing: 4) {
                        ForEach(ExternalSurfaceTab.allCases) { tab in
                            Button {
                                selectedSurface = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: selectedSurface == tab ? .bold : .medium))
                                    .foregroundColor(selectedSurface == tab ? AppTheme.fg(scheme) : AppTheme.muted(scheme))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(selectedSurface == tab ? AppTheme.surfaceElevated(scheme) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(AppTheme.bg(scheme).opacity(0.6)))

                    surfacePreviewStage
                        .frame(maxWidth: .infinity)

                    // Truthful readiness footer
                    HStack(spacing: 8) {
                        Circle()
                            .fill(deckStatusColor)
                            .frame(width: 7, height: 7)
                        Text(deckStatusText)
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppTheme.muted(scheme))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button {
                            Task { await model.resyncNow() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Resync")
                                Image(systemName: "arrow.clockwise")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.accent(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(CockpitMetrics.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous)
                        .fill(AppTheme.surface(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous)
                        .stroke(AppTheme.border(scheme), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var surfacePreviewStage: some View {
        let previewLine = model.currentLine.isEmpty ? "Play music to see live lyrics" : model.currentLine
        switch selectedSurface {
        case .island:
            // True-scale thin Dynamic Island pill + detached artwork bubble (~36pt)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.accent(scheme))
                    Text(previewLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Color.black))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))

                CoverArtworkView(
                    artworkData: model.artworkData,
                    cornerRadius: 18,
                    showsVinylFallback: false,
                    artworkColorHex: model.artworkColorHex
                )
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: CockpitMetrics.innerRadius, style: .continuous)
                    .fill(AppTheme.surfaceElevated(scheme))
            )

        case .carPlay:
            HStack(spacing: 10) {
                CoverArtworkView(
                    artworkData: model.artworkData,
                    cornerRadius: 8,
                    artworkColorHex: model.artworkColorHex
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(previewLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(model.nextLine ?? "CarPlay Dashboard · Auto-sync")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "car.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.accent(scheme))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: CockpitMetrics.innerRadius, style: .continuous)
                    .fill(Color.black)
            )

        case .lock:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(AppTheme.accent(scheme)).frame(width: 6, height: 6)
                    Text(model.trackTitle.isEmpty ? "Lock Screen Banner" : model.trackTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(AppTheme.accent(scheme))
                }
                Text(previewLine)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let next = model.nextLine, !next.isEmpty {
                    Text(next)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: CockpitMetrics.innerRadius, style: .continuous)
                    .fill(CoverArtworkView.controlledStageWash(model.artworkColorHex, enabled: true)
                          ?? LinearGradient(colors: [Color(hex: 0x1A1A1E), Color.black], startPoint: .top, endPoint: .bottom))
            )

        case .widget:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(previewLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(widgetTheme.textColor)
                        .lineLimit(2)
                    Text(model.nextLine ?? "Home Screen Widget")
                        .font(.system(size: 11))
                        .foregroundColor(widgetTheme.mutedTextColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if widgetCoverStyle == .vinyl {
                    VinylRecordView(artworkData: model.artworkData, diameter: 48, labelDiameter: 30)
                        .vinylSpin(model.isPlaybackActive)
                } else {
                    CoverArtworkView(artworkData: model.artworkData, cornerRadius: 8, artworkColorHex: model.artworkColorHex)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: CockpitMetrics.innerRadius, style: .continuous)
                    .fill(widgetTheme.backgroundColor)
            )
        }
    }

    private var deckStatusColor: Color {
        if !model.isOn { return AppTheme.subtle(scheme) }
        if model.hasActiveActivity { return AppTheme.ok }
        return AppTheme.accent(scheme)
    }

    private var deckStatusText: String {
        if !model.isOn { return "Off — switch on for Lock Screen & CarPlay" }
        if model.hasActiveActivity { return "Live on Lock Screen, Island & CarPlay" }
        return "Armed — play a song to start sync"
    }

    // MARK: - Zone 2: Lyrics Stage Card (Zero Duplicate Title/Artist)

    private var lyricsStageCard: some View {
        Button {
            showLyricsPage = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous)
                    .fill(Color(hex: 0x09090B))
                if let wash = CoverArtworkView.controlledStageWash(model.artworkColorHex, enabled: backdropStyle == .ambientCover) {
                    RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous)
                        .fill(wash)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("STAGE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }

                    Spacer(minLength: 4)

                    if model.trackTitle.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Waiting for music")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("Play Apple Music or Spotify to light up the stage.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.52))
                        }
                    } else if model.lyricStatus == .noLyrics {
                        Text("No synced lyrics for this track")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                    } else if model.currentLine.isEmpty && model.upcomingLines.isEmpty {
                        Text(model.lyricStatus == .loading ? "Finding synced lyrics…" : "Instrumental…")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if let prev = model.previousLines.last, !prev.isEmpty {
                                Text(prev)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.42))
                                    .lineLimit(1)
                            }

                            HStack(alignment: .top, spacing: 10) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(AppTheme.darkAccent)
                                    .frame(width: 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.currentLine.isEmpty ? "•••" : model.currentLine)
                                        .font(.system(size: 22, weight: useBoldLyrics ? .bold : .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(3)
                                    if showTranslations, let tr = model.currentTranslation, !tr.isEmpty {
                                        Text(tr)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white.opacity(0.68))
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)

                            if let next = model.nextLine, !next.isEmpty {
                                Text(next)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(2)
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }
                .padding(16)
            }
            .frame(minHeight: 228)
            .clipShape(RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .matchedTransitionSource(id: "stageCard", in: stageZoom)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full lyrics stage")
    }

    // MARK: - Surface Studio Extra Card (Optional Layout Mode)

    private var studioWidgetCard: some View {
        Button { showSurfaceStudio = true } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WIDGET STUDIO")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(AppTheme.accent(scheme))
                    Text("\(widgetTheme.displayName) · \(widgetCoverStyle.displayName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text("Tap to customize swatches & cover")
                        .font(.caption)
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                VinylRecordView(artworkData: model.artworkData, diameter: 54, labelDiameter: 34)
                    .vinylSpin(model.isPlaybackActive)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: CockpitMetrics.cardRadius, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Zone 3: Scrimmed Docked Console (Preserves Real Artist Name)

    private var dockedConsole: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CoverArtworkView(
                    artworkData: model.artworkData,
                    cornerRadius: CockpitMetrics.innerRadius,
                    artworkColorHex: model.artworkColorHex
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: CockpitMetrics.innerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CockpitMetrics.innerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.trackTitle.isEmpty ? "Not Playing" : model.trackTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                        .lineLimit(1)
                    Text(model.trackArtist.isEmpty ? sourceLabel : model.trackArtist)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.muted(scheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 2) {
                    Button { Task { await model.transport(.previous) } } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.fg(scheme))
                            .frame(width: 34, height: 44)
                    }
                    Button { Task { await model.transport(.playPause) } } label: {
                        Image(systemName: model.isPlaybackActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppTheme.fg(scheme))
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel(model.isPlaybackActive ? "Pause" : "Play")
                    Button { Task { await model.transport(.next) } } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.fg(scheme))
                            .frame(width: 34, height: 44)
                    }
                }
                .buttonStyle(.plain)

                // Source selector badge
                Menu {
                    Button { model.selectMusicSource(.auto) } label: {
                        Label("Automatic", systemImage: model.activeSource == .auto ? "checkmark" : "sparkles")
                    }
                    Button { model.selectMusicSource(.appleMusic) } label: {
                        Label("Apple Music", systemImage: model.activeSource == .appleMusic ? "checkmark" : "music.note")
                    }
                    Button {
                        if model.spotifyAuth.isConnected {
                            model.selectMusicSource(.spotify)
                        } else {
                            showSpotifySetup = true
                        }
                    } label: {
                        Label(model.spotifyAuth.isConnected ? "Spotify" : "Connect Spotify…",
                              systemImage: model.activeSource == .spotify ? "checkmark" : "dot.radiowaves.left.and.right")
                    }
                } label: {
                    Group {
                        if model.activeSource == .spotify || (model.activeSource == .auto && model.spotifyConnected) {
                            SpotifyLogo(size: 26)
                        } else {
                            AppleMusicLogo(size: 26)
                        }
                    }
                    .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Music source: \(sourceLabel)")
            }
            .padding(.horizontal, CockpitMetrics.consolePadding)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Integrated 2pt progress hairline
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.border(scheme))
                    Capsule()
                        .fill(AppTheme.accent(scheme))
                        .frame(width: geo.size.width * max(0, min(1, model.progress)))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, CockpitMetrics.consolePadding)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: CockpitMetrics.consoleRadius, style: .continuous)
                .fill(AppTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CockpitMetrics.consoleRadius, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.12), radius: 14, y: 6)
    }

    private var sourceLabel: String {
        switch model.activeSource {
        case .auto: return model.spotifyConnected ? "Spotify · Auto" : "Apple Music · Auto"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}
