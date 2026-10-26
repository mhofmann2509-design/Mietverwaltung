import Foundation
import SwiftData

/// Die jährliche Nebenkostenabrechnung der Hausverwaltung für eine Immobilie –
/// Grundlage, um daraus die Abrechnung für die einzelnen Mieter zu erstellen.
@Model
final class UtilityStatement {
    /// Abrechnungszeitraum – standardmäßig das Kalenderjahr, aber frei wählbar (z.B. bei
    /// unterjährigem Beginn der Verwaltung oder einem abweichenden Abrechnungszyklus).
    var periodStart: Date = Date.now
    var periodEnd: Date = Date.now
    var allocationMethodRaw: String = AllocationMethod.livingSpace.rawValue
    /// Grundsteuer des Abrechnungszeitraums – wird selbst eingegeben (steht meist nicht im Schreiben
    /// der Hausverwaltung), ist aber nach §2 Nr. 1 BetrKV auf die Mieter umlagefähig.
    var propertyTaxAmount: Double = 0
    /// Instandhaltungsrücklagenkonto bei der Hausverwaltung (Kontonummer/IBAN und/oder Kontostand),
    /// wie auf der eingescannten Abrechnung der Hausverwaltung vermerkt.
    var reserveFundAccountInfo: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    var property: Property?

    @Relationship(deleteRule: .cascade, inverse: \UtilityCostLineItem.statement)
    var lineItems: [UtilityCostLineItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.utilityStatement)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \UtilityStatementDispatch.statement)
    var dispatches: [UtilityStatementDispatch]? = []

    init(year: Int = Calendar.current.component(.year, from: .now), propertyTaxAmount: Double = 0, notes: String = "", allocationMethod: AllocationMethod = .livingSpace) {
        self.propertyTaxAmount = propertyTaxAmount
        self.notes = notes
        self.allocationMethodRaw = allocationMethod.rawValue
        self.createdAt = .now
        let calendar = Calendar.current
        self.periodStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        self.periodEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? .now
    }

    var allocationMethod: AllocationMethod {
        get { AllocationMethod(rawValue: allocationMethodRaw) ?? .livingSpace }
        set { allocationMethodRaw = newValue.rawValue }
    }

    /// Kalenderjahr dieser Abrechnung, abgeleitet aus dem Ende des tatsächlichen
    /// Abrechnungszeitraums – kein eigenständig speicherbares Feld mehr, damit es nie vom
    /// tatsächlichen Zeitraum abweichen kann (vormals ein unabhängiges Feld, das z.B. in der
    /// Cashflow-Berechnung und den Fristen-Hinweisen zu Fehlzuordnungen führen konnte).
    var year: Int {
        Calendar.current.component(.year, from: periodEnd)
    }

    /// Summe aller Kostenarten aus dem Schreiben der Hausverwaltung, umlagefähig oder nicht.
    var lineItemsTotal: Double {
        (lineItems ?? []).reduce(0) { $0 + $1.amount }
    }

    /// Umlagefähige Kostenarten aus dem Schreiben der Hausverwaltung (ohne Grundsteuer).
    var apportionableLineItemsTotal: Double {
        (lineItems ?? []).filter { $0.isApportionable }.reduce(0) { $0 + $1.amount }
    }

    /// Nicht umlagefähige Kostenarten – verbleiben beim Vermieter, mindern den freien Cashflow.
    var nonApportionableLineItemsTotal: Double {
        (lineItems ?? []).filter { !$0.isApportionable }.reduce(0) { $0 + $1.amount }
    }

    /// Grundlage für die Verteilung auf die Mieter: umlagefähige Kostenarten + Grundsteuer.
    var totalApportionableCosts: Double {
        apportionableLineItemsTotal + propertyTaxAmount
    }

    /// Alle Kosten zusammen (umlagefähig + nicht umlagefähig + Grundsteuer), zur Information.
    var totalCosts: Double {
        lineItemsTotal + propertyTaxAmount
    }
}

/// Eine einzelne Kostenart innerhalb der Nebenkostenabrechnung der Hausverwaltung,
/// z.B. „Heizung“, „Wasser/Abwasser“, „Hausmeister“.
@Model
final class UtilityCostLineItem {
    var costType: String = ""
    var amount: Double = 0
    /// Ob diese Kostenart nach der Betriebskostenverordnung auf die Mieter umgelegt werden darf
    /// (z.B. Heizung, Wasser ja; Verwaltergebühr, Instandhaltungsrücklage nein).
    var isApportionable: Bool = true
    /// Optionaler Umlageschlüssel laut Hausverwaltung für genau diese Kostenart (z.B. „MEA (4)“,
    /// „lt.An (11)“ bei verbrauchsabhängiger Heizkostenabrechnung). Manche Hausverwaltungen –
    /// insbesondere bei WEG-Wohngeldabrechnungen – rechnen je Kostenart mit unterschiedlichen
    /// Schlüsseln ab. Rein informativ zur Nachvollziehbarkeit, beeinflusst nicht die
    /// App-eigene Verteilung auf die Mieter dieser Immobilie (siehe `UtilityStatement.allocationMethod`).
    var allocationKeyLabel: String = ""

    var statement: UtilityStatement?

    init(costType: String = "", amount: Double = 0, isApportionable: Bool = true, allocationKeyLabel: String = "") {
        self.costType = costType
        self.amount = amount
        self.isApportionable = isApportionable
        self.allocationKeyLabel = allocationKeyLabel
    }
}

/// Markiert, ob und wann das individuelle Abrechnungsschreiben für ein Mietverhältnis innerhalb
/// einer Nebenkostenabrechnung verschickt wurde – unabhängig davon, ob/wie oft das PDF erzeugt
/// wurde. Ein Eintrag pro (Abrechnung, Mietverhältnis); ohne Eintrag gilt „noch nicht verschickt“.
@Model
final class UtilityStatementDispatch {
    var sentDate: Date = Date.now

    var statement: UtilityStatement?
    var tenancy: Tenancy?

    init(sentDate: Date = .now) {
        self.sentDate = sentDate
    }
}
