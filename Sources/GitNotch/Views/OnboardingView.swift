import SwiftUI

/// First-run prompt: captures which GitHub organization to scope PRs to.
/// Nothing is hard-coded — a fresh install starts with no org until the user
/// chooses one here (blank means "all orgs").
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    var onDone: () -> Void

    @State private var org: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                GitHubMark(color: .primary, size: 22)
                Text("Welcome to Git Notch").font(.title2.weight(.semibold))
            }
            Text("Which GitHub organization should Git Notch watch? Only pull "
                 + "requests from this org will be surfaced. Leave it blank to "
                 + "include PRs from everywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Organization (e.g. my-org)", text: $org)
                .textFieldStyle(.roundedBorder)
                .onSubmit(finish)

            Text("You can change this anytime in Settings.")
                .font(.caption).foregroundStyle(.tertiary)

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Continue", action: finish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380, height: 250)
        .onAppear { org = state.settings.org }
    }

    private func finish() {
        state.settings.org = org.trimmingCharacters(in: .whitespacesAndNewlines)
        onDone()
    }
}
