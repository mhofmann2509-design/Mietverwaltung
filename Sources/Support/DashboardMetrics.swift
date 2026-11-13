import Foundation

/// Zeitraum-Granularität für die Kopfzeilen-Auswahl im Dashboard – bestimmt, welcher Ausschnitt
/// für „Kaltmiete", „Zahlungseingänge", „offene Forderungen" und „Ausgaben" betrachtet wird.
enum DashboardPeriod: String, CaseIterable, Identifiable {
    case month, quarter, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "Monat"
        case .quarter: return "Quartal"
        case .year: return "Jahr"
        }
    }

    /// Erster und letzter Kalendertag (jeweils 0:00 Uhr) des Zeitraums, der `now` enthält.
    func range(containing now: Date = .now) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch self {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            return (start, end)
        case .quarter:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let month = comps.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: comps.year, month: quarterStartMonth, day: 1)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? now
            return (start, end)
        case .year:
            let year = calendar.component(.year, from: now)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? now
            return (start, end)
        }
    }

    var currentRange: (start: Date, end: Date) { range(containing: .now) }

    /// Lesbare Bezeichnung des Zeitraums, z.B. „Oktober 2026" / „Q4 2026" / „2026".
    func rangeLabel(containing now: Date = .now) -> String {
        let calendar = Calendar.current
        switch self {
        case .month:
            return now.asMonthYear
        case .quarter:
            let quarter = (calendar.component(.month, from: now) - 1) / 3 + 1
            return "Q\(quarter) \(String(calendar.component(.year, from: now)))"
        case .year:
            return String(calendar.component(.year, from: now))
        }
    }
}

/// Zahlungsstatus eines Mietverhältnisses für den laufenden Monat (Dashboard-Tabelle).
enum DashboardPaymentStatus: String {
    case paid = "Bezahlt"
    case open = "Offen"
    case overdue = "Überfällig"

    init(tenancy: Tenancy, on date: Date = .now) {
        guard let payment = tenancy.payment(forMonthContaining: date) else { self = .open; return }
        if payment.isPaid { self = .paid } else if payment.isOverdue { self = .overdue } else { self = .open }
    }
}

/// Die Dashboard-Kennzahlen je gewähltem Zeitraum – aus `DashboardView` ausgelagert, damit sie
/// ohne Oberfläche testbar sind. Die Eingaben sind bereits auf das gewählte Objekt eingeschränkt.
struct DashboardMetrics {
    let properties: [Property]
    let units: [Unit]
    let tenancies: [Tenancy]
    let expenses: [Expense]
    let range: (start: Date, end: Date)
    var now: Date = .now

    /// Ob `date` im Zeitraum liegt. Das Ende ist der letzte Kalendertag (0:00 Uhr) – er zählt
    /// ganztägig mit, sonst fiele eine am letzten Tag um 14 Uhr erfasste Zahlung heraus.
    private func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.start)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: range.end)) else { return false }
        return date >= start && date < endExclusive
    }

    /// Tagesgenaue Soll-Kaltmiete aller im Zeitraum laufenden Mietverhältnisse – dieselbe Basis
    /// wie `Property.annualColdRent(forYear:)`.
    var coldRent: Double {
        tenancies.reduce(0.0) { $0 + $1.coldRentContribution(from: range.start, to: range.end) }
    }

    /// Im Zeitraum tatsächlich eingegangene Zahlungen (nach Zahlungsdatum).
    var paymentsReceived: Double {
        tenancies.flatMap { $0.payments ?? [] }
            .filter { payment in payment.paidDate.map(contains) ?? false }
            .reduce(0) { $0 + ($1.paidAmount ?? $1.totalDue) }
    }

    /// Ob ein Mietverhältnis im Zeitraum mindestens eine offene (nicht bezahlte) Position hat –
    /// Monat für Monat geprüft, auch wenn für einen Monat gar kein `RentPayment` existiert (dann
    /// gilt er als offen, konsistent mit `PaymentsOverviewView`).
    func hasOpenPosition(_ tenancy: Tenancy) -> Bool {
        let calendar = Calendar.current
        var date = range.start
        while date <= range.end {
            if tenancy.isRunning(on: date), tenancy.payment(forMonthContaining: date)?.isPaid != true {
                return true
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { break }
            date = next
        }
        return false
    }

    /// Mieter mit offenen Forderungen im Zeitraum, summiert wird ihr **gesamter** aktueller
    /// Rückstand (nicht nur der Anteil aus dem Zeitraum).
    var openArrears: Double {
        tenancies
            .filter(hasOpenPosition)
            .reduce(0) { $0 + max(0, $1.arrearsBalance(upTo: now)) }
    }

    var expensesInRange: Double {
        expenses.filter { contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Weitere Kennzahlen (Stichtag `now`)

    var vacantUnits: [Unit] {
        units.filter { unit in !(unit.tenancies ?? []).contains { $0.isRunning(on: now) } }
    }

    var vacancyRatePercent: Double? {
        guard !units.isEmpty else { return nil }
        return Double(vacantUnits.count) / Double(units.count) * 100
    }

    /// Entgangene Kaltmiete je Monat: je leerer Einheit die letzte Miete des zuletzt beendeten
    /// Mietverhältnisses.
    var estimatedMonthlyVacancyLoss: Double {
        vacantUnits.reduce(0.0) { sum, unit in
            let lastPastTenancy = (unit.tenancies ?? [])
                .filter { $0.endDate != nil }
                .max { ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast) }
            return sum + (lastPastTenancy.map { $0.coldRent(forMonthContaining: $0.endDate ?? now) } ?? 0)
        }
    }

    var totalInvestment: Double {
        properties.reduce(0) { $0 + $1.purchasePrice }
    }

    /// Nach Kaufpreis gewichtete Bruttorendite des laufenden Jahres.
    var grossYieldPercent: Double? {
        let relevant = properties.filter { $0.purchasePrice > 0 }
        let totalPrice = relevant.reduce(0) { $0 + $1.purchasePrice }
        guard totalPrice > 0 else { return nil }
        let year = Calendar.current.component(.year, from: now)
        return relevant.reduce(0) { $0 + $1.annualColdRent(forYear: year) } / totalPrice * 100
    }
}
