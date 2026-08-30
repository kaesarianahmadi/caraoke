import Foundation

/// Single place the app and its App Intents share state, so a
/// `LiveActivityIntent` can start/stop a ride from a background context.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let ride = RideModeViewModel()

    private init() {}

    func startRideSession() {
        ride.startRide()
    }

    func stopRideSession() {
        ride.stopRide()
    }
}
