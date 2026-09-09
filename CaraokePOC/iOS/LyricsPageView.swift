import SwiftUI
import UIKit

/// The full lyrics page. Opened by tapping the in-app player card, the
/// floating mini player, or a widget (deep link `caraoke://lyrics`) — widgets
/// used to point at a route the app never handled, so the tap did nothing.
///
/// Immersive by design: the background is the cover's average colour (the same
/// wash the widgets paint), the lyrics are left-aligned at ONE size and fill
/// the window, and every line slides up on its own as the song advances.
struct LyricsPageView: View {
    @ObservedObject var model: RideModeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var coverHex: String?

    /// Cover wash when the song has artwork, flat app background otherwise.
    private var wash: LinearGradient? { AppTheme.coverWash(coverHex) }
    private var fg: Color { wash == nil ? AppTheme.fg(scheme) : .white }
    private var muted: Color { wash == nil ? AppTheme.muted(scheme) : .white.opacity(0.55) }
    private var surface: Color { wash == nil ? AppTheme.surface(scheme) : .white.opacity(0.12) }
    private var border: Color { wash == nil ? AppTheme.border(scheme) : .white.opacity(0.16) }

    var body: some View {
        ZStack {
            (wash ?? LinearGradient(colors: [AppTheme.bg(scheme), AppTheme.bg(scheme)],
                                    startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                lyricStage
                transportRow
                progressBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
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

    // MARK: - Lyric stage

    /// Every previous and upcoming line is rendered; `ViewThatFits` picks the
    /// largest step that still fits the window, so the free space is spent on
    /// more lyrics instead of on emptiness.
    private var lyricStage: some View {
        ViewThatFits(in: .vertical) {
            stageRows(size: 30)
            stageRows(size: 27)
            stageRows(size: 24)
            stageRows(size: 21)
            stageRows(size: 18)
            stageRows(size: 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 12)
    }

    private func stageRows(size: CGFloat) -> some View {
        let items = rows
        return VStack(alignment: .leading, spacing: size * 0.3) {
            ForEach(items) { row in
                Text(row.text)
                    // One size everywhere; the active line is the bold one.
                    .font(.system(size: size, weight: row.isHero ? .bold : .regular))
                    .foregroundColor(row.isHero ? fg : muted.opacity(row.opacity))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.32), value: items.map(\.id))
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
            // 1 = the line right above the active one.
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
}
