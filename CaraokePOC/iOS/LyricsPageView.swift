import SwiftUI
import UIKit

/// The full lyrics page. Opened by tapping the in-app player card, the
/// floating mini player, or a widget (deep link `caraoke://lyrics`) — widgets
/// used to point at a route the app never handled, so the tap did nothing.
struct LyricsPageView: View {
    @ObservedObject var model: RideModeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppTheme.bg(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                lyricStage
                Spacer(minLength: 16)
                transportRow
                progressBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(model.trackTitle.isEmpty ? "Caraoke" : model.trackTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.muted(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.surface(scheme)))
                    .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.surface(scheme))
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.muted(scheme))
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.border(scheme), lineWidth: 1))
    }

    // MARK: - Lyric stage (sliding karaoke block)

    private var lyricStage: some View {
        ZStack {
            VStack(spacing: 14) {
                ForEach(Array(model.previousLines.suffix(2).enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.muted(scheme).opacity(0.55 - Double(index) * 0.18))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Text(heroText)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(AppTheme.fg(scheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(model.upcomingLines.prefix(3).enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.muted(scheme).opacity(0.62 - Double(index) * 0.16))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            // New line pushes the old one up and slides in from the bottom.
            .id(slideKey)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: slideKey)
    }

    private var slideKey: String { "\(model.lyricStatus.rawValue)|\(model.currentLine)" }

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
        .foregroundColor(AppTheme.fg(scheme))
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
                Capsule().fill(AppTheme.fg(scheme).opacity(0.14))
                Capsule().fill(AppTheme.accent(scheme))
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(model.progress, 0), 1))))
            }
        }
        .frame(height: 4)
    }
}
