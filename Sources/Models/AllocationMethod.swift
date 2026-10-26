import Foundation

/// Der Umlageschlüssel, nach dem die Nebenkosten auf die Mieter verteilt werden.
/// - Note: `rawValue` ist ein stabiler, persistierter Schlüssel, siehe `label`.
enum AllocationMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case livingSpace
    case unitCount
    case personCount
    case coOwnershipShare

    var id: String { rawValue }

    var label: String {
        switch self {
        case .livingSpace: return "Nach Wohnfläche"
        case .unitCount: return "Gleichmäßig nach Einheiten"
        case .personCount: return "Nach Personenzahl"
        case .coOwnershipShare: return "Nach Miteigentumsanteilen (MEA)"
        }
    }

    /// Erläuternder Satz fürs Abrechnungsschreiben an den Mieter.
    var documentDescription: String {
        switch self {
        case .livingSpace:
            return "Die Verteilung erfolgt nach dem Verhältnis der Wohnfläche Ihrer Einheit zur Gesamtwohnfläche des Objekts."
        case .unitCount:
            return "Die Verteilung erfolgt zu gleichen Teilen auf alle Einheiten des Objekts."
        case .personCount:
            return "Die Verteilung erfolgt nach der Anzahl der in den Einheiten des Objekts gemeldeten Personen."
        case .coOwnershipShare:
            return "Die Verteilung erfolgt nach dem Verhältnis der Miteigentumsanteile (MEA) Ihrer Einheit zu den Miteigentumsanteilen des gesamten Objekts."
        }
    }
}
