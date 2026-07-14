import SwiftUI

/// The single source of truth the UI observes.
@MainActor
final class AppState: ObservableObject {
    /// A PR only counts as "awaiting your review" until it has this many
    /// approvals — once it does, it no longer needs your attention.
    static let approvalThreshold = 2

    let settings = Settings()
    let snoozes = SnoozeStore()
    private let sound = SoundPlayer()

    /// True when any review awaiting you carries an `urgent` label.
    var hasUrgentReview: Bool { reviewRequested.contains(where: \.isUrgent) }
    /// Urgent PR ids we've already sounded the alarm for, to avoid replaying.
    private var alertedUrgentIDs: Set<String> = []

    /// PRs awaiting my review with fewer than `approvalThreshold` approvals (left badge).
    @Published private(set) var reviewRequested: [PullRequest] = []
    /// ALL my open (non-draft) PRs — the Open tab list.
    @Published private(set) var openPRs: [PullRequest] = []
    /// ALL my open drafts — the Draft tab list.
    @Published private(set) var myAttentionDrafts: [PullRequest] = []

    /// Red badge: open PRs needing attention (excluding ones ready to merge).
    var openAttentionCount: Int {
        openPRs.filter { !$0.isReadyToMerge && !$0.signals.isDisjoint(with: settings.enabledSignals) }.count
    }
    /// Green badge: open PRs ready to merge.
    var openReadyCount: Int { openPRs.filter(\.isReadyToMerge).count }
    /// Blue badge: open PRs just awaiting review — not ready, nothing needs attention.
    var openAwaitingCount: Int { max(0, openPRs.count - openAttentionCount - openReadyCount) }

    @Published private(set) var viewerLogin: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    /// Raw, unfiltered copies kept so we can re-filter instantly when a setting
    /// changes (no network round-trip).
    private var rawReviewRequested: [PullRequest] = []
    private var rawMine: [PullRequest] = []

    /// Session-scoped cache of each repo's available labels, keyed by "owner/name".
    private var labelCache: [String: [PRLabel]] = [:]

    // GraphQL budget tracking (5,000 points/hour). We stop polling when the
    // remaining budget dips below this floor and resume after the window resets.
    private static let rateFloor = 150
    private var rateRemaining = 5000
    private var rateResetAt: Date?

    init() {
        settings.onChange = { [weak self] in self?.reclassify() }
    }

    func refresh() async {
        // Budget guard: don't poll when the GraphQL point budget is nearly spent;
        // wait for the hourly window to reset. Prevents fully exhausting the limit.
        if rateRemaining < Self.rateFloor, let reset = rateResetAt, reset > Date() {
            let secs = Int(reset.timeIntervalSinceNow)
            NSLog("[gitnotch] skipping refresh — GraphQL budget low (%d left, resets in %ds)", rateRemaining, secs)
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await GitHubClient.token()
            let result = try await GitHubClient.fetch(
                token: token, org: settings.org, commenter: settings.commenter)
            viewerLogin = result.viewerLogin
            rawReviewRequested = result.reviewRequested
            rawMine = result.mine
            rateRemaining = result.rateRemaining
            rateResetAt = result.rateResetAt
            reclassify()
            lastError = nil
            lastUpdated = Date()
            NSLog("[gitnotch] refresh ok: %@ — review=%d open=%d (red=%d green=%d) drafts=%d | cost=%d remaining=%d/hr",
                  viewerLogin, reviewRequested.count, openPRs.count, openAttentionCount, openReadyCount,
                  myAttentionDrafts.count, result.rateCost, result.rateRemaining)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[gitnotch] refresh failed: %@", lastError ?? "unknown")
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

        let live = rawMine.filter { !snoozes.isSnoozed($0.id) }
        // Open tab lists ALL open non-draft PRs; badges (red/green) are derived counts.
        openPRs = live
            .filter { !$0.isDraft }
            .sorted { $0.updatedAt > $1.updatedAt }
        // The Draft tab lists ALL your open drafts, regardless of signals.
        myAttentionDrafts = live
            .filter { $0.isDraft }
            .sorted { $0.updatedAt > $1.updatedAt }

        alertOnNewUrgent()
    }

    /// Sound the alarm the first time each urgent review shows up.
    private func alertOnNewUrgent() {
        let current = Set(reviewRequested.filter(\.isUrgent).map(\.id))
        let fresh = current.subtracting(alertedUrgentIDs)
        if !fresh.isEmpty {
            sound.play(resource: "Task_Resolved", ext: "mp3")
            NSLog("[gitnotch] urgent PR(s) — playing alert: %@", fresh.joined(separator: ", "))
        }
        alertedUrgentIDs = current   // forget ones no longer urgent so they can re-alert later
    }

    /// Snooze a PR for the configured duration, then refresh the visible lists.
    func snooze(_ pr: PullRequest) {
        snoozes.snooze(pr.id, for: settings.snoozeDuration)
        reclassify()
    }

    /// The labels defined on a repo, cached for the session.
    func repoLabels(for repo: String) async throws -> [PRLabel] {
        if let cached = labelCache[repo] { return cached }
        let token = try await GitHubClient.token()
        let labels = try await GitHubClient.repoLabels(token: token, repo: repo)
        labelCache[repo] = labels
        return labels
    }

    /// Add/remove labels on a PR via the API, then optimistically update the row.
    func updateLabels(add: [String], remove: [String], on pr: PullRequest) async {
        do {
            let token = try await GitHubClient.token()
            if !add.isEmpty {
                try await GitHubClient.addLabels(token: token, repo: pr.repo, number: pr.number, labels: add)
            }
            for name in remove {
                try await GitHubClient.removeLabel(token: token, repo: pr.repo, number: pr.number, label: name)
            }
            let available = labelCache[pr.repo] ?? []
            let added = add.map { name in
                available.first { $0.name == name } ?? PRLabel(name: name, color: "")
            }
            applyLabels(added, removing: Set(remove), toPRWithID: pr.id)
            reclassify()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[gitnotch] update labels failed: %@", lastError ?? "unknown")
        }
    }

    /// Merge added labels into the matching raw PR (skipping duplicates) and drop removed ones.
    private func applyLabels(_ labels: [PRLabel], removing removed: Set<String>, toPRWithID id: String) {
        func merge(_ pr: PullRequest) -> PullRequest {
            var updated = pr
            let existing = Set(pr.labels.map(\.name))
            updated.labels += labels.filter { !existing.contains($0.name) }
            updated.labels.removeAll { removed.contains($0.name) }
            return updated
        }
        if let i = rawReviewRequested.firstIndex(where: { $0.id == id }) {
            rawReviewRequested[i] = merge(rawReviewRequested[i])
        }
        if let i = rawMine.firstIndex(where: { $0.id == id }) {
            rawMine[i] = merge(rawMine[i])
        }
    }

    func clearSnoozes() {
        snoozes.clearAll()
        reclassify()
    }

    var snoozedCount: Int { snoozes.activeCount }
}
