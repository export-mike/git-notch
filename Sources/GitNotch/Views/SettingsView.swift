import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var controller: NotchController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Right badge — my PRs need attention when…") {
                ForEach(PRSignal.allCases, id: \.self) { signal in
                    Toggle(signal.label, isOn: Binding(
                        get: { state.settings.isEnabled(signal) },
                        set: { state.settings.setEnabled(signal, $0) }
                    ))
                }
            }

            Section("Filters") {
                Toggle("Only direct review requests", isOn: Binding(
                    get: { state.settings.directReviewRequestsOnly },
                    set: { state.settings.directReviewRequestsOnly = $0
                           controller.refreshNow(reason: "review-filter-changed") }
                ))
                Text("Hide PRs requested via a team you're on — show only when you're added individually.")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Organization", text: Binding(
                    get: { state.settings.org },
                    set: { state.settings.org = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Limit all PRs to this org (e.g. my-org). Leave blank for all.")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Commenter (optional)", text: Binding(
                    get: { state.settings.commenter },
                    set: { state.settings.commenter = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Only count my PRs where this user/team has commented.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Refresh every", selection: Binding(
                    get: { state.settings.refreshInterval },
                    set: { state.settings.refreshInterval = $0; controller.settingsChanged() }
                )) {
                    Text("30 sec").tag(TimeInterval(30))
                    Text("1 min").tag(TimeInterval(60))
                    Text("90 sec").tag(TimeInterval(90))
                    Text("5 min").tag(TimeInterval(300))
                }
                Picker("Snooze for", selection: Binding(
                    get: { state.settings.snoozeDuration },
                    set: { state.settings.snoozeDuration = $0 }
                )) {
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("2 hours").tag(TimeInterval(7200))
                    Text("4 hours").tag(TimeInterval(14400))
                    Text("1 day").tag(TimeInterval(86400))
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 500)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Revert the toggle if the system rejected the change.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
