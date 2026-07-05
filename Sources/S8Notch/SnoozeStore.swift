import Foundation

/// Remembers which PRs the user has snoozed, and until when. Persisted to
/// UserDefaults so snoozes survive refreshes and relaunches. Keyed by PR url.
@MainActor
final class SnoozeStore {
    private let key = "snoozedPRs"
    private let defaults = UserDefaults.standard
    private var untilByID: [String: Double]   // PR id -> snooze-until (epoch seconds)

    init() {
        untilByID = (defaults.dictionary(forKey: key))?
            .compactMapValues { $0 as? Double } ?? [:]
        prune()
    }

    func snooze(_ id: String, for duration: TimeInterval) {
        untilByID[id] = Date().addingTimeInterval(duration).timeIntervalSince1970
        persist()
    }

    func isSnoozed(_ id: String) -> Bool {
        guard let until = untilByID[id] else { return false }
        return until > Date().timeIntervalSince1970
    }

    var activeCount: Int {
        let now = Date().timeIntervalSince1970
        return untilByID.values.filter { $0 > now }.count
    }

    func clearAll() {
        untilByID = [:]
        persist()
    }

    /// Drop entries whose snooze has already elapsed.
    func prune() {
        let now = Date().timeIntervalSince1970
        let live = untilByID.filter { $0.value > now }
        if live.count != untilByID.count {
            untilByID = live
            persist()
        }
    }

    private func persist() { defaults.set(untilByID, forKey: key) }
}
