import SwiftUI

/// Segmented visual setup & troubleshooting guide replacing the old prose wall.
struct HelpView: View {
    enum Topic: String, CaseIterable, Identifiable {
        case quickStart = "Quick Start"
        case carPlay = "CarPlay"
        case lockedPhone = "Locked Phone"
        case spotify = "Spotify"
        case widgets = "Widgets"
        var id: String { rawValue }
    }

    @State private var topic: Topic = .quickStart
    @State private var copiedURI = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppTheme.bg(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Topic.allCases) { item in
                            Button {
                                topic = item
                            } label: {
                                Text(item.rawValue)
                                    .font(.caption.weight(topic == item ? .bold : .medium))
                                    .foregroundColor(topic == item ? .black : AppTheme.fg(scheme))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(topic == item ? AppTheme.accent(scheme) : AppTheme.surface(scheme))
                                    )
                                    .overlay(
                                        Capsule().stroke(topic == item ? Color.clear : AppTheme.border(scheme), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        topicDiagram
                        topicSteps
                        docsLink
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Setup & Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var topicDiagram: some View {
        switch topic {
        case .quickStart:
            diagramCard(title: "3-Zone Cockpit") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Live Lyrics")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                        Spacer()
                        Capsule().fill(AppTheme.darkAccent).frame(width: 34, height: 18)
                    }
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 44)
                        .overlay(Text("Stage Card — Tap to expand").font(.caption).foregroundColor(.white.opacity(0.75)))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 32)
                        .overlay(Text("Docked Console · ⏮ ⏯ ⏭ · Source").font(.caption2).foregroundColor(.white.opacity(0.85)))
                }
            }

        case .carPlay:
            diagramCard(title: "CarPlay Dashboard Split-Screen") {
                HStack(spacing: 10) {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.14)).frame(width: 46, height: 46)
                        Text("Player Tile").font(.caption2).foregroundColor(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current lyric").font(.caption.weight(.bold)).foregroundColor(.white)
                            Text("Next line").font(.caption2).foregroundColor(.white.opacity(0.6))
                            Spacer(minLength: 4)
                            Text("Tap tile to resync").font(.system(size: 10)).foregroundColor(AppTheme.darkAccent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black))

                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.darkAccent)
                            .padding(6)
                    }
                }
            }

        case .lockedPhone:
            diagramCard(title: "Relay + Resync") {
                HStack(spacing: 12) {
                    Image(systemName: "lock.iphone")
                        .font(.title2)
                        .foregroundColor(AppTheme.darkAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Relay advances current track while locked")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                        Text("Switched songs from the car? Tap any tile or open Caraoke to re-anchor.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

        case .spotify:
            diagramCard(title: "Canonical Redirect URI") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(SpotifyAuth.redirectURI)
                        .font(.subheadline.weight(.bold).monospaced())
                        .foregroundColor(Color(hex: 0x1DB954))
                    Button {
                        UIPasteboard.general.string = SpotifyAuth.redirectURI
                        copiedURI = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedURI = false }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copiedURI ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(copiedURI ? "Copied!" : "Copy Redirect URI")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: 0x1DB954)))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .widgets:
            diagramCard(title: "Small, Medium & Large Widgets") {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)).frame(width: 48, height: 48)
                        .overlay(Text("S").font(.caption.weight(.bold)).foregroundColor(.white))
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)).frame(width: 96, height: 48)
                        .overlay(Text("M · Vinyl").font(.caption.weight(.bold)).foregroundColor(.white))
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)).frame(width: 64, height: 64)
                        .overlay(Text("L").font(.caption.weight(.bold)).foregroundColor(.white))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var topicSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch topic {
            case .quickStart:
                step("1", "Pick Apple Music or Spotify from the bottom console badge or Settings → Music Sources.")
                step("2", "Turn Live Lyrics ON at the top of Home.")
                step("3", "Allow Live Activities in iOS Settings → Caraoke → Live Activities.")
            case .carPlay:
                step("1", "Connect iPhone via wired or wireless CarPlay and open the CarPlay Dashboard.")
                step("2", "Add Caraoke widgets in iOS Settings → General → CarPlay → Your Car → Widgets.")
                step("3", "On touchscreen CarPlay, tap the entire lyric/hybrid tile or the player cover to resync. An expired badge appears at the top-trailing corner.")
                step("4", "If wireless CarPlay audio lags behind lyrics, adjust Bluetooth Sync Offset (±0.25s) on the full lyrics page or Surface Studio.")
            case .lockedPhone:
                step("1", "iOS suspends background apps ~30s after locking; Caraoke's relay keeps the current song's Lock Screen & Dynamic Island moving.")
                step("2", "If you skip or pause from the steering wheel while locked, tap a widget tile to trigger resync or reopen Caraoke.")
                step("3", "For Apple Music, widget self-repair requires opening Caraoke; Spotify widgets can self-repair directly.")
            case .spotify:
                step("1", "Open Settings → Music Sources → Spotify (or tap the bottom console source badge) and tap Connect with Spotify.")
                step("2", "If you hit the 5-user beta limit (HTTP 403), expand 'Use your own free Client ID' inside Spotify Setup.")
                step("3", "In developer.spotify.com/dashboard, add Redirect URI: \(SpotifyAuth.redirectURI)")
                step("4", "Paste your Client ID and tap Save Custom ID & Connect.")
            case .widgets:
                step("1", "Long-press Home Screen → Edit → Add Widget → search Caraoke (Small, Medium, or Large).")
                step("2", "Customize Cover vs OLED/Slate/Ivory swatches and Vinyl vs Square art in Surface Studio (Home → Tune ›).")
                step("3", "You can also add the Caraoke Live Lyrics toggle directly to Control Center.")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
    }

    private var docsLink: some View {
        Link(destination: URL(string: "https://caraokeapp.com/docs")!) {
            HStack {
                Text("Open full web guide (caraokeapp.com/docs)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right.square")
            }
            .foregroundColor(AppTheme.accent(scheme))
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }

    private func diagramCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundColor(AppTheme.darkAccent)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x121214)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func step(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(AppTheme.accent(scheme)))
            Text(text)
                .font(.subheadline)
                .foregroundColor(AppTheme.fg(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
