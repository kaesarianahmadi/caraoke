import Foundation
import MetricKit

/// Native crash & diagnostic reporter for autonomous agent debugging.
///
/// Combines two layers:
/// 1. NSUncaughtExceptionHandler: catches runtime exceptions, persists stack trace
///    to UserDefaults, and uploads on the subsequent app launch.
/// 2. MetricKit: receives OS-level termination, watchdog, and crash diagnostics
///    directly from iOS and forward them to the lyric relay.
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

        installExceptionHandler()
        MXMetricManager.shared.add(self)
        flushPendingCrashReport()
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
