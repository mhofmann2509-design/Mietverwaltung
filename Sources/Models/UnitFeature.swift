import Foundation

/// Ausstattungsmerkmale einer Einheit, z.B. zur Anzeige als Badges.
/// - Note: `rawValue` ist ein stabiler, persistierter Schlüssel, siehe `label`.
enum UnitFeature: String, Codable, CaseIterable, Identifiable, Hashable {
    case balcony
    case fittedKitchen
    case cellar
    case parking
    case elevator
    case underfloorHeating
    case guestToilet
    case furnished
    case renovated
    case washerConnection

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balcony: return "Balkon/Terrasse"
        case .fittedKitchen: return "Einbauküche"
        case .cellar: return "Keller"
        case .parking: return "Stellplatz/Garage"
        case .elevator: return "Aufzug"
        case .underfloorHeating: return "Fußbodenheizung"
        case .guestToilet: return "Gäste-WC"
        case .furnished: return "Möbliert"
        case .renovated: return "Renoviert"
        case .washerConnection: return "Waschmaschinenanschluss"
        }
    }

    var systemImage: String {
        switch self {
        case .balcony: return "sun.max"
        case .fittedKitchen: return "fork.knife"
        case .cellar: return "shippingbox"
        case .parking: return "car.fill"
        case .elevator: return "arrow.up.arrow.down.circle"
        case .underfloorHeating: return "flame.fill"
        case .guestToilet: return "toilet"
        case .furnished: return "sofa"
        case .renovated: return "paintbrush.fill"
        case .washerConnection: return "washer"
        }
    }
}
