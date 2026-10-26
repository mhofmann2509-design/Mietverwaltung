import Foundation
import SwiftData

/// Der Wirtschaftsplan der Hausverwaltung für eine Immobilie – die Kosten-**Prognose** für ein
/// Jahr, strukturell wie eine `UtilityStatement` (Kostenarten mit Umlagefähigkeit), aber
/// bewusst als eigenständiges Modell geführt: der Wirtschaftsplan ist eine Planung zu
/// Jahresbeginn, die `UtilityStatement` die tatsächliche Abrechnung nach Jahresende – beide
/// Zahlen sollen nebeneinander sichtbar bleiben, nicht ineinander übergehen.
@Model
final class WirtschaftsplanStatement {
    var year: Int = Calendar.current.component(.year, from: .now)
    var propertyTaxAmount: Double = 0
    /// Instandhaltungsrücklagenkonto bei der Hausverwaltung (Kontonummer/IBAN und/oder geplanter
    /// Zuführungsbetrag), wie auf dem eingescannten Wirtschaftsplan vermerkt.
    var reserveFundAccountInfo: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    var property: Property?

    @Relationship(deleteRule: .cascade, inverse: \WirtschaftsplanLineItem.statement)
    var lineItems: [WirtschaftsplanLineItem]? = []

    init(year: Int = Calendar.current.component(.year, from: .now), propertyTaxAmount: Double = 0, notes: String = "") {
        self.year = year
        self.propertyTaxAmount = propertyTaxAmount
        self.notes = notes
        self.createdAt = .now
    }

    var lineItemsTotal: Double {
        (lineItems ?? []).reduce(0) { $0 + $1.amount }
    }

    var apportionableLineItemsTotal: Double {
        (lineItems ?? []).filter { $0.isApportionable }.reduce(0) { $0 + $1.amount }
    }

    var nonApportionableLineItemsTotal: Double {
        (lineItems ?? []).filter { !$0.isApportionable }.reduce(0) { $0 + $1.amount }
    }

    var totalApportionableCosts: Double {
        apportionableLineItemsTotal + propertyTaxAmount
    }

    var totalCosts: Double {
        lineItemsTotal + propertyTaxAmount
    }
}

/// Eine einzelne geplante Kostenart innerhalb des Wirtschaftsplans, z.B. „Heizung“,
/// „Instandhaltungsrücklage“.
@Model
final class WirtschaftsplanLineItem {
    var costType: String = ""
    var amount: Double = 0
    var isApportionable: Bool = true
    var allocationKeyLabel: String = ""

    var statement: WirtschaftsplanStatement?

    init(costType: String = "", amount: Double = 0, isApportionable: Bool = true, allocationKeyLabel: String = "") {
        self.costType = costType
        self.amount = amount
        self.isApportionable = isApportionable
        self.allocationKeyLabel = allocationKeyLabel
    }
}
