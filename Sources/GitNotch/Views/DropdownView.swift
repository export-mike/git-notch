import SwiftUI

enum DraftFilter: String, CaseIterable { case open = "Open", draft = "Draft" }

struct DropdownView: View {
    /// When `showsSideSwitcher` is true this becomes user-switchable (tray mode);
    /// otherwise it's fixed to the value passed in (notch clusters).
    @State private var side: Side
    let showsSideSwitcher: Bool
    let maxHeight: CGFloat
    @EnvironmentObject var state: AppState
    @EnvironmentObject var controller: NotchController
    @State private var draftFilter: DraftFilter = .open

    init(side: Side, maxHeight: CGFloat, showsSideSwitcher: Bool = false) {
        _side = State(initialValue: side)
        self.maxHeight = maxHeight
        self.showsSideSwitcher = showsSideSwitcher
    }

    private var items: [PullRequest] {
        switch side {
        case .left:  return state.reviewRequested
        case .right: return draftFilter == .open ? state.openPRs : state.myAttentionDrafts
        }
    }
    private var title: String {
        side == .left ? "Awaiting your review" : "Your PRs"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSideSwitcher {
                sideSwitcher
            }
            header
            if side == .left && state.isUrgentSoundPlaying {
                silenceBanner
            }
            if side == .right {
                filterBar
            }
            Divider().overlay(Color.white.opacity(0.08))
            content
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 400)
        .frame(maxHeight: maxHeight)
        .background(.black.opacity(0.92))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
        // The popover is dark-styled by hand; force the dark appearance so
        // system controls (segmented pickers) draw their labels light-on-dark
        // instead of near-black-on-dark (invisible).
        .environment(\.colorScheme, .dark)
    }

    private var sideSwitcher: some View {
        Picker("", selection: $side) {
            Text("Review (\(state.reviewRequested.count))").tag(Side.left)
            Text("Yours (\(state.openPRs.count))").tag(Side.right)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            GitHubMark(color: .white, size: 15)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Text("\(items.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(items.isEmpty ? Color.white.opacity(0.15) : Color.red))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    /// One-tap silence for the urgent alarm — shown on the incoming side only
    /// while the sound is actually playing.
    private var silenceBanner: some View {
        Button { state.silenceUrgentAlarm() } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash.fill")
                Text("Silence urgent alert").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.notchRed.opacity(0.9)))
        }
        .buttonStyle(.plain)
        .help("Stop the urgent alert sound")
        .padding(.horizontal, 14).padding(.bottom, 9)
    }

    private var filterBar: some View {
        Picker("", selection: $draftFilter) {
            Text("Open (\(state.openPRs.count))").tag(DraftFilter.open)
            Text("Draft (\(state.myAttentionDrafts.count))").tag(DraftFilter.draft)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var content: some View {
        if let err = state.lastError, items.isEmpty {
            message(err, systemImage: "exclamationmark.triangle", tint: .orange)
        } else if items.isEmpty {
            message(state.isLoading ? "Loading…" : "All clear — nothing needs you here.",
                    systemImage: state.isLoading ? "ellipsis" : "checkmark.circle", tint: .green)
        } else {
            List {
                ForEach(items) { pr in
                    PRRow(pr: pr, side: side, snoozeHelp: snoozeHelp,
                          onOpen: { controller.open(pr) },
                          onSnooze: { state.snooze(pr) })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparatorTint(.white.opacity(0.08))
                        // Swipe left (full swipe) to snooze.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { state.snooze(pr) } label: {
                                Label("Snooze", systemImage: "moon.zzz.fill")
                            }
                            .tint(.indigo)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
        }
    }

    private func message(_ text: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 22)).foregroundStyle(tint)
            Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        // Fill the content region and centre, so the footer stays pinned to the
        // bottom instead of leaving a void when the popover is taller than the
        // message (e.g. the all-clear side of a populated tray popover).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 34).padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if state.isLoading {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Button { controller.refreshNow() } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain)
            }
            Text(updatedText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            Spacer()
            if state.snoozedCount > 0 {
                Button { state.clearSnoozes() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "moon.zzz.fill")
                        Text("\(state.snoozedCount)").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .help("\(state.snoozedCount) snoozed — click to un-snooze all")
            }
            Button { controller.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
            Button { controller.quit() } label: { Image(systemName: "power") }
                .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var updatedText: String {
        guard let u = state.lastUpdated else { return "" }
        return "Updated \(RelativeTime.string(from: u))"
    }

    private var snoozeHelp: String {
        "Snooze for \(DurationLabel.short(state.settings.snoozeDuration))"
    }
}

/// Human-readable short label for a duration in seconds ("2h", "30m", "1d").
enum DurationLabel {
    static func short(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s % 86400 == 0 { return "\(s / 86400)d" }
        if s % 3600 == 0 { return "\(s / 3600)h" }
        return "\(s / 60)m"
    }
}

private struct PRRow: View {
    let pr: PullRequest
    let side: Side
    let snoozeHelp: String
    let onOpen: () -> Void
    let onSnooze: () -> Void
    @EnvironmentObject var state: AppState
    @State private var hovering = false
    @State private var showLabelPicker = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(dotColor).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(pr.repo) #\(pr.number)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                Text(pr.summary(for: side))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if !pr.labels.isEmpty { labelChips }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(hovering ? 0.7 : 0.25))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(hovering ? Color.white.opacity(0.06) : .clear)
        // The hover toolbar sits in the bottom-right corner as an overlay so it
        // never participates in the row's layout — showing it on hover can't
        // reflow the title/subtitle text. Kept visible while the label picker is
        // open so the popover's anchor doesn't vanish on hover-out.
        .overlay(alignment: .bottomTrailing) {
            if hovering || showLabelPicker {
                HStack(spacing: 12) {
                    Button { showLabelPicker = true } label: {
                        Image(systemName: "tag").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
                    .help("Add label")
                    .popover(isPresented: $showLabelPicker, arrowEdge: .bottom) {
                        LabelPickerView(pr: pr) { add, remove in
                            await state.updateLabels(add: add, remove: remove, on: pr)
                        }
                        .environmentObject(state)
                        .environment(\.colorScheme, .dark)
                    }
                    Button(action: onSnooze) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
                    .help(snoozeHelp)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
    }

    private var labelChips: some View {
        HStack(spacing: 4) {
            ForEach(pr.labels, id: \.self) { label in
                let color = Color(hex: label.color)
                Text(label.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.22)))
                    .foregroundStyle(color)
            }
        }
        .lineLimit(1)
        .padding(.top, 1)
    }

    private var dotColor: Color {
        switch pr.accent {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .notchGreen
        case .neutral: return .blue
        }
    }
}

/// Popover listing a repo's labels, multi-selectable. Labels already on the PR
/// start checked; unchecking one removes it on Apply.
private struct LabelPickerView: View {
    let pr: PullRequest
    let onApply: (_ add: [String], _ remove: [String]) async -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var labels: [PRLabel] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: Set<String> = []
    @State private var applying = false

    private var applied: Set<String> { Set(pr.labels.map(\.name)) }
    private var additions: [String] { selected.subtracting(applied).sorted() }
    private var removals: [String] { applied.subtracting(selected).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Labels")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            if loading {
                ProgressView().controlSize(.small).tint(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if let error {
                Text(error)
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(labels, id: \.self) { label in
                            row(for: label)
                        }
                    }
                }
                // Popovers size to the content's ideal height, and a ScrollView's
                // ideal height is ~zero — pin it to the row count (capped) instead.
                .frame(height: min(CGFloat(labels.count) * 26, 240))

                Divider().overlay(Color.white.opacity(0.08))
                Button {
                    let (add, remove) = (additions, removals)
                    applying = true
                    Task { await onApply(add, remove); dismiss() }
                } label: {
                    Text(applying ? "Applying…" : "Apply")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled((additions.isEmpty && removals.isEmpty) || applying)
                .padding(12)
            }
        }
        .frame(width: 240)
        .background(.black.opacity(0.92))
        .task {
            do {
                labels = try await state.repoLabels(for: pr.repo)
                selected = applied
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            loading = false
        }
    }

    @ViewBuilder private func row(for label: PRLabel) -> some View {
        let isSelected = selected.contains(label.name)
        HStack(spacing: 8) {
            Circle().fill(Color(hex: label.color)).frame(width: 9, height: 9)
            Text(label.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selected.remove(label.name) } else { selected.insert(label.name) }
        }
    }
}
