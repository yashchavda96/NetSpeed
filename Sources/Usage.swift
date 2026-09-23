import Foundation

/// Data used today and this month, saved so it survives restarts.
final class Usage {
    private var day = Tally(name: "day", dateFormat: "yyyy-MM-dd")
    private var month = Tally(name: "month", dateFormat: "yyyy-MM")
    private var lastSaved = Date()

    var today: ByteCounts { day.counts(at: Date()) }
    var thisMonth: ByteCounts { month.counts(at: Date()) }

    func add(_ bytes: ByteCounts) {
        let now = Date()
        day.add(bytes, at: now)
        month.add(bytes, at: now)
        // Saved every 30 seconds rather than every second, and again on quit.
        if now.timeIntervalSince(lastSaved) >= 30 {
            save()
        }
    }

    func reset() {
        day.reset()
        month.reset()
        save()
    }

    func save() {
        day.save()
        month.save()
        lastSaved = Date()
    }
}

/// Running total for one calendar period. Starts again from zero when the period changes.
private struct Tally {
    private let key: String
    private let formatter = DateFormatter()
    private var period: String
    private var counts: ByteCounts

    init(name: String, dateFormat: String) {
        key = "usage.\(name)"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat

        let saved = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        period = saved["period"] as? String ?? ""
        counts = ByteCounts(
            received: (saved["received"] as? NSNumber)?.uint64Value ?? 0,
            sent: (saved["sent"] as? NSNumber)?.uint64Value ?? 0
        )
    }

    func counts(at date: Date) -> ByteCounts {
        formatter.string(from: date) == period ? counts : ByteCounts()
    }

    mutating func add(_ bytes: ByteCounts, at date: Date) {
        let current = formatter.string(from: date)
        if current != period {
            period = current
            counts = ByteCounts()
        }
        counts.received &+= bytes.received
        counts.sent &+= bytes.sent
    }

    mutating func reset() {
        counts = ByteCounts()
    }

    func save() {
        UserDefaults.standard.set([
            "period": period,
            "received": NSNumber(value: counts.received),
            "sent": NSNumber(value: counts.sent),
        ], forKey: key)
    }
}
