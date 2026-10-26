import Foundation
import SwiftData

/// A rental agreement ("Mietvertrag") between a tenant and a unit.
@Model
final class Tenancy {
    var startDate: Date = Date.now
    var endDate: Date?
    var coldRent: Double = 0          // Kaltmiete
    var utilityAdvance: Double = 0    // Nebenkostenvorauszahlung
    var deposit: Double = 0           // Kaution
    var depositReceived: Bool = false
    var noticePeriodMonths: Int = 3
    var occupantCount: Int = 1        // Personenzahl (für Umlageschlüssel „Nach Personenzahl“)
    var notes: String = ""
    var createdAt: Date = Date.now

    var unit: Unit?
    var tenant: Tenant?

    @Relationship(deleteRule: .cascade, inverse: \RentPayment.tenancy)
    var payments: [RentPayment]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.tenancy)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \UtilityStatementDispatch.tenancy)
    var statementDispatches: [UtilityStatementDispatch]? = []

    init(startDate: Date = .now, endDate: Date? = nil, coldRent: Double = 0, utilityAdvance: Double = 0, deposit: Double = 0, depositReceived: Bool = false, noticePeriodMonths: Int = 3, occupantCount: Int = 1, notes: String = "") {
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
}
