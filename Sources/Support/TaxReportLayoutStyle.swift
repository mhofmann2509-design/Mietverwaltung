import SwiftUI
import Combine

/// Die beiden wählbaren Layout-Vorlagen für die PDF-Steuerreports (siehe `TaxReportPDFBuilder`) –
/// unabhängig vom App-weiten `AppearanceStyle`, da PDFs fürs Finanzamt bewusst nicht am
/// UI-Theme hängen, sondern eine eigene, gedeckte Dokumentoptik behalten.
enum TaxReportLayoutStyle: String, CaseIterable, Identifiable {
    /// Kernzahl direkt unter dem Kapiteltitel hervorgehoben, Herleitung/Tabelle folgt darunter.
    case ergebnisZuerst
    /// Nummeriertes Tabellenraster mit vollen Zellrahmen und schwarzen Abschnittsbalken – an die
    /// amtliche Anlage-V-Formularoptik angelehnt.
    case formularraster

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ergebnisZuerst: return "Ergebnis zuerst"
        case .formularraster: return "Formular-Raster"
        }
    }

    var subtitle: String {
        switch self {
        case .ergebnisZuerst: return "Kernzahl direkt oben, Herleitung darunter."
        case .formularraster: return "Nummeriertes Raster, an die amtliche Anlage V angelehnt."
        }
    }
}

/// Hält die aktuell gewählte Steuerreport-Layoutvorlage persistent (UserDefaults) und als
/// `@Published`, analog zu `AppearanceStore` – aber als eigene Einstellungsachse, da sie nur die
/// PDF-Erzeugung betrifft, nicht die App-UI.
@MainActor
final class TaxReportLayoutStore: ObservableObject {
    static let shared = TaxReportLayoutStore()

    @Published var style: TaxReportLayoutStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.key) }
    }

    private static let key = "taxReportLayoutStyle"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key), let saved = TaxReportLayoutStyle(rawValue: raw) {
            style = saved
        } else {
            style = .ergebnisZuerst
        }
    }
}
