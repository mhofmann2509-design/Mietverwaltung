import Foundation
import SwiftData

/// Hausgeld einer Einheit an die WEG ab einem Stichtag – vorgeschlagen aus dem Wirtschaftsplan
/// (`HausgeldCalculator.proposal`), danach frei anpassbar. Gilt, bis ein späterer Plan beginnt.
///
/// Steuerlich wird das Hausgeld hier bewusst nicht angesetzt: Die abziehbaren Kosten kommen wie
/// bisher aus der WEG-Jahresabrechnung (Nebenkostenabrechnung), sonst würden sie doppelt zählen.
@Model
final class HausgeldPlan {
    var validFrom: Date = Date.now
    /// Monatliches Hausgeld gesamt.
    var monthlyAmount: Double = 0
    /// Davon auf die Mieter umlagefähig.
    var apportionableMonthly: Double = 0
    /// Davon Zuführung zur Erhaltungsrücklage (erst bei Verwendung durch die WEG abziehbar).
    var reserveFundMonthly: Double = 0
    /// Jahr des Wirtschaftsplans, aus dem der Vorschlag stammt (`nil` = frei eingetragen).
    var sourcePlanYear: Int?
    /// Vorschlag aus dem Wirtschaftsplan wurde von Hand geändert.
    var isManuallyAdjusted: Bool = false
    var notes: String = ""
    var createdAt: Date = Date.now

    var unit: Unit?

    init(validFrom: Date = .now, monthlyAmount: Double = 0, apportionableMonthly: Double = 0, reserveFundMonthly: Double = 0, sourcePlanYear: Int? = nil) {
        self.validFrom = validFrom
        self.monthlyAmount = monthlyAmount
        self.apportionableMonthly = apportionableMonthly
        self.reserveFundMonthly = reserveFundMonthly
        self.sourcePlanYear = sourcePlanYear
        self.createdAt = .now
    }

    /// Nicht umlagefähiger Anteil ohne Rücklage (z.B. Verwaltergebühr).
    var nonApportionableMonthly: Double {
        max(0, monthlyAmount - apportionableMonthly - reserveFundMonthly)
    }
}

/// Eine Hausgeld-Zahlung für einen Monat (Soll laut Plan zum Zeitpunkt der Erfassung).
@Model
final class HausgeldPayment {
    var dueDate: Date = Date.now
    var amountDue: Double = 0
    var paidDate: Date?
    var paidAmount: Double?
    var note: String = ""

    var unit: Unit?

    init(dueDate: Date = .now, amountDue: Double = 0) {
        self.dueDate = dueDate
        self.amountDue = amountDue
    }

    var isPaid: Bool { paidDate != nil }

    /// Tatsächlich gezahlter Betrag; ohne Angabe gilt das Soll als voll gezahlt.
    var effectivePaidAmount: Double { isPaid ? (paidAmount ?? amountDue) : 0 }

    func markPaid(amount: Double? = nil, date: Date = .now) {
        paidDate = date
        paidAmount = amount
    }

    func markUnpaid() {
        paidDate = nil
        paidAmount = nil
    }
}

/// Sonderumlage der WEG. Die steuerliche Behandlung und der anzusetzende Betrag werden von Hand
/// eingetragen (sie ergeben sich aus der Abrechnung der Hausverwaltung). Sobald bezahlt, wird
/// eine verknüpfte Ausgabe gebucht – so fließt die Umlage über die bestehende Logik in
/// Werbungskosten, AfA-Erfassung, 15-%-Grenze und Cashflow ein (`SpecialLevy.syncExpense`).
@Model
final class SpecialLevy {
    var title: String = ""
    var purpose: String = ""
    var amount: Double = 0
    var dueDate: Date = Date.now
    var resolutionDate: Date?
    var paidDate: Date?
    var paidAmount: Double?
    var taxTreatmentRaw: String = TaxTreatment.maintenanceExpense.rawValue
    /// Steuerlich anzusetzender Betrag laut Abrechnung, falls abweichend vom gezahlten Betrag
    /// (z.B. wenn ein Teil in die Erhaltungsrücklage fließt).
    var deductibleAmountOverride: Double?
    var notes: String = ""
    var createdAt: Date = Date.now

    var property: Property?
    var unit: Unit?
    var ownersMeeting: OwnersMeetingEvent?
    @Relationship(deleteRule: .cascade, inverse: \Expense.specialLevy)
    var expense: Expense?

    init(title: String = "", amount: Double = 0, dueDate: Date = .now, taxTreatment: TaxTreatment = .maintenanceExpense) {
        self.title = title
        self.amount = amount
        self.dueDate = dueDate
        self.taxTreatmentRaw = taxTreatment.rawValue
        self.createdAt = .now
    }

    var taxTreatment: TaxTreatment {
        get { TaxTreatment(rawValue: taxTreatmentRaw) ?? .maintenanceExpense }
        set { taxTreatmentRaw = newValue.rawValue }
    }

    var isPaid: Bool { paidDate != nil }

    var effectivePaidAmount: Double { isPaid ? (paidAmount ?? amount) : 0 }

    /// Betrag der verknüpften Ausgabe: der eingetragene steuerliche Betrag, sonst der gezahlte.
    var bookedAmount: Double { deductibleAmountOverride ?? effectivePaidAmount }

    func isOverdue(on date: Date = .now) -> Bool {
        !isPaid && Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: date)
    }

    /// Hält die verknüpfte Ausgabe passend zur Umlage: bezahlt → Ausgabe anlegen bzw.
    /// aktualisieren (Datum = Zahlungsdatum), nicht bezahlt → Ausgabe entfernen.
    func syncExpense(context: ModelContext) {
        guard let paidDate else {
            if let expense {
                self.expense = nil
                context.delete(expense)
            }
            return
        }
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense()
            context.insert(target)
            expense = target
        }
        target.date = paidDate
        target.amount = bookedAmount
        target.category = .maintenance
        target.title = "Sonderumlage: \(title)"
        target.notes = purpose
        target.taxTreatment = taxTreatment
        target.property = property ?? unit?.property
        target.unit = unit
        target.receiptPending = false
    }
}
