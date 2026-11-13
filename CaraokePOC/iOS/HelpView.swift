import SwiftUI
import UIKit

/// Offline setup guide + troubleshooting, reached from Settings → Help & setup.
/// Content mirrors what the pipeline actually does: Live Lyrics → Live Activity,
/// the one-track push relay for the locked-phone case, widget/CarPlay resync.
/// Deliberately makes no "always works" promise — iOS delivery and widget
/// refresh cadence are outside the app's control.
struct HelpView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppTheme.background(scheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    quickStartSection
                    lockedPhoneSection
                    carPlaySection
                    resyncSection
                    spotifySection
                    widgetsSection
                    lyricsSection
                    privacySection
                    moreHelpSection
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Help & setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up lyrics everywhere")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.fg(scheme))
                .accessibilityAddTraits(.isHeader)
            Text("The setup steps work offline; links and policies need a connection. It covers Live Lyrics, CarPlay, the Lock Screen, the Dynamic Island, and widgets.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Quick start

    private var quickStartSection: some View {
        section("Quick start") {
            step("1", "Open Settings (gear on Home) → Connect music. Choose Apple Music, or connect Spotify.")
            step("2", "On Home, switch Live Lyrics on.")
            step("3", "Allow Live Activities: iOS Settings → Caraoke → Live Activities.")
            step("4", "Play a song in the chosen app. Lyrics appear on the Lock Screen, in the Dynamic Island, and on the CarPlay dashboard.")
            paragraph("Apple Music needs no account inside Caraoke — it reads the system player. Spotify needs authorization first; see Spotify setup below.")
        }
    }

    // MARK: - Locked phone (the driving case)

    private var lockedPhoneSection: some View {
        section("While your phone is locked") {
            paragraph("When Live Lyrics starts, Caraoke reads the current song's full lyric timeline and hands it to a push relay before iOS suspends the app (about 30 seconds after you leave it). The relay stores that schedule and the ride's Live Activity push token for the active session; stopping the ride tells it to drop the session. The relay advances the lines while the phone is locked, so the car screen does not need Caraoke running in front.")
            callout(
                icon: "exclamationmark.triangle.fill",
                title: "One song at a time",
                text: "The relay is armed for the song that was playing. If you change track, pause, or seek while Caraoke is suspended, the tile can hold the previous line or keep counting. Tap Resync to sample the selected player now; opening Caraoke only resumes normal polling.",
                tint: AppTheme.warn
            )
            paragraph("iOS ends a Live Activity on its own after several hours; reopen Caraoke to start a fresh one. Low Power Mode, Focus, or Live Activities being off can delay or hide updates.")
            docLink("Locked-phone details", path: "/docs#locked-phone")
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                Text("Open iOS Settings for Caraoke")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(AppTheme.accent(scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(AppTheme.fg(scheme).opacity(0.06)))
            .overlay(Capsule().stroke(AppTheme.border(scheme), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Caraoke settings where Live Activities can be allowed")
    }

    // MARK: - CarPlay

    private var carPlaySection: some View {
        section("CarPlay") {
            step("1", "Connect the iPhone to the car with wireless or wired CarPlay.")
            step("2", "Start Live Lyrics in Caraoke, then play a song.")
            step("3", "On the car screen, open the dashboard. The Caraoke tile mirrors the Live Activity.")
            paragraph("Nothing needs configuring while driving. On touchscreen CarPlay, the lyrics-only tile has a Resync arrow; the player tile resyncs from its cover and adds transport; the hybrid has both. On a non-touch screen, open Caraoke on the phone to resync.")
        }
    }

    // MARK: - Resync

    private var resyncSection: some View {
        section("If lyrics freeze or drift") {
            step("1", "Tap the Resync arrow on the CarPlay lyrics-only tile, the cover on the CarPlay player/hybrid tile, or the vinyl/album art on a Home Screen widget. The Live Activity itself has no Resync control. When Caraoke handles the tap, it samples the selected player right away. The widget-extension fallback repairs Spotify only; Apple Music needs the app path.")
            step("2", "In Caraoke, open the lyrics page and tap Resync in the header. Opening the app from a widget also resumes normal polling, but does not force an immediate sample or relay rearm.")
            step("3", "Still stale? Switch Live Lyrics off, then on.")
            step("4", "Confirm Settings → Connect music matches the app that is actually playing.")
            step("5", "Paused or seeked from the car? Resume playback, then seek once in the track. With Caraoke open, it re-aligns within a couple of seconds.")
            step("6", "No tile at all? Check iOS Settings → Caraoke → Live Activities, then switch Live Lyrics off and on.")
            step("7", "Lock Screen and Dynamic Island have no Resync control — open Caraoke instead. On non-touchscreen CarPlay, do the same.")
            docLink("Open the full troubleshooting guide", path: "/docs#problems")
        }
    }

    // MARK: - Spotify

    private var spotifySection: some View {
        section("Spotify setup") {
            paragraph("Spotify is a limited beta. The built-in credentials work for a small allowlist; if you get an authorization or 403 error, connect with your own free Client ID. That bypasses Caraoke's shared limit.")
            step("1", "Open developer.spotify.com/dashboard and log in.")
            step("2", "Create an app named Caraoke and select Web API.")
            step("3", "Under App Settings → Redirect URIs add exactly caraoke://spotify-callback.")
            step("4", "Copy the Client ID from Basic Information.")
            step("5", "In Caraoke: Settings → Connect music → Spotify, paste the Client ID, then Save & Connect.")
            paragraph("To repair a broken connection, reopen the Spotify row and choose Reconnect. Disconnect is in the same expanded panel.")
            paragraph("Spotify access uses now-playing and playback-state scopes plus playback control (play, pause, skip). Caraoke requests no library or playlist scopes.")
            spotifyDashboardLink
        }
    }

    private var spotifyDashboardLink: some View {
        Link(destination: URL(string: "https://developer.spotify.com/dashboard")!) {
            HStack(spacing: 4) {
                Text("Open Spotify Developer Dashboard")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .foregroundColor(AppTheme.accent(scheme))
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Widgets

    private var widgetsSection: some View {
        section("Widgets & StandBy") {
            step("1", "Long-press the Home Screen, tap +, search Caraoke, then pick a size.")
            step("2", "Tap the vinyl disc, album art, or Resync to request a fresh sample. Rendering still follows iOS widget scheduling.")
            step("3", "For themes, size previews, and widget options, open Home → Widget inside Caraoke.")
            step("4", "StandBy: place the iPhone horizontally on a charger, then add the Caraoke widget to the StandBy screen.")
            paragraph("iOS chooses when widgets redraw on its own; a tap requests a fresh sample, but the redraw can lag. For continuous line-by-line updates use Live Lyrics.")
        }
    }

    // MARK: - Lyrics sources

    private var lyricsSection: some View {
        section("Missing or early lyrics") {
            paragraph("Caraoke asks LRCLIB and YouTube Music at the same time and uses the first synchronized lyric sheet that comes back. If neither has one, the song plays without lines — the title, artist, and progress still update.")
            paragraph("If lines run ahead or behind, seek once in the music app. Bluetooth and car audio processing can add a fraction of a second of delay that no lyric file can predict.")
            Text("Lyrics © their respective rights holders. Track data comes from the active music source.")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Privacy & data

    private var privacySection: some View {
        section("Privacy & data") {
            paragraph("There is no Caraoke account. To match lyrics, Caraoke sends the track title and artist to LRCLIB and YouTube Music (LRCLIB also receives the duration). Crash diagnostics go to Sentry and Caraoke's crash relay; usage signals go to TelemetryDeck, and purchases use Apple StoreKit with RevenueCat.")
            paragraph("For locked-phone lyrics, Caraoke's push relay stores the current ride's lyric schedule and Live Activity push token. Caraoke sends a stop request when the ride ends; the relay drops the session only after it successfully processes that request or the session expires, so a failed request can leave it stored. Spotify tokens stay in the device Keychain.")
            docLink("Privacy Policy", path: "/privacy")
            docLink("Terms of Use", path: "/terms")
        }
    }

    // MARK: - More help

    private var moreHelpSection: some View {
        section("More help") {
            Link(destination: URL(string: "https://caraokeapp.com/docs")!) {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                        .font(.system(size: 14, weight: .medium))
                    Text("Setup guides at caraokeapp.com")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                }
                .foregroundColor(AppTheme.fg(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            Divider().overlay(AppTheme.border(scheme))
            Link(destination: URL(string: "mailto:support@caraoke.app?subject=Caraoke%20help")!) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14, weight: .medium))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email support")
                            .font(.system(size: 14, weight: .semibold))
                        Text("support@caraoke.app")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                .foregroundColor(AppTheme.fg(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    private var footnote: some View {
        Text("Caraoke · Designed for passengers · Do not interact with the phone while driving")
            .font(.system(size: 11))
            .foregroundColor(AppTheme.muted(scheme))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Layout helpers

    private func docLink(_ title: String, path: String) -> some View {
        Link(destination: URL(string: "https://caraokeapp.com" + path)!) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .foregroundColor(AppTheme.accent(scheme))
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number + ".")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.accent(scheme))
                .frame(minWidth: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.fg(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(AppTheme.muted(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func callout(icon: String, title: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }
}