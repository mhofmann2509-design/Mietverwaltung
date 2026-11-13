import Foundation
import SwiftData

/// Berechnungen rund um das WEG-Hausgeld einer Einheit.
///
/// Annahme wie bei den Nebenkostenabrechnungen der App: Wirtschaftsplan und Jahresabrechnung
/// einer Immobilie enthalten die Beträge für alle eigenen Einheiten dieses Objekts. Der Anteil
/// einer Einheit richtet sich nach Miteigentumsanteilen (MEA), ersatzweise nach Wohnfläche,
/// sonst zu gleichen Teilen. Die Grundsteuer zahlt der Eigentümer an die Gemeinde, nicht über
/// das Hausgeld – sie bleibt deshalb außen vor.
enum HausgeldCalculator {
    struct Proposal: Equatable {
        let monthlyAmount: Double
        let apportionableMonthly: Double
        let reserveFundMonthly: Double
        let unitShare: Double
        let shareBasis: String
    }

    struct YearAccount: Equatable {
        /// Soll aller Monate mit gültigem Hausgeld-Plan.
        let due: Double
        let paid: Double
        /// Monate mit Plan, aber ohne (bezahlte) Zahlung.
        let openMonths: Int
        var balance: Double { due - paid }
    }

    struct Settlement: Equatable {
        /// Anteil der Einheit an den Kosten laut Jahresabrechnung (ohne Grundsteuer).
        let actualCosts: Double
        let advancesPaid: Double
        /// Positiv = Nachzahlung an die WEG, negativ = Guthaben.
        var balance: Double { actualCosts - advancesPaid }
    }

    /// Anteil der Einheit an ihrer Immobilie (0…1) und die verwendete Grundlage.
    static func share(of unit: Unit) -> (value: Double, basis: String) {
        let units = unit.property?.units ?? [unit]
        let totalShares = units.reduce(0) { $0 + $1.coOwnershipShare }
        if totalShares > 0, unit.coOwnershipShare > 0 {
            return (unit.coOwnershipShare / totalShares, "MEA")
        }
        let totalArea = units.reduce(0) { $0 + $1.sizeSquareMeters }
        if totalArea > 0, unit.sizeSquareMeters > 0 {
            return (unit.sizeSquareMeters / totalArea, "Wohnfläche")
        }
        return (1 / Double(max(units.count, 1)), "gleiche Teile")
    }

    /// Positionen der Erhaltungsrücklage erkennt die App an der Bezeichnung.
    static func isReserveFund(_ costType: String) -> Bool {
        let lower = costType.lowercased()
        return lower.contains("rücklage") || lower.contains("ruecklage") || lower.contains("rueckstellung") || lower.contains("rückstellung")
    }

    /// Monatliches Hausgeld der Einheit aus dem Wirtschaftsplan (Jahreswerte ÷ 12).
    static func proposal(from plan: WirtschaftsplanStatement, for unit: Unit) -> Proposal {
        let (share, basis) = share(of: unit)
        let items = plan.lineItems ?? []
        let total = items.reduce(0) { $0 + $1.amount }
        let apportionable = items.filter { $0.isApportionable && !isReserveFund($0.costType) }.reduce(0) { $0 + $1.amount }
        let reserve = items.filter { isReserveFund($0.costType) }.reduce(0) { $0 + $1.amount }
        func monthly(_ annual: Double) -> Double { (annual * share / 12).roundedToCents }
        return Proposal(monthlyAmount: monthly(total), apportionableMonthly: monthly(apportionable), reserveFundMonthly: monthly(reserve), unitShare: share, shareBasis: basis)
    }

    /// Der am Tag `date` gültige Plan (spätester Beginn ≤ Tag).
    static func plan(for unit: Unit, on date: Date) -> HausgeldPlan? {
        let day = Calendar.current.startOfDay(for: date)
        return (unit.hausgeldPlans ?? [])
            .filter { Calendar.current.startOfDay(for: $0.validFrom) <= day }
            .max { $0.validFrom < $1.validFrom }
    }

    static func payment(for unit: Unit, inMonthOf date: Date) -> HausgeldPayment? {
        (unit.hausgeldPayments ?? []).first { Calendar.current.isDate($0.dueDate, equalTo: date, toGranularity: .month) }
    }

    /// Soll eines Monats: der zum Monatsletzten gültige Plan (ein Plan ab dem 15. gilt für den
    /// ganzen Monat, wie üblich bei Wirtschaftsplänen ab Beschluss).
    static func monthlyDue(for unit: Unit, inMonthOf date: Date) -> Double {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else { return 0 }
        return plan(for: unit, on: monthEnd)?.monthlyAmount ?? 0
    }

    /// Hausgeldkonto eines Jahres bis einschließlich des Monats von `upTo`.
    static func account(for unit: Unit, year: Int, upTo: Date = .now) -> YearAccount {
        let calendar = Calendar.current
        var due = 0.0, paid = 0.0, open = 0
        for month in 1...12 {
            guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { continue }
            if monthStart > upTo { break }
            let payment = payment(for: unit, inMonthOf: monthStart)
            let monthDue = payment?.amountDue ?? monthlyDue(for: unit, inMonthOf: monthStart)
            guard monthDue > 0 else { continue }
            due += monthDue
            let monthPaid = payment?.effectivePaidAmount ?? 0
            paid += monthPaid
            if monthPaid + 0.005 < monthDue { open += 1 }
        }
        return YearAccount(due: due, paid: paid, openMonths: open)
    }

    /// Abrechnungsspitze: Kostenanteil laut Jahresabrechnung minus gezahlte Vorschüsse des Jahres.
    static func settlement(for unit: Unit, statement: UtilityStatement) -> Settlement {
        let costs = (statement.lineItemsTotal * share(of: unit).value).roundedToCents
        let year = statement.year
        let paid = (unit.hausgeldPayments ?? [])
            .filter { Calendar.current.component(.year, from: $0.dueDate) == year }
            .reduce(0) { $0 + $1.effectivePaidAmount }
        return Settlement(actualCosts: costs, advancesPaid: paid.roundedToCents)
    }

    /// Markiert einen Monat als bezahlt; fehlt der Eintrag, wird er mit dem Soll laut Plan angelegt.
    static func markPaid(unit: Unit, month: Date, on paidDate: Date = .now, amount: Double? = nil, context: ModelContext) {
        if let existing = payment(for: unit, inMonthOf: month) {
            existing.markPaid(amount: amount, date: paidDate)
        } else {
            let calendar = Calendar.current
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
            let payment = HausgeldPayment(dueDate: monthStart, amountDue: monthlyDue(for: unit, inMonthOf: monthStart))
            payment.markPaid(amount: amount, date: paidDate)
            payment.unit = unit
            context.insert(payment)
        }
    }
}
