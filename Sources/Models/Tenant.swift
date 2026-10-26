import Foundation
import SwiftData

/// Anrede für Anschreiben (z.B. Nebenkostenabrechnung) – bestimmt „Herr“/„Frau“.
/// `rawValue` ist ein stabiler, persistierter Schlüssel.
enum Salutation: String, Codable, CaseIterable, Identifiable {
    case male, female, unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .male: return "Herr"
        case .female: return "Frau"
        case .unspecified: return "Keine Angabe"
        }
    }
}

@Model
final class Tenant {
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var phone: String = ""
    var salutationRaw: String = Salutation.unspecified.rawValue
    /// Frühere Anschrift des Mieters (vor Einzug), z.B. für Übergabeprotokoll/Mieterselbstauskunft.
    var previousAddress: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    // Kontodaten (z.B. für die Erstattung eines Guthabens aus der Nebenkostenabrechnung)
    var bankAccountHolder: String = ""
    var iban: String = ""
    var bic: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Tenancy.tenant)
    var tenancies: [Tenancy]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.tenant)
    var documents: [Document]? = []

    init(firstName: String = "", lastName: String = "", email: String = "", phone: String = "", salutation: Salutation = .unspecified, previousAddress: String = "", notes: String = "", bankAccountHolder: String = "", iban: String = "", bic: String = "") {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.salutationRaw = salutation.rawValue
        self.previousAddress = previousAddress
        self.notes = notes
        self.createdAt = .now
        self.bankAccountHolder = bankAccountHolder
        self.iban = iban
        self.bic = bic
    }

    var salutation: Salutation {
        get { Salutation(rawValue: salutationRaw) ?? .unspecified }
        set { salutationRaw = newValue.rawValue }
    }

    var fullName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unbenannter Mieter" : name
    }

    /// Anrede für ein Anschreiben, z.B. „Sehr geehrter Herr Mustermann,“ / „Sehr geehrte Frau
    /// Musterfrau,“. Ohne hinterlegtes Geschlecht ein neutraler Fallback mit vollem Namen.
    var formalSalutation: String {
        switch salutation {
        case .male: return "Sehr geehrter Herr \(lastName),"
        case .female: return "Sehr geehrte Frau \(lastName),"
        case .unspecified: return "Sehr geehrte(r) \(fullName),"
        }
    }

    var activeTenancy: Tenancy? {
        tenancies?.first(where: { $0.isActive })
    }
}
