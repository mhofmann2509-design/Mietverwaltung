import Foundation
import SwiftData
import SwiftUI

/// - Note: `rawValue` is a stable key persisted to disk. The German text shown to the
///   user lives in `label` instead, so renaming or localizing a category later never
///   breaks already-saved data.
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case maintenance
    case utilities
    case insurance
    case tax
    case financing
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .maintenance: return "Instandhaltung"
        case .utilities: return "Betriebskosten"
        case .insurance: return "Versicherung"
        case .tax: return "Steuern & Abgaben"
        case .financing: return "Finanzierung"
        case .other: return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver"
        case .utilities: return "bolt"
        case .insurance: return "shield"
        case .tax: return "building.columns"
        case .financing: return "banknote"
        case .other: return "ellipsis.circle"
        }
    }

    /// Sinnvoller steuerlicher Standardwert für eine neu angelegte Ausgabe dieser Kategorie.
    var defaultTaxTreatment: TaxTreatment {
        self == .maintenance ? .maintenanceExpense : .otherDeductible
    }

    /// Konsistente Einfärbung in Listen/Dashboard, unabhängig von der Akzentfarbe.
    var color: Color {
        switch self {
        case .maintenance: return .blue
        case .utilities: return .yellow
        case .insurance: return .purple
        case .tax: return .gray
        case .financing: return .green
        case .other: return .secondary
        }
    }
}

@Model
final class Expense {
    var date: Date = Date.now
    var amount: Double = 0                      // wie auf dem Beleg, i.d.R. brutto – bleibt die für
                                                  // Werbungskosten/Cashflow maßgebliche Größe
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var title: String = ""
    var notes: String = ""
    var taxTreatmentRaw: String = TaxTreatment.otherDeductible.rawValue
    /// Umsatzsteuersatz des Belegs (z.B. 19 oder 7), falls bekannt – ausschließlich für Fälle
    /// nötig, in denen der Netto-Betrag maßgeblich ist (z.B. 15-%-Grenze, siehe
    /// `ThreeYearThresholdCase`). Ohne Angabe gilt der Netto-Betrag als nicht ermittelbar, statt
    /// `amount` stillschweigend als Netto zu behandeln.
    var vatRatePercent: Double?

    var property: Property?
    var unit: Unit?

    @Relationship(deleteRule: .cascade, inverse: \Document.expense)
    var documents: [Document]? = []

    /// `taxTreatment` nil lässt die steuerliche Behandlung anhand der Kategorie automatisch bestimmen
    /// (Instandhaltung → Erhaltungsaufwand, sonst → sonstige Werbungskosten).
    init(date: Date = .now, amount: Double = 0, category: ExpenseCategory = .other, title: String = "", notes: String = "", taxTreatment: TaxTreatment? = nil) {
        self.date = date
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.title = title
        self.notes = notes
        self.taxTreatmentRaw = (taxTreatment ?? category.defaultTaxTreatment).rawValue
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var taxTreatment: TaxTreatment {
        get { TaxTreatment(rawValue: taxTreatmentRaw) ?? .otherDeductible }
        set { taxTreatmentRaw = newValue.rawValue }
    }

    /// Aus `amount` (brutto) und `vatRatePercent` abgeleiteter Netto-Betrag – `nil`, wenn kein
    /// Umsatzsteuersatz hinterlegt ist, statt `amount` ungeprüft als Netto zu übernehmen.
    var netAmount: Double? {
        guard let vatRatePercent else { return nil }
        return amount / (1 + vatRatePercent / 100)
    }
}
