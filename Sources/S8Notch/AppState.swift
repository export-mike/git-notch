import SwiftUI

/// The single source of truth the UI observes.
@MainActor
final class AppState: ObservableObject {
    /// A PR only counts as "awaiting your review" until it has this many
    /// approvals — once it does, it no longer needs your attention.
    static let approvalThreshold = 2

    let settings = Settings()
    let snoozes = SnoozeStore()

    /// PRs awaiting my review with fewer than `approvalThreshold` approvals (left badge).
    @Published private(set) var reviewRequested: [PullRequest] = []
    /// My open (non-draft) PRs that trip an enabled attention signal (right badge + default view).
    @Published private(set) var myAttention: [PullRequest] = []
    /// My *draft* PRs that trip an enabled attention signal (Draft tab).
    @Published private(set) var myAttentionDrafts: [PullRequest] = []

    @Published private(set) var viewerLogin: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    /// Raw, unfiltered copies kept so we can re-filter instantly when a setting
    /// changes (no network round-trip).
    private var rawReviewRequested: [PullRequest] = []
    private var rawMine: [PullRequest] = []

    init() {
        settings.onChange = { [weak self] in self?.reclassify() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await GitHubClient.token()
            let result = try await GitHubClient.fetch(
                token: token, org: settings.org, commenter: settings.commenter)
            viewerLogin = result.viewerLogin
            rawReviewRequested = result.reviewRequested
            rawMine = result.mine
            reclassify()
            lastError = nil
            lastUpdated = Date()
            NSLog("[s8notch] refresh ok: %@ — review-requested=%d, my-attention=%d (+%d draft) of %d mine",
                  viewerLogin, reviewRequested.count, myAttention.count, myAttentionDrafts.count, rawMine.count)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[s8notch] refresh failed: %@", lastError ?? "unknown")
        }
    }

    /// Recompute the derived lists from cached data + current settings.
    func reclassify() {
        snoozes.prune()
        reviewRequested = rawReviewRequested
            .filter { $0.approvalCount < Self.approvalThreshold }
            .filter { !$0.author.lowercased().contains("dependabot") } // backstop
            .filter { !snoozes.isSnoozed($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let enabled = settings.enabledSignals
        let live = rawMine.filter { !snoozes.isSnoozed($0.id) }
        // Open (non-draft) PRs must trip an enabled attention signal.
        myAttention = live
            .filter { !$0.isDraft && !$0.signals.isDisjoint(with: enabled) }
            .sorted { $0.updatedAt > $1.updatedAt }
        // The Draft tab lists ALL your open drafts, regardless of signals.
        myAttentionDrafts = live
            .filter { $0.isDraft }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Snooze a PR for the configured duration, then refresh the visible lists.
    func snooze(_ pr: PullRequest) {
        snoozes.snooze(pr.id, for: settings.snoozeDuration)
        reclassify()
    }

    func clearSnoozes() {
        snoozes.clearAll()
        reclassify()
    }

    var snoozedCount: Int { snoozes.activeCount }
}
