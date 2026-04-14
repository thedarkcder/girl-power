import Foundation

struct EntitlementGracePolicy {
    let isSubscribed: Bool
    let hasValidatedSnapshot: Bool
    let revalidationGraceDeadline: Date?

    func effectiveIsPro(now: Date) -> Bool {
        if isSubscribed {
            return true
        }
        guard hasValidatedSnapshot, let deadline = revalidationGraceDeadline else {
            return false
        }
        return now < deadline
    }

    static func graceDeadline(
        hasValidatedSnapshot: Bool,
        now: Date,
        gracePeriod: TimeInterval
    ) -> Date? {
        guard hasValidatedSnapshot else {
            return nil
        }
        return now.addingTimeInterval(gracePeriod)
    }
}
