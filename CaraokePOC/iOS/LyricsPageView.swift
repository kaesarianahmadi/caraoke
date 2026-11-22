import SwiftUI
import UIKit

/// Full-screen Portrait Karaoke Stage with natural verses, distance-graduated
/// opacity ladder, bilingual subtitles, and Bluetooth sync offset controls.
struct LyricsPageView: View {
    @ObservedObject var model: RideModeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppearanceSettings.boldTextKey) private var boldText = true
    @AppStorage(AppearanceSettings.backdropStyleKey) private var backdropRaw = LyricsBackdropStyle.ambientCover.rawValue
    @AppStorage(AppearanceSettings.showTranslationsKey) private var showTranslations = true

    @State private var userScrolled = false
    @State private var showOffsetPopover = false
    @State private var isResyncing = false

    private var backdropStyle: LyricsBackdropStyle { LyricsBackdropStyle(rawValue: backdropRaw) ?? .ambientCover }
    private var useBoldLyrics: Bool { boldText || legibilityWeight == .bold }

    var body: some View {
        ZStack {
            Color(hex: 0x09090B).ignoresSafeArea()
            if let wash = CoverArtworkView.controlledStageWash(model.artworkColorHex, enabled: backdropStyle == .ambientCover) {
                wash.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                grabber
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                lyricsScrollArea

                footerControls
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            CoverArtworkView(
                artworkData: model.artworkData,
                cornerRadius: 10,
                artworkColorHex: model.artworkColorHex
            )
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(model.trackTitle.isEmpty ? "No Track Playing" : model.trackTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !model.trackArtist.isEmpty {
                        Text(model.trackArtist)
                            .lineLimit(1)
                        Text("·")
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.isPlaybackActive ? AppTheme.ok : AppTheme.darkAccent)
                            .frame(width: 6, height: 6)
                        Text(model.lyricStatus.homeBadge)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
            }

            Spacer(minLength: 4)

            // Bluetooth / CarPlay timing offset
            Button {
                showOffsetPopover.toggle()
            } label: {
                Text(offsetBadgeText)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(model.lyricOffsetMs == 0 ? .white.opacity(0.85) : .black)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 36, minHeight: 34)
                    .background(Capsule().fill(model.lyricOffsetMs == 0 ? Color.white.opacity(0.14) : AppTheme.darkAccent))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lyric timing offset \(offsetBadgeText)")
            .popover(isPresented: $showOffsetPopover) {
                offsetPopoverContent
                    .presentationCompactAdaptation(.popover)
            }

            Button {
                guard !isResyncing else { return }
                isResyncing = true
                Task {
                    await model.resync()
                    isResyncing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resync lyrics")

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close lyrics")
        }
    }

    private var offsetBadgeText: String {
        if model.lyricOffsetMs == 0 { return "±0s" }
        let sec = Double(model.lyricOffsetMs) / 1000.0
        return String(format: "%+.2gs", sec)
    }

    private var offsetPopoverContent: some View {
        VStack(spacing: 12) {
            Text("Bluetooth Sync Offset")
                .font(.subheadline.weight(.semibold))
            Text(offsetBadgeText)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundColor(AppTheme.darkAccent)
            HStack(spacing: 10) {
                Button("-0.25s") { model.adjustLyricOffset(by: -250) }
                    .buttonStyle(.bordered)
                Button("Reset") { model.resetLyricOffset() }
                    .buttonStyle(.bordered)
                Button("+0.25s") { model.adjustLyricOffset(by: 250) }
                    .buttonStyle(.bordered)
            }
            Text("Shift earlier or later to match car Bluetooth audio delay.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .padding(16)
    }

    // MARK: - Lyrics Scroll Area

    private var lyricsScrollArea: some View {
        ZStack(alignment: .bottom) {
            if model.allLines.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text(emptyLyricsTitle)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(emptyLyricsSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            Color.clear.frame(height: 60)

                            ForEach(Array(model.allLines.enumerated()), id: \.element.startMs) { index, line in
                                lyricRow(line: line, index: index)
                                    .id(index)
                            }

                            Color.clear.frame(height: 120)
                        }
                        .padding(.horizontal, 24)
                    }
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            if !userScrolled { userScrolled = true }
                        }
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.88),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onAppear {
                        scrollToCurrent(proxy: proxy, animated: false)
                    }
                    .onChange(of: model.currentLineIndex) { _, _ in
                        guard !userScrolled else { return }
                        scrollToCurrent(proxy: proxy, animated: !reduceMotion)
                    }
                }
            }

            if userScrolled && !model.allLines.isEmpty {
                Button {
                    userScrolled = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.to.line")
                        Text("Resume live sync")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppTheme.darkAccent))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy, animated: Bool) {
        let target = model.currentLineIndex ?? 0
        guard model.allLines.indices.contains(target) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func lyricRow(line: LyricLine, index: Int) -> some View {
        let active = model.currentLineIndex ?? -1
        let distance = active >= 0 ? abs(index - active) : index + 1
        let isCurrent = index == active
        let fontSize: CGFloat = isCurrent ? 28 : (distance == 1 ? 24 : (distance == 2 ? 22 : 20))
        let weight: Font.Weight = isCurrent ? (useBoldLyrics ? .bold : .semibold) : (distance == 1 ? .medium : .regular)
        let opacity: Double = isCurrent ? 1.0 : (distance == 1 ? 0.62 : (distance == 2 ? 0.38 : 0.22))

        return HStack(alignment: .top, spacing: 12) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.darkAccent)
                    .frame(width: 3.5)
                    .padding(.vertical, 3)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(line.text)
                    .font(.system(size: fontSize, weight: weight))
                    .foregroundColor(.white.opacity(opacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showTranslations, let tr = line.translation, !tr.isEmpty {
                    Text(tr)
                        .font(.system(size: fontSize * 0.72, weight: .medium))
                        .foregroundColor(.white.opacity(opacity * 0.68))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.currentLineIndex)
    }

    private var emptyLyricsTitle: String {
        switch model.lyricStatus {
        case .loading: return "Finding synced lyrics…"
        case .noLyrics: return "No synced lyrics found"
        case .idle: return "Waiting for playback"
        default: return "Instrumental"
        }
    }

    private var emptyLyricsSubtitle: String {
        switch model.lyricStatus {
        case .noLyrics: return "Enjoy the music — playback controls stay ready below."
        case .idle: return "Start playing a track in Apple Music or Spotify."
        default: return "Checking LRCLIB and YouTube Music."
        }
    }

    // MARK: - Footer Progress & Transport

    private var footerControls: some View {
        VStack(spacing: 14) {
            if let error = model.transportError {
                Text(error)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppTheme.warn)
                    .lineLimit(2)
            }

            // Progress bar + tabular timestamps
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * max(0, min(1, model.progress)))
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(ms: model.positionMs))
                    Spacer()
                    Text(remainingTimeText)
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.62))
            }

            HStack(spacing: 40) {
                Button { Task { await model.transport(.previous) } } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous track")

                Button { Task { await model.transport(.playPause) } } label: {
                    Image(systemName: model.isPlaybackActive ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.isPlaybackActive ? "Pause" : "Play")

                Button { Task { await model.transport(.next) } } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next track")
            }
            .buttonStyle(.plain)

            Text("Use while parked · Designed for passengers")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.38))
        }
    }

    private var remainingTimeText: String {
        guard let dur = model.durationMs, dur > 0 else { return "--:--" }
        let rem = max(0, dur - model.positionMs)
        return "-\(formatTime(ms: rem))"
    }

    private func formatTime(ms: Int) -> String {
        let totalSec = max(0, ms / 1000)
        return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
    }
}
