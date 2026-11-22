import SwiftUI
import ActivityKit
import UIKit
#if canImport(TipKit)
import TipKit
#endif

/// Interactive 3-step visual onboarding with pure SwiftUI surface diagrams.
struct OnboardingView: View {
    let onDismiss: () -> Void

    @State private var step = 0
    @State private var chosenSource: RideModeViewModel.ActiveMusicSource = AppModel.shared.ride.activeSource
    @State private var showSpotifySetup = false
    @Environment(\.colorScheme) private var scheme

    private var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var body: some View {
        ZStack {
            AppTheme.bg(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == step ? AppTheme.accent(scheme) : AppTheme.border(scheme))
                                .frame(width: index == step ? 22 : 8, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: step)
                        }
                    }
                    Spacer()
                    Button("Skip for now") {
                        onDismiss()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppTheme.muted(scheme))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                TabView(selection: $step) {
                    sourcePickerStep.tag(0)
                    surfacesBlueprintStep.tag(1)
                    resyncGestureStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 10) {
                    Button {
                        if step < 2 {
                            withAnimation { step += 1 }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(step < 2 ? "Continue" : primaryFinishTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(AppTheme.accent(scheme))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showSpotifySetup, onDismiss: {
            onDismiss()
        }) {
            SpotifySetupView(spotifyAuth: AppModel.shared.ride.spotifyAuth) {
                AppModel.shared.ride.selectMusicSource(.spotify)
            }
        }
    }

    private var primaryFinishTitle: String {
        if chosenSource == .spotify && !AppModel.shared.ride.spotifyAuth.isConnected {
            return "Connect Spotify & Start"
        }
        return "Start Caraoke"
    }

    private func completeOnboarding() {
        let model = AppModel.shared.ride
        model.selectMusicSource(chosenSource)
        if chosenSource == .spotify && !model.spotifyAuth.isConnected {
            showSpotifySetup = true
            return
        }
        onDismiss()
    }

    // MARK: - Step 1: Pick Your Music App

    private var sourcePickerStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text("Pick Your Music App")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.fg(scheme))
            Text("Caraoke syncs lyrics from whichever player you drive with.")
                .font(.subheadline)
                .foregroundColor(AppTheme.muted(scheme))

            VStack(spacing: 12) {
                sourceOptionCard(
                    source: .appleMusic,
                    title: "Apple Music",
                    subtitle: "Built-in Music app · Instant sync"
                ) { AppleMusicLogo(size: 34) }

                sourceOptionCard(
                    source: .spotify,
                    title: "Spotify",
                    subtitle: AppModel.shared.ride.spotifyAuth.isConnected ? "Connected" : "1-tap sign-in or custom Client ID"
                ) { SpotifyLogo(size: 34) }

                sourceOptionCard(
                    source: .auto,
                    title: "Automatic",
                    subtitle: "Follows whichever player starts first"
                ) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.accent(scheme))
                        .frame(width: 34, height: 34)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func sourceOptionCard<Icon: View>(
        source: RideModeViewModel.ActiveMusicSource,
        title: String,
        subtitle: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let selected = chosenSource == source
        return Button {
            chosenSource = source
        } label: {
            HStack(spacing: 14) {
                icon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(AppTheme.fg(scheme))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selected ? AppTheme.accent(scheme) : AppTheme.border(scheme))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? AppTheme.accent(scheme) : AppTheme.border(scheme), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Lyrics on Every Screen

    private var surfacesBlueprintStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text("Lyrics on Every Screen")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.fg(scheme))
            Text("Switch Live Lyrics on from Home to mirror to Dynamic Island, Lock Screen, and CarPlay Dashboard.")
                .font(.subheadline)
                .foregroundColor(AppTheme.muted(scheme))

            // Vector Blueprint Diagram
            VStack(spacing: 12) {
                // Dynamic Island mockup
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform").foregroundColor(AppTheme.darkAccent)
                        Text("Bright and early").font(.caption.weight(.semibold)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.black))
                    Circle().fill(AppTheme.darkAccent.opacity(0.35)).frame(width: 32, height: 32)
                        .overlay(Image(systemName: "music.note").font(.caption2).foregroundColor(.white))
                }

                // CarPlay Split-Screen mockup
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 68)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "map.fill").foregroundColor(.white.opacity(0.5))
                                Text("Maps").font(.caption2).foregroundColor(.white.opacity(0.5))
                            }
                        )
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black)
                        .frame(height: 68)
                        .overlay(
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bright and early").font(.caption.weight(.bold)).foregroundColor(.white)
                                Text("I'm up with the sun").font(.caption2).foregroundColor(.white.opacity(0.6))
                            }
                            .padding(8)
                            , alignment: .leading
                        )
                }

                // Live Activities readiness badge
                HStack(spacing: 8) {
                    Image(systemName: activitiesEnabled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(activitiesEnabled ? AppTheme.ok : AppTheme.warn)
                    Text(activitiesEnabled ? "Live Activities Ready" : "Live Activities Off — Enable in iOS Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Spacer()
                    if !activitiesEnabled {
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppTheme.accent(scheme))
                    }
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Step 3: Tap Cover to Resync

    private var resyncGestureStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text("Tap Tile to Resync")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.fg(scheme))
            Text("iOS pauses background apps ~30s after locking. Relay keeps your current song moving — if you skip from the steering wheel, tap the widget cover or lyric tile to resync.")
                .font(.subheadline)
                .foregroundColor(AppTheme.muted(scheme))

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    VinylRecordView(diameter: 66, labelDiameter: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap cover or lyric tile")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text("Samples the active player and updates timelines.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x16161A)))

                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black)
                    .padding(7)
                    .background(Circle().fill(AppTheme.darkAccent))
                    .padding(10)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

#if canImport(TipKit)
@available(iOS 17.0, *)
struct StageExpandTip: Tip {
    var title: Text { Text("Full-Screen Stage") }
    var message: Text? { Text("Tap the Stage card anytime to zoom into full-screen lyrics and Bluetooth offset controls.") }
    var image: Image? { Image(systemName: "music.mic") }
}
#endif
