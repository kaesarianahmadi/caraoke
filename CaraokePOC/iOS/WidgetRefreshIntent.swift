#if os(iOS)
import AppIntents
import os

/// System-dispatched continuation. Stopped/replaced cycles finish normally;
/// throwing cancellation here exercises a crashing LinkServices path on iOS 26.5.2.
struct WidgetRefreshIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Caraoke Widgets"
    static let isDiscoverable = false

    @Parameter(title: "Session") var session: String
    @Parameter(title: "Cycle") var cycle: Int

    init() {}

    init(session: String, cycle: Int = 0) {
        self.session = session
        self.cycle = cycle
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard SharedWidgetStore.isWidgetRefreshSession(session) else { return .result() }
#if !CARAOKE_WIDGET_EXTENSION
        let active = await MainActor.run {
            guard SharedWidgetStore.isWidgetRefreshSession(session) else { return false }
            AppModel.shared.startRideSession()
            AppModel.shared.ride.ensureActivity()
            return true
        }
        guard active else { return .result() }
#endif
        let delay = WidgetRefreshSession.nextRefreshDelay(payload: SharedWidgetStore.read(), now: Date())
        Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
            .notice("refresh intent cycle=\(cycle, privacy: .public) nextIn=\(delay, privacy: .public)")
        SharedWidgetStore.requestReload(reason: "intent-cycle")
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch is CancellationError {
            return .result()
        }
        guard SharedWidgetStore.isWidgetRefreshSession(session) else { return .result() }
        return .result(opensIntent: WidgetRefreshIntent(session: session, cycle: cycle &+ 1))
    }
}
#endif
