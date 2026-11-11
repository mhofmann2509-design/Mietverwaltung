import Foundation
import SwiftData

/// Die vereinbarte Mietvertragsart – bestimmt, welche gesetzlichen Fristen/Möglichkeiten für
/// eine Mieterhöhung gelten, siehe `RentIncreaseAdvisor`.
enum TenancyContractType: String, Codable, CaseIterable, Identifiable {
    case standard
    case staffel
    case index

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .staffel: return "Staffelmiete"
        case .index: return "Indexmiete"
        }
    }
}

/// A rental agreement ("Mietvertrag") between a tenant and a unit.
@Model
final class Tenancy {
    var startDate: Date = Date.now
    var endDate: Date?
    var coldRent: Double = 0          // Kaltmiete
    var utilityAdvance: Double = 0    // Nebenkostenvorauszahlung
    var deposit: Double = 0           // Kaution
    var depositReceived: Bool = false
    /// Zeitpunkt der Kautionsrückzahlung an den Mieter nach Mietende – `nil`, solange noch nicht
    /// zurückgezahlt. Es gibt keine feste gesetzliche Frist, die Rechtsprechung sieht i.d.R. bis
    /// zu sechs Monate nach Mietende als übliche Obergrenze für die Abrechnung an.
    var depositReturnedAt: Date?
    var noticePeriodMonths: Int = 3
    var occupantCount: Int = 1        // Personenzahl (für Umlageschlüssel „Nach Personenzahl“)
    var notes: String = ""
    var createdAt: Date = Date.now

    var contractTypeRaw: String = TenancyContractType.standard.rawValue
    /// Zeitpunkt der letzten Mieterhöhung auf die ortsübliche Vergleichsmiete (§ 558 BGB) –
    /// ohne Eintrag gilt `startDate` als Referenz für die 15-Monats-Frist.
    var lastRentIncreaseDate: Date?
    /// Zeitpunkt der letzten Indexmietanpassung (§ 557b BGB) – ohne Eintrag gilt `startDate`
    /// als Referenz für die 12-Monats-Frist.
    var lastIndexAdjustmentDate: Date?

    /// Zeitpunkt der Modernisierungsankündigung (§ 555c BGB) – rein informativ, die Maßnahme darf
    /// frühestens 3 Monate danach beginnen. Optional, unabhängig von `contractType`.
    var modernizationAnnouncedAt: Date?
    /// Zeitpunkt des Zugangs der Mieterhöhungserklärung nach Abschluss der Modernisierung
    /// (§ 559b BGB) – Grundlage für den Zeitpunkt, ab dem die erhöhte Miete zu entrichten ist.
    var modernizationIncreaseDeclaredAt: Date?

    var unit: Unit?
    var tenant: Tenant?

    @Relationship(deleteRule: .cascade, inverse: \RentPayment.tenancy)
    var payments: [RentPayment]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.tenancy)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \UtilityStatementDispatch.tenancy)
    var statementDispatches: [UtilityStatementDispatch]? = []

    @Relationship(deleteRule: .cascade, inverse: \RentStep.tenancy)
    var rentSteps: [RentStep]? = []

    init(startDate: Date = .now, endDate: Date? = nil, coldRent: Double = 0, utilityAdvance: Double = 0, deposit: Double = 0, depositReceived: Bool = false, noticePeriodMonths: Int = 3, occupantCount: Int = 1, notes: String = "", contractType: TenancyContractType = .standard) {
        self.startDate = startDate
        self.endDate = endDate
        self.coldRent = coldRent
        self.utilityAdvance = utilityAdvance
        self.deposit = deposit
        self.depositReceived = depositReceived
        self.noticePeriodMonths = noticePeriodMonths
        self.occupantCount = occupantCount
        self.notes = notes
        self.createdAt = .now
        self.contractTypeRaw = contractType.rawValue
    }

    var contractType: TenancyContractType {
        get { TenancyContractType(rawValue: contractTypeRaw) ?? .standard }
        set { contractTypeRaw = newValue.rawValue }
    }

    var totalMonthlyAmount: Double {
        coldRent + utilityAdvance
    }

    var isActive: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        guard let endDate else { return startDate <= today }
        return startDate <= today && endDate >= today
    }

    func isRunning(on date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        guard let endDate else { return startDate <= day }
        return startDate <= day && endDate >= day
    }

    /// Returns the existing payment entry for the month containing `date`, if any.
    func payment(forMonthContaining date: Date) -> RentPayment? {
        let calendar = Calendar.current
        return payments?.first { payment in
            calendar.isDate(payment.dueDate, equalTo: date, toGranularity: .month)
        }
    }

    /// Summe der tatsächlich geleisteten Nebenkostenvorauszahlungen in einem Kalenderjahr
    /// (Grundlage für die Nebenkostenabrechnung).
    func utilityAdvancesPaid(inYear year: Int) -> Double {
        (payments ?? [])
            .filter { $0.isPaid && Calendar.current.component(.year, from: $0.dueDate) == year }
            .reduce(0) { $0 + $1.utilityAdvanceDue }
    }

    /// Summe der tatsächlich geleisteten Nebenkostenvorauszahlungen innerhalb eines frei wählbaren
    /// Zeitraums. Bei einer Teilzahlung (`paidAmount` < Gesamtsoll) wird der gezahlte Betrag im
    /// Verhältnis von Nebenkostenvorauszahlung zu Gesamtsoll aufgeteilt, statt die volle Soll-
    /// Vorauszahlung als geleistet zu zählen, sobald irgendein Betrag als bezahlt erfasst ist.
    func utilityAdvancesPaid(from start: Date, to end: Date) -> Double {
        (payments ?? [])
            .filter { $0.isPaid && $0.dueDate >= start && $0.dueDate <= end }
            .reduce(0) { sum, payment in
                guard payment.totalDue > 0 else { return sum }
                let paid = payment.paidAmount ?? payment.totalDue
                let utilityShare = paid * (payment.utilityAdvanceDue / payment.totalDue)
                return sum + utilityShare
            }
    }

    /// Anteilige Kaltmiete dieses Mietverhältnisses innerhalb eines frei wählbaren Zeitraums:
    /// monatsgenau für die tatsächlich überlappenden Monate, nicht nur für Monate, deren 1. Tag in
    /// den Zeitraum fällt – ein unterjährig begonnenes oder beendetes Mietverhältnis fließt also
    /// nicht mit vollen Monaten ein. Gemeinsame Basis für `Property.annualColdRent(forYear:)` und
    /// die Dashboard-Kennzahl je gewähltem Zeitraum, damit beide dieselbe Zahl zeigen.
    func coldRentContribution(from rangeStart: Date, to rangeEnd: Date) -> Double {
        let calendar = Calendar.current
        func monthIndex(_ date: Date) -> Int {
            let components = calendar.dateComponents([.year, .month], from: date)
            return (components.year ?? 0) * 12 + (components.month ?? 0)
        }
        let tenancyEnd = endDate ?? rangeEnd
        let overlapStart = max(startDate, rangeStart)
        let overlapEnd = min(tenancyEnd, rangeEnd)
        guard overlapStart <= overlapEnd else { return 0 }
        let months = monthIndex(overlapEnd) - monthIndex(overlapStart) + 1
        return coldRent * Double(months)
    }

    /// Laufender Saldo des Mietrückstandskontos zu einem Stichtag: Summe aus Soll minus Ist über
    /// alle Monate seit Mietbeginn bis einschließlich des Monats von `date` – positiv bedeutet
    /// einen Rückstand des Mieters, negativ ein Guthaben. Monate ohne erfasste Zahlung gelten
    /// als vollständig offen.
    func arrearsBalance(upTo date: Date = .now) -> Double {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month], from: date)
        guard var year = startComponents.year, let startMonth = startComponents.month,
              let endYear = endComponents.year, let endMonth = endComponents.month else { return 0 }
        var month = startMonth
        var balance = 0.0
        while year < endYear || (year == endYear && month <= endMonth) {
            if let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)), isRunning(on: monthDate) {
                let due = totalMonthlyAmount
                let payment = payment(forMonthContaining: monthDate)
                let paid = (payment?.isPaid == true) ? (payment?.paidAmount ?? due) : 0
                balance += (due - paid)
            }
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return balance
    }

    /// Anzahl Tage, die dieses Mietverhältnis innerhalb des angegebenen Kalenderjahres lief
    /// (für die anteilige Verteilung der Nebenkosten bei unterjährigem Ein-/Auszug).
    func activeDays(inYear year: Int) -> Int {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
        return activeDays(from: yearStart, to: yearEnd)
    }

    /// Anzahl Tage, die dieses Mietverhältnis innerhalb eines frei wählbaren Zeitraums lief
    /// (für die anteilige Verteilung der Nebenkosten bei unterjährigem Ein-/Auszug).
    func activeDays(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let periodStart = calendar.startOfDay(for: start)
        let periodEnd = calendar.startOfDay(for: end)
        let effectiveStart = max(calendar.startOfDay(for: startDate), periodStart)
        let effectiveEnd = min(endDate.map { calendar.startOfDay(for: $0) } ?? periodEnd, periodEnd)
        guard effectiveEnd >= effectiveStart else { return 0 }
        return (calendar.dateComponents([.day], from: effectiveStart, to: effectiveEnd).day ?? 0) + 1
    }

    /// Tage seit Mietende, wenn eine vereinbarte Kaution nach Mietende noch nicht zurückgezahlt
    /// wurde – `nil`, wenn das Mietverhältnis noch läuft, keine Kaution vereinbart war oder sie
    /// bereits zurückgezahlt wurde. Grundlage für den Kautionsrückzahlungs-Hinweis in
    /// `RemindersEngine` (keine feste gesetzliche Frist, siehe `depositReturnedAt`).
    func daysSinceEndWithUnreturnedDeposit(today: Date = .now) -> Int? {
        guard let endDate, deposit > 0, depositReturnedAt == nil, endDate <= today else { return nil }
        return Calendar.current.dateComponents([.day], from: endDate, to: today).day.map { max(0, $0) }
    }
}
