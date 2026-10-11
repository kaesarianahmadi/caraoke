import Foundation
import MetricKit
#if canImport(Sentry)
import Sentry
#endif

/// Native crash & diagnostic reporter for autonomous agent debugging.
///
/// Combines three layers:
/// 1. Sentry SDK: real-time crash capture, Mach exception handling, and symbolicated stack traces.
/// 2. NSUncaughtExceptionHandler: fallback runtime exception persistence.
/// 3. MetricKit: receives OS-level termination, watchdog, and crash diagnostics.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    private let userDefaultsKey = "app.caraoke.pending_crash"
    private var isStarted = false

    private override init() {
        super.init()
    }

    /// Initializes exception handlers and subscribes to MetricKit diagnostics.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        #if canImport(Sentry)
        if let dsn = SecretsLoader.sentryDSN {
            SentrySDK.start { options in
                options.dsn = dsn
                options.enableAutoSessionTracking = true
                options.enableWatchdogTerminationTracking = true
                #if DEBUG
                options.debug = true
                #endif
            }
        }
        #endif

        installExceptionHandler()
        MXMetricManager.shared.add(self)
        flushPendingCrashReport()
    }

    /// Captures a non-fatal error to Sentry.
    static func recordError(_ error: Error) {
        #if canImport(Sentry)
        SentrySDK.capture(error: error)
        #endif
    }

    // MARK: - Uncaught Exception Handling

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let crashData: [String: Any] = [
                "type": "UncaughtException",
                "name": exception.name.rawValue,
                "reason": exception.reason ?? "Unknown",
                "callStack": exception.callStackSymbols,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]

            if let data = try? JSONSerialization.data(withJSONObject: crashData) {
                UserDefaults.standard.set(data, forKey: "app.caraoke.pending_crash")
                UserDefaults.standard.synchronize()
            }
        }
    }

    private func flushPendingCrashReport() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        upload(data: data)
    }

    // MARK: - MetricKit Subscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let crashes = payload.crashDiagnostics, !crashes.isEmpty else { continue }
            for crash in crashes {
                let json = crash.jsonRepresentation()
                upload(data: json)
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Routine metrics omitted to preserve relay bandwidth
    }

    // MARK: - Upload

    private func upload(data: Data) {
        guard let baseURL = FeatureFlags.relayBaseURL else { return }
        let url = baseURL.appendingPathComponent("crashes")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                #if DEBUG
                print("[CrashReporter] Crash report delivered to relay")
                #endif
            } else if let error = error {
                #if DEBUG
                print("[CrashReporter] Failed to send crash report: \(error.localizedDescription)")
                #endif
            }
        }.resume()
    }
}
