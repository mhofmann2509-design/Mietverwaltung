import Foundation
import SwiftUI

/// Wie eine Ausgabe steuerlich zu behandeln ist.
/// - Note: `rawValue` ist ein stabiler, persistierter Schlüssel. Die angezeigten Texte
///   stehen in `label`/`shortLabel`, damit sich Formulierungen später ändern lassen,
///   ohne gespeicherte Daten zu beschädigen.
enum TaxTreatment: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Erhaltungsaufwand: Reparatur/Instandhaltung, sofort abziehbar (§21 EStG).
    case maintenanceExpense
    /// Sonstige sofort abziehbare Werbungskosten (Versicherung, Steuern, Zinsen, Verwaltung, …).
    case otherDeductible
    /// Herstellungskosten/Modernisierung: muss aktiviert und über die Nutzungsdauer abgeschrieben werden (AfA).
    case capitalized
    /// Steuerlich nicht relevant (z.B. private Anschaffung).
    case notDeductible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .maintenanceExpense: return "Erhaltungsaufwand (sofort abziehbar)"
        case .otherDeductible: return "Sonstige Werbungskosten (sofort abziehbar)"
        case .capitalized: return "Herstellungskosten (AfA)"
        case .notDeductible: return "Nicht steuerlich relevant"
        }
    }

    var shortLabel: String {
        switch self {
        case .maintenanceExpense: return "Erhaltungsaufwand"
        case .otherDeductible: return "Sonstige Werbungskosten"
        case .capitalized: return "Herstellungskosten"
        case .notDeductible: return "Nicht relevant"
        }
    }

    var systemImage: String {
        switch self {
        case .maintenanceExpense: return "wrench.and.screwdriver"
        case .otherDeductible: return "minus.circle"
        case .capitalized: return "building.columns"
        case .notDeductible: return "nosign"
        }
    }

    var color: Color {
        switch self {
        case .maintenanceExpense: return .blue
        case .otherDeductible: return .accentColor
        case .capitalized: return .orange
        case .notDeductible: return .secondary
        }
    }

    /// Sofort abziehbare Werbungskosten im weiteren Sinne (Erhaltungsaufwand + sonstige Werbungskosten).
    var isImmediatelyDeductible: Bool {
        self == .maintenanceExpense || self == .otherDeductible
    }
}
