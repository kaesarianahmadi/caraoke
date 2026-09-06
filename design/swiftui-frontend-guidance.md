# SwiftUI Frontend Implementation Guide — Caraoke

Target references:
- `design/screens/home.html`
- `design/screens/live-activity.html`
- `design/screens/settings.html`

---

## 1. Core Architecture Rules

1. **Zero Transport Controls**:
   - Live Activity Lock Screen card has NO rewind, play/pause, or fast-forward buttons.
   - In-app player block has NO rewind, play/pause, or fast-forward buttons.
   - Delete `transport` subview logic from `LyricTileView.swift`.
2. **Lock Screen Live Activity Header**:
   - Delete "Caraoke" logo mark and "Caraoke" text.
   - Top-left: Track title (`13pt`, semibold, `.white`) stacked over Artist (`11.5pt`, regular, `#EBEBF5` 55% opacity).
   - Top-right: Status indicator (`Playing` with 7pt amber dot `#FF9845`, or `Paused` with 9pt pause glyph).
3. **In-App Home Hierarchy (`HomeView.swift`)**:
   - Vertical order inside root `ScrollView`:
     1. App Header: "Caraoke" title (`28pt`, bold) + Settings gear button (44×44 circle).
     2. **Live Lyrics Switch Card**: Master toggle switch on right, title + subtitle on left. Optional warning callout directly beneath if permissions missing.
     3. **Music Player Block**: Placed directly underneath the Live Lyrics card. Identical layout to Live Activity (title/artist top-left, status top-right, current + next lyric, 3px progress bar + elapsed/remaining timestamps). Uses app theme background `#131921` and border `#292E36`.
     4. **Music Sources Card**: Apple Music row + Spotify row.
     5. **Needs Attention Card**: Only rendered when setup steps remain.
   - **No Standalone Lyrics View**: Remove navigation links or modal sheets pointing to a standalone lyrics view.
4. **Spotify Brand Mark**:
   - Do NOT use SF Symbol `waveform`.
   - Use custom SwiftUI vector rendering 3 horizontal curved black stripes inside a `#1DB954` green circle.
5. **Settings Appearance Selector (`SettingsView.swift`)**:
   - Single list row:
     - Left: Icon (`circle.lefthalf.filled`), label "Appearance".
     - Right: Current mode label ("Auto", "Light", "Dark") + chevron icon.
   - Tap presents a half-sheet (`.presentationDetents([.medium])`) with selectable rows and checkmark on active choice.

---

## 2. Design Tokens

### Colors

```swift
extension Color {
    static let appBackground = Color(hex: 0x0A0E15)
    static let appSurface = Color(hex: 0x131921)
    static let appBorder = Color(hex: 0x292E36)
    static let textPrimary = Color(hex: 0xECEFF2)
    static let textMuted = Color(hex: 0x82868E)
    static let accentAmber = Color(hex: 0xFF9845)
    static let spotifyGreen = Color(hex: 0x1DB954)
}

// Live Activity Glass Tokens (Always Dark)
struct LiveActivityTokens {
    static let background = Color(red: 14/255, green: 14/255, blue: 16/255).opacity(0.68)
    static let border = Color.white.opacity(0.07)
    static let title = Color.white
    static let artist = Color(hex: 0xEBEBF5).opacity(0.55)
    static let heroLyric = Color.white
    static let nextLyric = Color(hex: 0xEBEBF5).opacity(0.55)
    static let trackBg = Color.white.opacity(0.18)
    static let trackFill = Color.white.opacity(0.75)
    static let timeText = Color(hex: 0xEBEBF5).opacity(0.40)
}
```

### Dimensions & Radii
- Screen horizontal margin: `20pt`
- Card corner radius: `18pt` continuous (`20pt` for player card, `28pt` for Lock Screen widget)
- Card internal padding: `16pt` horizontal, `14pt` vertical
- Section vertical spacing: `14pt` to `16pt`
- Progress bar height: `3pt` capsule

---

## 3. Reference SwiftUI Implementations

### Spotify Logo Vector (`SpotifyLogo.swift`)

```swift
import SwiftUI

struct SpotifyLogo: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x1DB954))

            SpotifyWavesShape()
                .fill(Color.black)
                .scaleEffect(0.68)
        }
        .frame(width: size, height: size)
    }
}

private struct SpotifyWavesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0

        // Bottom wave
        path.move(to: CGPoint(x: 17.521 * sx, y: 17.34 * sy))
        path.addCurve(to: CGPoint(x: 16.5 * sx, y: 17.58 * sy), control1: CGPoint(x: 17.28 * sx, y: 17.7 * sy), control2: CGPoint(x: 16.86 * sx, y: 17.82 * sy))
        path.addCurve(to: CGPoint(x: 5.94 * sx, y: 16.44 * sy), control1: CGPoint(x: 13.68 * sx, y: 15.84 * sy), control2: CGPoint(x: 10.14 * sy, y: 15.48 * sy))
        path.addCurve(to: CGPoint(x: 5.04 * sx, y: 15.9 * sy), control1: CGPoint(x: 5.52 * sx, y: 16.56 * sy), control2: CGPoint(x: 5.16 * sx, y: 16.26 * sy))
        path.addCurve(to: CGPoint(x: 5.58 * sx, y: 15.0 * sy), control1: CGPoint(x: 4.92 * sx, y: 15.48 * sy), control2: CGPoint(x: 5.22 * sx, y: 15.12 * sy))
        path.addCurve(to: CGPoint(x: 17.22 * sx, y: 16.32 * sy), control1: CGPoint(x: 10.14 * sx, y: 13.98 * sy), control2: CGPoint(x: 14.1 * sx, y: 14.4 * sy))
        path.addCurve(to: CGPoint(x: 17.521 * sx, y: 17.34 * sy), control1: CGPoint(x: 17.64 * sx, y: 16.5 * sy), control2: CGPoint(x: 17.7 * sx, y: 16.98 * sy))
        path.closeSubpath()

        // Middle wave
        path.move(to: CGPoint(x: 18.96 * sx, y: 14.04 * sy))
        path.addCurve(to: CGPoint(x: 17.7 * sx, y: 14.34 * sy), control1: CGPoint(x: 18.66 * sx, y: 14.46 * sy), control2: CGPoint(x: 18.12 * sx, y: 14.64 * sy))
        path.addCurve(to: CGPoint(x: 5.76 * sx, y: 12.96 * sy), control1: CGPoint(x: 14.46 * sx, y: 12.36 * sy), control2: CGPoint(x: 9.54 * sx, y: 11.76 * sy))
        path.addCurve(to: CGPoint(x: 4.62 * sx, y: 12.36 * sy), control1: CGPoint(x: 5.28 * sx, y: 13.08 * sy), control2: CGPoint(x: 4.74 * sx, y: 12.84 * sy))
        path.addCurve(to: CGPoint(x: 5.22 * sx, y: 11.22 * sy), control1: CGPoint(x: 4.5 * sx, y: 11.88 * sy), control2: CGPoint(x: 4.74 * sx, y: 11.34 * sy))
        path.addCurve(to: CGPoint(x: 18.72 * sx, y: 12.84 * sy), control1: CGPoint(x: 9.6 * sx, y: 9.9 * sy), control2: CGPoint(x: 15.0 * sx, y: 10.56 * sy))
        path.addCurve(to: CGPoint(x: 18.96 * sx, y: 14.04 * sy), control1: CGPoint(x: 19.08 * sx, y: 13.02 * sy), control2: CGPoint(x: 19.26 * sx, y: 13.62 * sy))
        path.closeSubpath()

        // Top wave
        path.move(to: CGPoint(x: 20.28 * sx, y: 10.68 * sy))
        path.addCurve(to: CGPoint(x: 18.72 * sx, y: 10.98 * sy), control1: CGPoint(x: 19.98 * sx, y: 11.1 * sy), control2: CGPoint(x: 19.26 * sx, y: 11.28 * sy))
        path.addCurve(to: CGPoint(x: 5.16 * sx, y: 9.30 * sy), control1: CGPoint(x: 15.24 * sx, y: 8.4 * sy), control2: CGPoint(x: 8.82 * sx, y: 8.16 * sy))
        path.addCurve(to: CGPoint(x: 3.78 * sx, y: 8.58 * sy), control1: CGPoint(x: 4.56 * sx, y: 9.48 * sy), control2: CGPoint(x: 3.96 * sx, y: 9.12 * sy))
        path.addCurve(to: CGPoint(x: 4.5 * sx, y: 7.2 * sy), control1: CGPoint(x: 3.6 * sx, y: 7.98 * sy), control2: CGPoint(x: 3.96 * sx, y: 7.38 * sy))
        path.addCurve(to: CGPoint(x: 20.22 * sx, y: 8.82 * sy), control1: CGPoint(x: 8.76 * sx, y: 5.94 * sy), control2: CGPoint(x: 15.78 * sx, y: 6.18 * sy))
        path.addCurve(to: CGPoint(x: 20.28 * sx, y: 10.68 * sy), control1: CGPoint(x: 20.76 * sx, y: 9.12 * sy), control2: CGPoint(x: 20.58 * sx, y: 10.14 * sy))
        path.closeSubpath()

        return path
    }
}
```

---

### Player / Live Activity Card (`LyricTileView.swift`)

```swift
import SwiftUI

struct LyricTileView: View {
    let title: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    let isPlaying: Bool
    let progress: Double
    let positionMs: Int
    let durationMs: Int?
    let isHome: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row: Left Title/Artist, Right Status Badge
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "No Song Playing" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isHome ? Color.textPrimary : LiveActivityTokens.title)
                        .lineLimit(1)

                    if !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(isHome ? Color.textMuted : LiveActivityTokens.artist)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    if isPlaying {
                        Circle()
                            .fill(Color.accentAmber)
                            .frame(width: 7, height: 7)
                        Text("Playing")
                    } else {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                        Text("Paused")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHome ? Color.textMuted : LiveActivityTokens.artist)
            }

            // Lyrics Lines
            VStack(alignment: .leading, spacing: 4) {
                Text(currentLine.isEmpty ? "Waiting for lyrics…" : currentLine)
                    .font(.system(size: isHome ? 19 : 20, weight: .bold))
                    .foregroundColor(isHome ? Color.textPrimary : LiveActivityTokens.heroLyric)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let next = nextLine, !next.isEmpty {
                    Text(next)
                        .font(.system(size: isHome ? 14.5 : 15, weight: .medium))
                        .foregroundColor(isHome ? Color.textMuted : LiveActivityTokens.nextLyric)
                        .lineLimit(2)
                }
            }
            .padding(.top, 10)

            // Progress Line & Timestamps
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isHome ? Color.appBorder : LiveActivityTokens.trackBg)
                        Capsule()
                            .fill(isHome ? Color.accentAmber : LiveActivityTokens.trackFill)
                            .frame(width: max(3, geo.size.width * CGFloat(min(max(progress, 0), 1))))
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(timeText(positionMs))
                    Spacer()
                    if let durationMs {
                        Text("-" + timeText(max(0, durationMs - positionMs)))
                    }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(isHome ? Color.textMuted : LiveActivityTokens.timeText)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: isHome ? 20 : 28, style: .continuous)
                .fill(isHome ? Color.appSurface : LiveActivityTokens.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isHome ? 20 : 28, style: .continuous)
                .stroke(isHome ? Color.appBorder : LiveActivityTokens.border, lineWidth: 1)
        )
    }

    private func timeText(_ ms: Int) -> String {
        let totalSec = max(0, ms / 1000)
        let min = totalSec / 60
        let sec = totalSec % 60
        return String(format: "%d:%02d", min, sec)
    }
}
```

---

### Home View Structure (`HomeView.swift`)

```swift
import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: CaraokeViewModel
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. App Top Header
                    HStack {
                        Text("Caraoke")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.appSurface)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.appBorder, lineWidth: 1))
                        }
                    }
                    .padding(.top, 8)

                    // 2. Live Lyrics Switch Card (Directly ABOVE player)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Lyrics")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text("Dynamic Island and Lock Screen")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.isLiveLyricsEnabled)
                                .labelsHidden()
                                .tint(Color.accentAmber)
                        }

                        if let warning = viewModel.liveActivityGateMessage {
                            Text(warning)
                                .font(.system(size: 12))
                                .foregroundColor(.accentAmber)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentAmber.opacity(0.12))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.appSurface)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.appBorder, lineWidth: 1))

                    // 3. Player Card (Identical layout to Live Activity)
                    LyricTileView(
                        title: viewModel.currentTrackTitle,
                        artist: viewModel.currentTrackArtist,
                        currentLine: viewModel.currentLyricLine,
                        nextLine: viewModel.nextLyricLine,
                        isPlaying: viewModel.isPlaying,
                        progress: viewModel.playbackProgress,
                        positionMs: viewModel.positionMs,
                        durationMs: viewModel.durationMs,
                        isHome: true
                    )

                    // 4. Music Sources Card
                    VStack(spacing: 0) {
                        // Apple Music Row
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Music")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(viewModel.isAppleMusicConnected ? "Connected" : "Not connected")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textMuted)
                            }

                            Spacer()

                            if viewModel.isAppleMusicConnected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 12)

                        Divider().background(Color.appBorder)

                        // Spotify Row
                        HStack(spacing: 12) {
                            SpotifyLogo(size: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spotify")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(viewModel.isSpotifyConnected ? "Connected" : "Connect account")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .background(Color.appSurface)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.appBorder, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
```

---

### Settings Appearance Picker (`SettingsView.swift`)

```swift
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

struct SettingsView: View {
    @AppStorage("appearance_mode") private var selectedMode: AppearanceMode = .auto
    @State private var showingAppearanceSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    Section {
                        Button {
                            showingAppearanceSheet = true
                        } label: {
                            HStack {
                                Label {
                                    Text("Appearance")
                                        .foregroundColor(.textPrimary)
                                } icon: {
                                    Image(systemName: "circle.lefthalf.filled")
                                        .foregroundColor(.textPrimary)
                                }

                                Spacer()

                                Text(selectedMode.rawValue)
                                    .foregroundColor(.textMuted)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                        }
                    } header: {
                        Text("Display")
                            .foregroundColor(.textMuted)
                    }
                    .listRowBackground(Color.appSurface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAppearanceSheet) {
                AppearanceSheet(selectedMode: $selectedMode)
                    .presentationDetents([.height(220)])
            }
        }
    }
}

struct AppearanceSheet: View {
    @Binding var selectedMode: AppearanceMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.appSurface.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Appearance")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 16)

                Divider().background(Color.appBorder)

                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        dismiss()
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                                .font(.system(size: 16))
                                .foregroundColor(.textPrimary)

                            Spacer()

                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color.accentAmber)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }

                    if mode != AppearanceMode.allCases.last {
                        Divider().background(Color.appBorder).padding(.leading, 20)
                    }
                }
            }
        }
    }
}
```

---

## 4. Acceptance Checklist for SwiftUI Agent

- [ ] Lock screen Live Activity widget has NO playback transport controls (no play/pause/skip).
- [ ] Lock screen Live Activity widget has NO "Caraoke" text or logo icon.
- [ ] Song title (`13pt`) and artist (`11.5pt`) are smaller in the Live Activity header.
- [ ] Status indicator (`Playing` with amber dot) remains in top right of Live Activity.
- [ ] In-app home screen features "Live Lyrics" switch block directly ABOVE the music player card.
- [ ] Music player card on home screen is structurally identical to the Live Activity card (same header, lyrics, and progress bar; no transport buttons).
- [ ] Standalone lyrics page references and navigation are deleted.
- [ ] Spotify badge renders 3 curved black stripes inside a `#1DB954` green circle (no waveform glyph).
- [ ] Appearance in Settings is a single row opening an iOS picker sheet.
