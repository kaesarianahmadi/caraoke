#if os(iOS)
import AppIntents
import os

/// Return the next intent to the system; never call `perform()` from an app timer.
/// The five-second wait bounds reload requests and leaves cancellation observable.
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
        guard SharedWidgetStore.isWidgetRefreshSession(session) else { throw CancellationError() }
#if !CARAOKE_WIDGET_EXTENSION
        try await MainActor.run {
            guard SharedWidgetStore.isWidgetRefreshSession(session) else { throw CancellationError() }
            AppModel.shared.startRideSession()
            AppModel.shared.ride.ensureActivity()
        }
#endif
        Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
            .notice("refresh intent cycle=\(cycle, privacy: .public)")
        SharedWidgetStore.requestReload(reason: "intent-cycle")
        try await Task.sleep(for: .seconds(5))
        guard SharedWidgetStore.isWidgetRefreshSession(session) else { throw CancellationError() }
        return .result(opensIntent: WidgetRefreshIntent(session: session, cycle: cycle &+ 1))
    }
}
#endif
