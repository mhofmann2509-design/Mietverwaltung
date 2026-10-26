import Foundation
import SwiftData

/// Eine einzelne Fahrt zum Vermietungsobjekt (Besichtigung, Verwaltung, Instandhaltung) – mit der
/// tatsächlich gefahrenen Strecke (Hin- und Rückfahrt, nicht nur die einfache Entfernung) × km-Satz
/// abziehbar, § 9 Abs. 1 EStG. Keine Entfernungspauschale, da das Objekt keine „erste
/// Tätigkeitsstätte“ ist – gilt nur bei gelegentlichen Besuchen, nicht bei dauerhafter Präsenz.
@Model
final class TravelExpense {
    var date: Date = Date.now
    var purpose: String = ""
    var kilometers: Double = 0 // Hin- und Rückfahrt zusammen
    var ratePerKilometer: Double = 0.30

    var property: Property?

    init(date: Date = .now, purpose: String = "", kilometers: Double = 0, ratePerKilometer: Double = 0.30) {
        self.date = date
        self.purpose = purpose
        self.kilometers = kilometers
        self.ratePerKilometer = ratePerKilometer
    }

    var amount: Double { kilometers * ratePerKilometer }
}
