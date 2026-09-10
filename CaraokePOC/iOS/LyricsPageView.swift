import SwiftUI
import UIKit

/// The full lyrics page. Opened by tapping the in-app player card, the
/// floating mini player, or a widget (deep link `caraoke://lyrics`) — widgets
/// used to point at a route the app never handled, so the tap did nothing.
///
/// Immersive by design: the background is the cover's average colour (the same
/// wash the widgets paint), the lyrics are left-aligned at ONE size and fill
/// the window, and every line slides up on its own as the song advances.
///
/// Build 42: transport + progress bar pinned to bottom, NEVER overlapped.
/// Active lyric sits in vertical centre between header and controls.
struct LyricsPageView: View {
    @ObservedObject var model: RideModeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var coverHex: String?

    /// Cover wash when the song has artwork, flat app background otherwise.
    private var wash: LinearGradient? { CoverArtworkView.wash(coverHex) }
    private var fg: Color { wash == nil ? AppTheme.fg(scheme) : .white }
    private var muted: Color { wash == nil ? AppTheme.muted(scheme) : .white.opacity(0.55) }
    private var surface: Color { wash == nil ? AppTheme.surface(scheme) : .white.opacity(0.12) }
    private var border: Color { wash == nil ? AppTheme.border(scheme) : .white.opacity(0.16) }

    var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                (wash ?? LinearGradient(colors: [AppTheme.bg(scheme), AppTheme.bg(scheme)],
                                        startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    lyricStage(boundedBy: outerGeo.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .layoutPriority(0)
                    transportRow.layoutPriority(1)
                    progressBar.layoutPriority(1)
                    transportFeedback
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .onAppear { coverHex = model.artworkData.flatMap(UIImage.init(data:))?.averageColorHex }
        .onChange(of: model.artworkData) { _, data in
            coverHex = data.flatMap(UIImage.init(data:))?.averageColorHex
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(model.trackTitle.isEmpty ? "Caraoke" : model.trackTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(fg)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(fg)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(surface))
                    .overlay(Circle().stroke(border, lineWidth: 1))
            }
            .accessibilityLabel("Close lyrics")
        }
    }

    private var subtitle: String {
        if !model.trackArtist.isEmpty { return model.trackArtist }
        return model.lyricStatus.homeBadge
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let data = model.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(surface)
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(muted)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(border, lineWidth: 1))
    }

    // MARK: - Lyric stage (Build 42: bounded height, no overlap, centred)

    /// Build 42: bounded lyric stage. Computes available lyric space as
    /// totalHeight minus header, transport, progress bar and padding.
    /// The active line stays vertically centred in this bounded area.
    private func lyricStage(boundedBy totalHeight: CGFloat) -> some View {
        let chrome: CGFloat = 52 + 8      // header
            + 60 + 4 + 20                 // transport + progress + padding
            + 20 + 24                     // outer VStack padding
        let availableHeight = max(100, totalHeight - chrome)

        return GeometryReader { geo in
            let rows = visibleRows(viewportHeight: min(geo.size.height, availableHeight))
            VStack(alignment: .leading, spacing: LyricType.pageLyric * 0.34) {
                ForEach(rows) { row in
                    Text(row.text)
                        .font(.system(size: LyricType.pageLyric,
                                      weight: row.isHero ? LyricType.lyricWeight : LyricType.lyricNeighborWeight))
                        .foregroundColor(row.isHero ? fg : muted.opacity(row.opacity))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(LyricType.lyricLineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeInOut(duration: 0.32), value: rows.map(\.id))
        }
        .frame(maxWidth: .infinity, maxHeight: availableHeight)
        .padding(.vertical, 12)
        .onAppear {
            DispatchQueue.main.async { centresWindow = true }
        }
    }

    /// How many already-sung lines to keep on screen above the active one.
    /// Starts at the whole history (so opening the page fills the window) and
    /// converges on the middle as the song advances, which keeps the active
    /// line centred instead of walking down to the bottom edge.
    @State private var centresWindow = false

    private func visibleRows(viewportHeight: CGFloat) -> [PageRow] {
        let all = rows
        guard let heroIndex = all.firstIndex(where: \.isHero) else { return all }
        guard viewportHeight > 0 else { return all }

        let capacity = max(7, Int(viewportHeight / (LyricType.pageLyric * 1.34)))
        let history = heroIndex
        let showAbove = centresWindow ? max(0, capacity / 2) : history
        let showBelow = max(1, capacity - showAbove - 1)
        let start = max(0, heroIndex - showAbove)
        let end = min(all.count, heroIndex + showBelow + 1)
        return Array(all[start..<end])
    }

    private struct PageRow: Identifiable {
        let id: String
        let text: String
        let isHero: Bool
        let opacity: Double
    }

    private var rows: [PageRow] {
        var seen: [String: Int] = [:]
        func uniqueID(_ text: String) -> String {
            let count = seen[text, default: 0]
            seen[text] = count + 1
            return count == 0 ? text : "\(text)#\(count)"
        }
        let previous = model.previousLines
        var rows: [PageRow] = []
        for (index, line) in previous.enumerated() {
            let distance = Double(previous.count - index)
            rows.append(PageRow(id: uniqueID(line), text: line, isHero: false,
                                opacity: max(0.22, 0.62 - distance * 0.1)))
        }
        rows.append(PageRow(id: uniqueID(heroText), text: heroText, isHero: true, opacity: 1))
        for (index, line) in model.upcomingLines.enumerated() {
            rows.append(PageRow(id: uniqueID(line), text: line, isHero: false,
                                opacity: max(0.2, 0.66 - Double(index) * 0.08)))
        }
        return rows
    }

    private var heroText: String {
        if !model.currentLine.isEmpty { return model.currentLine }
        return model.isOn ? "Play a song to see lyrics" : "Switch on Live Lyrics to start"
    }

    // MARK: - Transport (drives whichever player is the active source)

    private var transportRow: some View {
        HStack(spacing: 40) {
            transportButton("backward.fill", size: 24, label: "Previous song") {
                Task { await model.transport(.previous) }
            }
            transportButton(model.isPlaybackActive ? "pause.fill" : "play.fill",
                            size: 32,
                            label: model.isPlaybackActive ? "Pause" : "Play") {
                Task { await model.transport(.playPause) }
            }
            transportButton("forward.fill", size: 24, label: "Next song") {
                Task { await model.transport(.next) }
            }
        }
        .foregroundColor(fg)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private func transportButton(_ name: String, size: CGFloat, label: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(fg.opacity(0.14))
                Capsule().fill(fg.opacity(0.92))
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(model.progress, 0), 1))))
            }
        }
        .frame(height: 4)
    }

    /// Brief transport failure message shown below the progress bar.
    /// Auto-clears when the next transport action succeeds.
    @ViewBuilder
    private var transportFeedback: some View {
        if let err = model.transportError {
            Text(err)
                .font(.system(size: 11))
                .foregroundColor(muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .transition(.opacity)
        }
    }
}
