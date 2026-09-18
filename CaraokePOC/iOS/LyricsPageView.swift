import SwiftUI
import UIKit

/// The full lyrics page. Opened by tapping the in-app player card, the
/// floating mini player, or a widget (deep link `caraoke://lyrics`).
///
/// Immersive by design: deep dark cover wash, full song lyrics in a smooth
/// scrolling view with the active lyric pinned to vertical centre (45%),
/// and transport controls pinned at the bottom.
struct LyricsPageView: View {
    @ObservedObject var model: RideModeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var coverHex: String?

    /// Darkened cover wash for high contrast in all modes.
    private var wash: LinearGradient? { CoverArtworkView.wash(coverHex) }
    private var fg: Color { .white }
    private var muted: Color { .white.opacity(0.60) }
    private var surface: Color { .white.opacity(0.14) }
    private var border: Color { .white.opacity(0.18) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let wash {
                wash.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                lyricStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0)

                VStack(spacing: 8) {
                    progressBar
                    transportRow
                    transportFeedback
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .layoutPriority(1)
            }
        }
        .preferredColorScheme(.dark)
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

    // MARK: - Lyric Stage (Full window utilization & centered auto-scrolling)

    private var lyricStage: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    // Headroom so top lines can scroll to vertical center
                    Color.clear.frame(height: 80)

                    // Song name and author at the top of the lyrics window
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.trackTitle.isEmpty ? "Caraoke" : model.trackTitle)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(fg)
                        if !model.trackArtist.isEmpty {
                            Text(model.trackArtist)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(muted)
                        }
                    }
                    .id("lyric_header")
                    .padding(.bottom, 16)

                    if !model.allLines.isEmpty {
                        ForEach(Array(model.allLines.enumerated()), id: \.offset) { index, line in
                            let isHero = !model.currentLine.isEmpty && line.text == model.currentLine
                            let isPast = isLineInPast(index: index)
                            Text(line.text)
                                .font(LyricType.font(size: LyricType.pageLyric, weight: isHero ? LyricType.lyricHeroWeight : .regular))
                                .foregroundColor(isHero ? fg : (isPast ? muted.opacity(0.55) : muted.opacity(0.90)))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(LyricType.lyricLineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id("line_\(index)")
                        }
                    } else if !model.currentLine.isEmpty || !model.upcomingLines.isEmpty {
                        // Fallback when full track is still arriving
                        ForEach(fallbackLines) { row in
                            Text(row.text)
                                .font(LyricType.font(size: LyricType.pageLyric, weight: row.isHero ? LyricType.lyricHeroWeight : .regular))
                                .foregroundColor(row.isHero ? fg : muted.opacity(row.opacity))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(LyricType.lyricLineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(row.id)
                        }
                    } else {
                        // Empty / loading state
                        VStack(alignment: .leading, spacing: 10) {
                            Text(emptyStatusText)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(muted)
                        }
                        .padding(.top, 20)
                    }

                    // Bottom padding so last lines scroll into center
                    Color.clear.frame(height: 220)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: model.currentLine) { _, newLine in
                scrollToActiveLine(proxy: proxy, lineText: newLine)
            }
            .onAppear {
                scrollToActiveLine(proxy: proxy, lineText: model.currentLine)
            }
        }
    }

    private func isLineInPast(index: Int) -> Bool {
        guard let heroIndex = model.allLines.firstIndex(where: { $0.text == model.currentLine }) else {
            return false
        }
        return index < heroIndex
    }

    private func scrollToActiveLine(proxy: ScrollViewProxy, lineText: String) {
        if let index = model.allLines.firstIndex(where: { $0.text == lineText }) {
            withAnimation(.easeInOut(duration: 0.42)) {
                proxy.scrollTo("line_\(index)", anchor: UnitPoint(x: 0.5, y: 0.45))
            }
        } else if lineText.isEmpty {
            withAnimation(.easeInOut(duration: 0.42)) {
                proxy.scrollTo("lyric_header", anchor: UnitPoint(x: 0.5, y: 0.45))
            }
        }
    }

    private var emptyStatusText: String {
        switch model.lyricStatus {
        case .loading: return "Finding lyrics…"
        case .noLyrics: return "No lyrics found for this song"
        case .idle: return model.isOn ? "Waiting for playback…" : "Turn switch on to stream lyrics"
        case .stale: return "Ride ended"
        default: return "Lyrics will appear when singing begins"
        }
    }

    private struct FallbackRow: Identifiable {
        let id: String
        let text: String
        let isHero: Bool
        let opacity: Double
    }

    private var fallbackLines: [FallbackRow] {
        var rows: [FallbackRow] = []
        for (idx, line) in model.previousLines.enumerated() {
            rows.append(FallbackRow(id: "prev_\(idx)", text: line, isHero: false, opacity: 0.55))
        }
        if !model.currentLine.isEmpty {
            rows.append(FallbackRow(id: "hero", text: model.currentLine, isHero: true, opacity: 1.0))
        }
        for (idx, line) in model.upcomingLines.enumerated() {
            rows.append(FallbackRow(id: "up_\(idx)", text: line, isHero: false, opacity: 0.90))
        }
        return rows
    }

    // MARK: - Transport

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
                Capsule().fill(fg.opacity(0.18))
                Capsule().fill(fg.opacity(0.92))
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(model.progress, 0), 1))))
            }
        }
        .frame(height: 4)
    }

    /// Brief transport failure message shown below the progress bar.
    @ViewBuilder
    private var transportFeedback: some View {
        if let err = model.transportError {
            Text(err)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.warn)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
                .transition(.opacity)
        }
    }
}
