#if os(iOS)
import AppIntents
import os

/// System-dispatched continuation. Stopped/replaced cycles finish normally;
/// throwing cancellation here exercises a crashing LinkServices path on iOS 26.5.2.
struct WidgetRefreshIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Caraoke Widgets"
    static let isDiscoverable = false

    @Parameter(title: "Session", default: "") var session: String
    @Parameter(title: "Cycle", default: 0) var cycle: Int

    init() {}

    init(session: String, cycle: Int = 0) {
        self.session = session
        self.cycle = cycle
    }

    func perform() async throws -> IntentResultContainer<String, WidgetRefreshIntent, Never, Never> {
        var result: IntentResultContainer<String, WidgetRefreshIntent, Never, Never> =
            .result(value: session, opensIntent: WidgetRefreshIntent(session: session, cycle: cycle &+ 1))
        Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
            .notice("refresh entry cycle=\(cycle, privacy: .public)")
        guard SharedWidgetStore.isWidgetRefreshSession(session) else {
            result.opensIntent = nil
            return result
        }
#if !CARAOKE_WIDGET_EXTENSION
        let active = await MainActor.run {
            guard SharedWidgetStore.isWidgetRefreshSession(session) else { return false }
            AppModel.shared.startRideSession()
            AppModel.shared.ride.ensureActivity()
            AppModel.shared.ride.refreshWidgetSnapshot()
            return true
        }
        guard active else {
            result.opensIntent = nil
            return result
        }
#endif
        SharedWidgetStore.noteWidgetRefreshCycle(session)
        let delay = WidgetRefreshSession.nextRefreshDelay(payload: SharedWidgetStore.read(), now: Date())
        Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
            .notice("refresh intent cycle=\(cycle, privacy: .public) nextIn=\(delay, privacy: .public)")
        SharedWidgetStore.requestReload(reason: "intent-cycle")
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch is CancellationError {
            result.opensIntent = nil
            return result
        }
        if !SharedWidgetStore.isWidgetRefreshSession(session) { result.opensIntent = nil }
        return result
    }
}
#endif
