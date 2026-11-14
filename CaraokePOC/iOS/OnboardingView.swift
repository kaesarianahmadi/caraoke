import SwiftUI

/// Short dismissible welcome sheet. Presented once by the root app
/// (first-launch persistence lives in `CaraokeApp.swift`) and replayable
/// from Settings → Welcome guide. Explains only behavior the app actually
/// supports: choose a music source, turn on Live Lyrics, open Full lyrics.
/// No permission prompts, no competitor screenshots, no external images.
struct OnboardingView: View {
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.background(scheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    steps
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom) {
                actions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .background(AppTheme.bg(scheme))
            }
        }
        .preferredColorScheme(AppearanceSettings.preferredScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Caraoke")
                .font(.title.weight(.bold))
                .foregroundColor(AppTheme.fg(scheme))
                .accessibilityAddTraits(.isHeader)
            Text("Live lyrics while you ride — made for passengers.")
                .font(.subheadline)
                .foregroundColor(AppTheme.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        VStack(spacing: 0) {
            stepRow(number: 1, symbol: "music.note.list", title: "Choose your music",
                    body: "Choose Apple Music or connect Spotify in Settings → Music connections.")
            divider
            stepRow(number: 2, symbol: "waveform", title: "Turn on Live Lyrics",
                    body: "Enable the session from Home for supported external displays.")
            divider
            stepRow(number: 3, symbol: "rectangle.on.rectangle", title: "Open Full lyrics",
                    body: "Tap the Full lyrics preview to read the whole song.")
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(AppTheme.border(scheme), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stepRow(number: Int, symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(AppTheme.accent(scheme).opacity(0.14))
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.accent(scheme))
                }
                .frame(width: 34, height: 34)
                Text("Step \(number)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.muted(scheme))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.fg(scheme))
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number) of 3: \(title). \(body)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var divider: some View {
        Divider().overlay(AppTheme.border(scheme))
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                if reduceMotion {
                    onDismiss()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) { onDismiss() }
                }
            } label: {
                Text("Get started")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(scheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.accent(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.accent(scheme).opacity(0.6), lineWidth: 1))
            .accessibilityHint("Dismiss the welcome sheet and start using Caraoke")

            Button {
                if reduceMotion {
                    onDismiss()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) { onDismiss() }
                }
            } label: {
                Text("Not now")
                    .font(.headline.weight(.medium))
                    .foregroundColor(AppTheme.accent(scheme))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Dismiss the welcome sheet without starting setup")
        }
    }
}