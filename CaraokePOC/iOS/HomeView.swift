import SwiftUI

/// Home screen: one master switch (Ride Mode), a live preview of the current
/// and next lyric lines, and status text. Everything happens on device.
struct HomeView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var showSettings = false
    @State private var showPaywall = false
    @StateObject private var purchases = PurchaseManager()

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Image(systemName: "car.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Caraoke — Live Lyrics")
                    .font(.title2.weight(.semibold))
                Text("Road Trip Lyrics")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Master control
            Toggle(isOn: Binding(
                get: { model.isOn },
                set: { _ in model.toggle() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ride Mode")
                        .font(.headline)
                    Text(model.isOn ? "Lyrics are live." : "Lyrics to CarPlay when music plays.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // Live preview (also shown on Lock Screen / CarPlay)
            VStack(alignment: .leading, spacing: 8) {
                Text("Now playing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.currentLine.isEmpty ? "—" : model.currentLine)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                if let next = model.nextLine, !next.isEmpty {
                    Text(next)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // Live Activity diagnostic — makes a no-show observable on device
            // instead of a silent failure (cost us a test round-trip on
            // build 4).
            if !model.activityStatus.isEmpty {
                Text(model.activityStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.horizontal)
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model, presentingPaywall: $showPaywall)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(purchases: purchases, onDismiss: { showPaywall = false })
                .presentationDetents([.medium, .large])
        }
    }
}
