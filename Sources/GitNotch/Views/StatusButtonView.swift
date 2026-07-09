import SwiftUI

/// Content of the menu-bar status item shown on notch-less Macs: the GitHub
/// mark flanked by the two counts (review-requested on the left, your PRs
/// needing attention on the right) — the tray echo of the notch's two icon
/// clusters.
struct StatusButtonView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 3) {
            countBadge(state.reviewRequested.count)
            GitHubMark(color: Color(nsColor: .labelColor), size: 15)
            countBadge(state.openAttentionCount)
        }
        .padding(.horizontal, 6)
        .frame(height: NSStatusBar.system.thickness)
        .fixedSize()
    }

    /// Red capsule with a white count — hidden entirely when the queue is empty,
    /// so a clear side collapses to just the mark. Mirrors `NotchBarView`'s badge.
    @ViewBuilder private func countBadge(_ n: Int) -> some View {
        if n > 0 {
            Text(n > 99 ? "99+" : "\(n)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .frame(minWidth: 14, minHeight: 14)
                .background(Capsule().fill(Color.notchRed))
        }
    }
}
