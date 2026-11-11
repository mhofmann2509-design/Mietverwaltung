import Foundation
import SwiftData

/// Das Vermieterprofil – als Einzelsatz hinterlegt (unabhängig von den einzelnen Immobilien),
/// da in der Regel ein und derselbe Vermieter für alle Objekte zuständig ist. Liefert die
/// Absender-/Kontodaten sowie den Grenzsteuersatz zur groben Abschätzung der steuerlichen
/// Belastung aus dem steuerlichen Ergebnis aller Immobilien.
@Model
final class Landlord {
    var name: String = ""
    var street: String = ""
    var zipCode: String = ""
    var city: String = ""
    var email: String = ""

    var bankAccountHolder: String = ""
    var iban: String = ""
    var bic: String = ""

    /// Persönlicher Grenzsteuersatz in Prozent (inkl. Soli/Kirchensteuer, falls gewünscht) –
    /// Grundlage für die geschätzte Steuerlast aus dem steuerlichen Ergebnis der Immobilien.
    var marginalTaxRatePercent: Double = 42

    /// Steuerliche Vertretung durch einen Steuerberater – bestimmt, welche gesetzliche
    /// Abgabefrist (§ 149 AO) für die Steuererklärung angezeigt wird.
    var usesTaxAdvisor: Bool = false

    init(name: String = "", street: String = "", zipCode: String = "", city: String = "", email: String = "", bankAccountHolder: String = "", iban: String = "", bic: String = "", marginalTaxRatePercent: Double = 42, usesTaxAdvisor: Bool = false) {
        self.name = name
        self.street = street
        self.zipCode = zipCode
        self.city = city
        self.email = email
        self.bankAccountHolder = bankAccountHolder
        self.iban = iban
        self.bic = bic
        self.marginalTaxRatePercent = marginalTaxRatePercent
        self.usesTaxAdvisor = usesTaxAdvisor
    }

    var address: String {
        "\(street), \(zipCode) \(city)"
    }
}
