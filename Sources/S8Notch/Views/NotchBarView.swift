import SwiftUI

/// The always-on bar: two icon clusters hugging either side of the notch,
/// with the physical notch left transparent in the middle.
struct NotchBarView: View {
    let layout: NotchLayout
    @EnvironmentObject var state: AppState
    @EnvironmentObject var controller: NotchController

    var body: some View {
        HStack(spacing: 0) {
            ClusterView(side: .left, count: state.reviewRequested.count)
                .frame(width: layout.clusterWidth)
                .offset(x: 2)   // nudge inward toward the notch
            Color.clear.frame(width: layout.notchWidth) // the notch itself
            ClusterView(side: .right, count: state.myAttention.count)
                .frame(width: layout.clusterWidth)
                .offset(x: -2)  // nudge inward toward the notch
        }
        .frame(width: layout.windowWidth, height: layout.barHeight)
    }
}

private struct ClusterView: View {
    let side: Side
    let count: Int
    @EnvironmentObject var controller: NotchController

    /// hidden = nothing to show; active = red count; cleared = green tick (transient celebration).
    private enum Phase { case hidden, active, cleared }
    @State private var phase: Phase = .hidden
    @State private var pulseTrigger = 0
    @State private var retractWork: DispatchWorkItem?

    private var isGreen: Bool { phase == .cleared }
    private var accent: Color { isGreen ? .notchGreen : .notchRed }
    /// Inner edge (toward the notch) that content slides in from.
    private var innerEdge: Edge { side == .left ? .trailing : .leading }

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
        .help(side == .left ? "PRs awaiting your review" : "Your PRs needing attention")
        .onAppear { phase = count > 0 ? .active : .hidden }
        .onChange(of: count) { old, new in react(old: old, new: new) }
    }

    private var content: some View {
        ZStack {
            NotchTabShape(side: side, radius: 11)
                .fill(Color.black)
                // Extend the inner edge under the notch so the tab merges with
                // it seamlessly (no seam, no gap).
                .padding(Edge.Set(innerEdge), -6)
            ZStack {
                PulseRing(color: accent, trigger: pulseTrigger)
                Circle().strokeBorder(accent, lineWidth: 2).frame(width: 25, height: 25)
                GitHubMark(color: .white)
            }
            badge.offset(x: side == .left ? -13 : 13, y: -8)
        }
    }

    @ViewBuilder private var badge: some View {
        if isGreen {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.notchGreen)
                    .overlay(Circle().strokeBorder(.black, lineWidth: 1.5)))
                .transition(.scale.combined(with: .opacity))
        } else {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.horizontal, 3)
                .frame(minWidth: 14, minHeight: 14)
                .background(Circle().fill(Color.notchRed)
                    .overlay(Circle().strokeBorder(.black, lineWidth: 1.5)))
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// State machine reacting to count changes.
    private func react(old: Int, new: Int) {
        retractWork?.cancel(); retractWork = nil
        if new > 0 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { phase = .active }
            if new > old { pulseTrigger += 1 }              // new work landed → pulse
        } else if old > 0 {
            // Queue just hit zero: celebrate green, then retract to nothing.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phase = .cleared }
            pulseTrigger += 1
            let work = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.5)) { phase = .hidden }
            }
            retractWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
        } else {
            phase = .hidden                                  // was already empty
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
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height, rect.width)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))      // top-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))   // top-right
        if side == .right {
            // Outer edge is the right → round bottom-right, square bottom-left.
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            // Outer edge is the left → round bottom-left, square bottom-right.
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        p.closeSubpath()
        return p
    }
}
