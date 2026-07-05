import SwiftUI

/// The always-on bar: two icon clusters hugging either side of the notch,
/// with the physical notch left transparent in the middle.
struct NotchBarView: View {
    let layout: NotchLayout
    @EnvironmentObject var state: AppState
    @EnvironmentObject var controller: NotchController

    var body: some View {
        HStack(spacing: 0) {
            ClusterView(side: .left, redCount: state.reviewRequested.count,
                        urgent: state.hasUrgentReview, hasNotch: layout.hasNotch)
                .frame(width: layout.clusterWidth)
                .offset(x: layout.hasNotch ? 2 : 0)   // nudge inward toward the notch
            Color.clear.frame(width: layout.notchWidth) // the notch (or a small gap)
            ClusterView(side: .right, redCount: state.openAttentionCount,
                        greenCount: state.openReadyCount, blueCount: state.openAwaitingCount,
                        hasNotch: layout.hasNotch,
                        browsable: !state.openPRs.isEmpty || !state.myAttentionDrafts.isEmpty,
                        errored: state.lastError != nil)
                .frame(width: layout.clusterWidth)
                .offset(x: layout.hasNotch ? -2 : 0)  // nudge inward toward the notch
        }
        .frame(width: layout.windowWidth, height: layout.barHeight)
    }
}

private struct ClusterView: View {
    let side: Side
    let redCount: Int            // needs-attention / reviews-awaiting
    var greenCount: Int = 0      // ready-to-merge (right side only)
    var blueCount: Int = 0       // open awaiting review (right side only)
    var urgent: Bool = false
    var hasNotch: Bool = true    // false → free-standing rounded pill
    var browsable: Bool = false  // right side: stay visible to browse PRs even with no red/green
    var errored: Bool = false    // fetch failed → stay visible so the error is reachable
    @EnvironmentObject var controller: NotchController

    /// hidden = nothing to show; active = counts showing; cleared = ✓ celebration.
    private enum Phase { case hidden, active, cleared }
    @State private var phase: Phase = .hidden
    @State private var pulseTrigger = 0
    @State private var retractWork: DispatchWorkItem?

    private var total: Int { redCount + greenCount }
    /// Visible with a count, PRs to browse, or an error to surface.
    private var present: Bool { total > 0 || browsable || errored }
    private var isViolent: Bool { urgent && phase == .active && redCount > 0 }
    /// Error with nothing else to show → warn instead of hiding.
    private var showError: Bool { errored && total == 0 && !browsable }
    private var ringColor: Color {
        if phase == .cleared { return .notchGreen }
        if redCount > 0 { return .notchRed }
        if greenCount > 0 { return .notchGreen }
        if blueCount > 0 { return .notchBlue }   // open, awaiting review
        if showError { return .orange }          // fetch failed, no data
        return Color.white.opacity(0.55)         // drafts only — nothing else to show
    }
    /// Inner edge (toward the notch) that content slides in from.
    private var innerEdge: Edge { side == .left ? .trailing : .leading }
    private var outerX: CGFloat { side == .left ? -13 : 13 }

    var body: some View {
        ZStack {
            if phase != .hidden {
                content
                    .transition(.asymmetric(
                        insertion: .move(edge: innerEdge).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { controller.toggleDropdown(side) }
        .help(side == .left ? "PRs awaiting your review" : "Your PRs (needs attention / ready to merge)")
        .onAppear { phase = present ? .active : .hidden }
        .onChange(of: present) { _, now in setPresent(now) }
        .onChange(of: total) { old, new in if new > old, phase == .active { pulseTrigger += 1 } }
    }

    private var content: some View {
        ZStack {
            NotchTabShape(side: side, radius: 11, standalone: !hasNotch)
                .fill(Color.black)
                // With a real notch, extend the inner edge under it so the tab
                // merges seamlessly. Free-standing pills need no tuck.
                .padding(Edge.Set(innerEdge), hasNotch ? -6 : 0)
            ZStack {
                if isViolent { RepeatingPulse(color: .notchRed) }   // urgent: relentless pulse
                PulseRing(color: ringColor, trigger: pulseTrigger)
                Circle().strokeBorder(ringColor, lineWidth: isViolent ? 2.5 : 2).frame(width: 25, height: 25)
                GitHubMark(color: isViolent ? .notchRed : .white)   // urgent: the mark itself goes red
            }
            badges
        }
    }

    @ViewBuilder private var badges: some View {
        if phase == .cleared {
            checkBadge.offset(x: outerX, y: -8)
        } else {
            // Red on top; green below it when both are present (green alone rides on top).
            if redCount > 0 {
                countBadge(redCount, color: .notchRed).offset(x: outerX, y: -8)
            }
            if greenCount > 0 {
                countBadge(greenCount, color: .notchGreen)
                    .offset(x: outerX, y: redCount > 0 ? 8 : -8)
            }
            // Nothing actionable: show the awaiting-review count in blue.
            if redCount == 0 && greenCount == 0 && blueCount > 0 {
                countBadge(blueCount, color: .notchBlue).offset(x: outerX, y: -8)
            }
            // Fetch failed with no data: warn so it's obvious something's wrong.
            if showError {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.orange).overlay(Circle().strokeBorder(.black, lineWidth: 1.5)))
                    .offset(x: outerX, y: -8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func countBadge(_ n: Int, color: Color) -> some View {
        Text(n > 99 ? "99+" : "\(n)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .padding(.horizontal, 3)
            .frame(minWidth: 14, minHeight: 14)
            .background(Circle().fill(color).overlay(Circle().strokeBorder(.black, lineWidth: 1.5)))
            .transition(.scale.combined(with: .opacity))
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.notchGreen).overlay(Circle().strokeBorder(.black, lineWidth: 1.5)))
            .transition(.scale.combined(with: .opacity))
    }

    /// Show/hide the cluster as its presence toggles.
    private func setPresent(_ now: Bool) {
        retractWork?.cancel(); retractWork = nil
        if now {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { phase = .active }
            pulseTrigger += 1
        } else {
            // Everything cleared: celebrate green, then retract to nothing.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phase = .cleared }
            pulseTrigger += 1
            let work = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.5)) { phase = .hidden }
            }
            retractWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
        }
    }
}

/// A ring that continuously expands and fades — used for urgent PRs, where the
/// relentless motion is the point.
private struct RepeatingPulse: View {
    let color: Color
    @State private var animate = false
    var body: some View {
        Circle().stroke(color, lineWidth: 2)
            .frame(width: 26, height: 26)
            .scaleEffect(animate ? 2.0 : 1.0)
            .opacity(animate ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

/// A ring that expands and fades once each time `trigger` increments — a
/// one-shot pulse, so there's no distracting perpetual motion in the notch.
private struct PulseRing: View {
    let color: Color
    let trigger: Int
    @State private var t: CGFloat = 1   // 1 = fully faded/invisible at rest

    var body: some View {
        Circle().stroke(color, lineWidth: 2)
            .frame(width: 26, height: 26)
            .scaleEffect(1 + t * 0.9)
            .opacity(0.7 * (1 - Double(t)))
            .onChange(of: trigger) { _, _ in
                t = 0
                withAnimation(.easeOut(duration: 0.9)) { t = 1 }
            }
    }
}

/// A tab that extends the notch. Top edge flush with the screen top; the inner
/// edge (toward the notch) is square so the tab merges seamlessly; only the
/// OUTER bottom corner is rounded — like a corner of the notch itself.
struct NotchTabShape: Shape {
    let side: Side
    var radius: CGFloat
    /// Standalone (no real notch) → round BOTH bottom corners into a pill.
    var standalone: Bool = false

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height, rect.width / 2)
        // Which bottom corners to round: only the outer one next to a real notch,
        // or both when free-standing.
        let roundLeft = standalone || side == .left
        let roundRight = standalone || side == .right
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))      // top-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))   // top-right
        if roundRight {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        } else {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        if roundLeft {
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        } else {
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
