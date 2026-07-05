import Foundation

/// A pull request, cleaned up from the GraphQL response into something the UI
/// can render directly.
struct PullRequest: Identifiable, Hashable {
    let id: String            // the PR url — stable & unique
    let title: String
    let url: URL
    let number: Int
    let repo: String          // owner/name
    let author: String
    let updatedAt: Date
    let isDraft: Bool

    // Fields relevant when the PR is one of *mine*.
    let reviewDecision: String?     // APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED / nil
    let reviewCount: Int
    let checkState: String?         // SUCCESS / FAILURE / ERROR / PENDING / nil
    let unresolvedCount: Int
    /// Distinct current approvals (latest review per author that is APPROVED).
    let approvalCount: Int

    /// Which attention signals this PR currently trips.
    var signals: Set<PRSignal> {
        var s: Set<PRSignal> = []
        if reviewDecision == "CHANGES_REQUESTED" { s.insert(.changesRequested) }
        if reviewCount > 0 { s.insert(.reviewFeedback) }
        if let c = checkState, c == "FAILURE" || c == "ERROR" { s.insert(.failingChecks) }
        if unresolvedCount > 0 { s.insert(.unresolvedComments) }
        return s
    }

    /// A short human summary of "what is going on" for the list row.
    func summary(for side: Side) -> String {
        switch side {
        case .left:
            let approvals = approvalCount == 0
                ? "No approvals yet"
                : "\(approvalCount) approval\(approvalCount == 1 ? "" : "s")"
            return "\(approvals) · \(relativeUpdated)"
        case .right:
            var parts: [String] = []
            if reviewDecision == "CHANGES_REQUESTED" { parts.append("Changes requested") }
            if let c = checkState, c == "FAILURE" || c == "ERROR" { parts.append("CI failing") }
            if unresolvedCount > 0 {
                parts.append("\(unresolvedCount) unresolved comment\(unresolvedCount == 1 ? "" : "s")")
            }
            if parts.isEmpty, reviewCount > 0 { parts.append("Review feedback") }
            if parts.isEmpty { parts.append("Needs attention") }
            return parts.joined(separator: " · ") + " · \(relativeUpdated)"
        }
    }

    /// The dominant status colour for the row's leading dot.
    var accent: StatusAccent {
        if let c = checkState, c == "FAILURE" || c == "ERROR" { return .red }
        if reviewDecision == "CHANGES_REQUESTED" { return .red }
        if unresolvedCount > 0 { return .orange }
        if reviewCount > 0 { return .yellow }
        return .neutral
    }

    var relativeUpdated: String { RelativeTime.string(from: updatedAt) }
}

enum StatusAccent { case red, orange, yellow, neutral }

enum Side { case left, right }

enum RelativeTime {
    private static let fmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    static func string(from date: Date, now: Date = Date()) -> String {
        fmt.localizedString(for: date, relativeTo: now)
    }
}
