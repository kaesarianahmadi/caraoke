import SwiftUI

/// The full lyrics page. Opened by tapping the full lyrics preview, the
/// floating mini player, or a widget (deep link `caraoke://lyrics`).
///
/// Black and orange, one identity row, full song lyrics centred on the active
/// line, and transport pinned at the bottom. Auto-follow pauses the moment the
/// user browses away and resumes from the "Back to current line" action.
struct LyricsPageView: View {
    @ObservedObject var model: RideModeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var lyricSize: CGFloat = LyricType.pageLyric
    @State private var isFollowingCurrentLine = true

    private var accent: Color { AppTheme.accent(.dark) }
    private var fg: Color { AppTheme.fg(.dark) }
    private var muted: Color { AppTheme.muted(.dark) }
    private var surface: Color { AppTheme.surface(.dark) }
    private var border: Color { AppTheme.border(.dark) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                lyricStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0)

                controls
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .layoutPriority(1)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header (identity once)

    private var header: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(model.trackTitle.isEmpty ? "Caraoke" : model.trackTitle)
                    .font(.headline)
                    .foregroundColor(fg)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !model.trackArtist.isEmpty {
                        Text(model.trackArtist)
                            .foregroundColor(muted)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(muted.opacity(0.6))
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 5, height: 5)
                        Text(statusText)
                            .lineLimit(1)
                    }
                    .foregroundColor(muted)
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            Button(intent: ResyncWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundColor(fg)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(surface))
                    .overlay(Circle().stroke(border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resync lyrics")
            .accessibilityHint("Samples the selected player and restarts lyric updates")

            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundColor(fg)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(surface))
                    .overlay(Circle().stroke(border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close lyrics")
        }
    }

    private var statusText: String {
        model.isOn ? model.lyricStatus.homeBadge : "Live Lyrics off"
    }

    private var statusTint: Color {
        guard model.isOn else { return muted }
        switch model.lyricStatus {
        case .stale, .expired:
            return AppTheme.warn
        case .noLyrics:
            return muted
        default:
            return accent
        }
    }

    private var artwork: some View {
        CoverArtworkView(artworkData: model.artworkData,
                         cornerRadius: 12,
                         artworkColorHex: model.artworkColorHex)
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(border, lineWidth: 1))
    }

    // MARK: - Lyric stage

    private var lyricStage: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        Color.clear
                            .frame(height: 60)
                            .id("lyric_start")

                        if !model.allLines.isEmpty {
                            ForEach(Array(model.allLines.enumerated()), id: \.offset) { index, line in
                                lyricRow(text: line.text,
                                         isHero: isLineHero(index: index, lineText: line.text),
                                         id: "line_\(index)")
                            }
                        } else if !model.currentLine.isEmpty || !model.upcomingLines.isEmpty {
                            // Fallback while the full track is still arriving.
                            ForEach(fallbackLines) { row in
                                lyricRow(text: row.text,
                                         isHero: row.isHero,
                                         id: row.id)
                            }
                        } else {
                            emptyState
                        }

                        Color.clear.frame(height: 180)
                    }
                    .padding(.horizontal, 20)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting || phase == .decelerating {
                        isFollowingCurrentLine = false
                    }
                }
                .onChange(of: model.currentLineIndex) { _, newIndex in
                    guard isFollowingCurrentLine else { return }
                    scrollToActiveLine(proxy: proxy, lineIndex: newIndex, lineText: model.currentLine)
                }
                .onChange(of: model.currentLine) { _, newLine in
                    guard isFollowingCurrentLine, model.currentLineIndex == nil else { return }
                    scrollToActiveLine(proxy: proxy, lineIndex: nil, lineText: newLine)
                }
                .onChange(of: model.trackTitle) { _, _ in
                    isFollowingCurrentLine = true
                }
                .onChange(of: model.isOn) { _, isOn in
                    if isOn { isFollowingCurrentLine = true }
                }
                .onAppear {
                    scrollToActiveLine(proxy: proxy,
                                       lineIndex: model.currentLineIndex,
                                       lineText: model.currentLine)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipped()

                if !isFollowingCurrentLine && hasCurrentLine {
                    backToCurrentLineButton(proxy: proxy)
                        .padding(.bottom, 12)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                       value: isFollowingCurrentLine)
        }
    }

    private var hasCurrentLine: Bool {
        model.currentLineIndex != nil || !model.currentLine.isEmpty
    }

    private func lyricRow(text: String, isHero: Bool, id: String) -> some View {
        Text(LyricSegmenter.segmentedDisplayText(for: text))
            .font(LyricType.font(size: lyricSize,
                                 weight: isHero ? LyricType.lyricHeroWeight : .regular))
            .foregroundColor(isHero ? fg : muted)
            .multilineTextAlignment(.leading)
            .lineSpacing(LyricType.lyricLineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                if isHero {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
            .accessibilityLabel(isHero ? "Current line: \(text)" : text)
            .id(id)
    }

    private func backToCurrentLineButton(proxy: ScrollViewProxy) -> some View {
        Button {
            isFollowingCurrentLine = true
            scrollToActiveLine(proxy: proxy,
                               lineIndex: model.currentLineIndex,
                               lineText: model.currentLine)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption.weight(.semibold))
                Text("Back to current line")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Resumes following the song")
    }

    private func isLineHero(index: Int, lineText: String) -> Bool {
        if let currentIdx = model.currentLineIndex {
            return index == currentIdx
        }
        return !model.currentLine.isEmpty && lineText == model.currentLine
    }

    private func scrollToActiveLine(proxy: ScrollViewProxy, lineIndex: Int?, lineText: String) {
        // While the full track is still arriving the page renders the fallback
        // stream, whose only stable target is the hero row.
        guard !model.allLines.isEmpty else {
            if !lineText.isEmpty {
                scroll(proxy, id: "hero")
            } else {
                scroll(proxy, id: "lyric_start")
            }
            return
        }
        if let lineIndex {
            scroll(proxy, id: "line_\(lineIndex)")
        } else if let index = model.allLines.firstIndex(where: { $0.text == lineText }) {
            scroll(proxy, id: "line_\(index)")
        } else if lineText.isEmpty {
            scroll(proxy, id: "lyric_start")
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, id: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
            proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.45))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyStatusText)
                .font(.title3.weight(.semibold))
                .foregroundColor(fg.opacity(0.9))
            Text(emptyDetailText)
                .font(.subheadline)
                .foregroundColor(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.top, 12)
    }

    private var emptyStatusText: String {
        guard model.isOn else { return "Live Lyrics is off" }
        switch model.lyricStatus {
        case .loading: return "Finding lyrics…"
        case .noLyrics: return "No lyrics found for this song"
        case .idle: return "Waiting for playback…"
        case .expired: return "Lyrics are out of date"
        case .stale: return "Ride ended"
        case .paused: return "Paused"
        case .playing: return "Lyrics will appear when singing begins"
        }
    }

    private var emptyDetailText: String {
        guard model.isOn else { return "Turn Live Lyrics on from Home to stream lyrics." }
        switch model.lyricStatus {
        case .loading: return "Matching this song to a lyric sheet."
        case .noLyrics: return "The song will keep playing without lines."
        case .idle: return "Play a song in your music app."
        case .expired: return "Tap Resync in the header to request a fresh sample."
        case .stale: return "Start Live Lyrics again from Home."
        case .paused: return "Playback is paused."
        case .playing: return "The first line will appear here."
        }
    }

    private struct FallbackRow: Identifiable {
        let id: String
        let text: String
        let isHero: Bool
    }

    private var fallbackLines: [FallbackRow] {
        var rows: [FallbackRow] = []
        for (idx, line) in model.previousLines.enumerated() {
            rows.append(FallbackRow(id: "prev_\(idx)", text: line, isHero: false))
        }
        if !model.currentLine.isEmpty {
            rows.append(FallbackRow(id: "hero", text: model.currentLine, isHero: true))
        }
        for (idx, line) in model.upcomingLines.enumerated() {
            rows.append(FallbackRow(id: "up_\(idx)", text: line, isHero: false))
        }
        return rows
    }

    // MARK: - Transport

    private var controls: some View {
        VStack(spacing: 8) {
            progressBar
            transportRow
            transportFeedback
        }
    }

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
                Capsule().fill(fg.opacity(0.16))
                Capsule().fill(accent)
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
                .font(.footnote.weight(.medium))
                .foregroundColor(AppTheme.warn)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
