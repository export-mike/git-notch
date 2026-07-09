import Foundation

/// A signal that can mark one of *your own* PRs as needing attention.
enum PRSignal: String, CaseIterable {
    case changesRequested   // a reviewer blocked the merge
    case reviewFeedback     // any formal review has landed
    case failingChecks      // required CI is failing
    case unresolvedComments // open (non-outdated) review threads

    var label: String {
        switch self {
        case .changesRequested:   return "Changes requested"
        case .reviewFeedback:     return "Any review feedback"
        case .failingChecks:      return "Failing CI checks"
        case .unresolvedComments: return "Unresolved comments"
        }
    }
}

/// User-tunable configuration, persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Called whenever a value changes so dependent state can recompute.
    var onChange: (() -> Void)?

    @Published var enabledSignals: Set<PRSignal> {
        didSet { persistSignals(); onChange?() }
    }
    @Published var org: String {
        didSet { defaults.set(org, forKey: "org"); onChange?() }
    }
    @Published var commenter: String {
        didSet { defaults.set(commenter, forKey: "commenter"); onChange?() }
    }
    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval"); onChange?() }
    }
    @Published var snoozeDuration: TimeInterval {
        didSet { defaults.set(snoozeDuration, forKey: "snoozeDuration") }
    }

    /// Whether the first-run setup prompt has been shown. Nothing about the org
    /// is baked in — a fresh install asks for it on first launch.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        if let raw = defaults.array(forKey: "enabledSignals") as? [String] {
            enabledSignals = Set(raw.compactMap(PRSignal.init(rawValue:)))
        } else {
            enabledSignals = Set(PRSignal.allCases) // default: all four on
        }
        org = defaults.object(forKey: "org") as? String ?? ""
        commenter = defaults.string(forKey: "commenter") ?? ""
        // Existing installs that already have an org configured skip the prompt.
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
            || defaults.object(forKey: "org") != nil
        let stored = defaults.double(forKey: "refreshInterval")
        refreshInterval = stored > 0 ? stored : 90
        let snooze = defaults.double(forKey: "snoozeDuration")
        snoozeDuration = snooze > 0 ? snooze : 2 * 60 * 60   // default 2 hours
    }

    private func persistSignals() {
        defaults.set(enabledSignals.map(\.rawValue), forKey: "enabledSignals")
    }

    func isEnabled(_ signal: PRSignal) -> Bool { enabledSignals.contains(signal) }

    func setEnabled(_ signal: PRSignal, _ on: Bool) {
        if on { enabledSignals.insert(signal) } else { enabledSignals.remove(signal) }
    }
}
