#if os(iOS)
import AppIntents
import WidgetKit

/// The budget-bypass refresh intent.
///
/// **Why this exists.** An intent with NO `systemProtocol` is just a button.
/// Device log, 2026-11-03, phone plugged into CarPlay for 30 minutes:
/// `ResyncWidgetIntent` ran twice and chronod never once printed "intent
/// recently ran" for our extension — 0 lines, against the competitor's 1 313.
/// Their tiles are admitted to reload every 5 s regardless; ours showed
/// `timelineExhausted-…-budgeted-1`, the metered path.
///
/// **What they do.** Their widget extension's intent metadata
/// (`extract.actionsdata`, both their targets — the attribute is registered on
/// the extension, not the app) declares exactly two system protocols:
///
///     WidgetRefreshAppIntent → AudioStarting   (Swift: AudioPlaybackIntent)
///     RefreshAppIntent       → SessionStarting (Swift: LiveActivityIntent)
///
/// `AudioStartingIntent` / `LiveActivityStartingIntent` are the iOS 16/17
/// spellings and are deprecated on 26; `AudioPlaybackIntent` (iOS 17+) is the
/// current `SystemIntent` with the same meaning. Running such an intent is what
/// makes chronod allow the *next* reload at the free tier, with a
/// self-re-arming follow-on, instead of metering it.
///
/// **Two details copied deliberately:** a changing parameter, so successive
/// runs aren't collapsed into one system cache entry (all of their intents
/// carry `random: Int`); and registration in both targets.
///
/// `perform()` is intentionally empty. The reload still happens in
/// `SharedWidgetStore.requestReload`; this intent exists only so chronod has a
/// recent run to grant against. Reloading in here too would double every ask.
struct WidgetRefreshIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Refresh Caraoke Widgets"
    static let description = IntentDescription("Refreshes the Caraoke lyric tiles.")

    @Parameter(title: "Nonce")
    var nonce: Int

    init() {
        self.nonce = Int.random(in: 0..<Int.max)
    }

    init(nonce: Int) {
        self.nonce = nonce
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
#endif
