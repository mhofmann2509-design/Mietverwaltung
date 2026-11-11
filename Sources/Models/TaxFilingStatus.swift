import Foundation
import SwiftData

/// Verfolgt je Steuerjahr den Abgabestatus der Steuererklärung – als Einzelsatz pro Jahr
/// unabhängig von einzelnen Immobilien, da die Steuererklärung das gesamte Vermieterprofil
/// betrifft. Die gesetzliche Regelabgabefrist (§ 149 AO) wird daraus berechnet,
/// kann aber bei Bedarf überschrieben werden (`deadlineOverride`), z.B. bei einer individuell
/// gewährten Fristverlängerung.
@Model
final class TaxFilingStatus {
    var taxYear: Int = Calendar.current.component(.year, from: .now) - 1
    var submittedAt: Date?
    var deadlineOverride: Date?

    init(taxYear: Int, submittedAt: Date? = nil, deadlineOverride: Date? = nil) {
        self.taxYear = taxYear
        self.submittedAt = submittedAt
        self.deadlineOverride = deadlineOverride
    }

    var isSubmitted: Bool { submittedAt != nil }

    /// Gesetzliche Regelabgabefrist nach § 149 AO: ohne steuerliche Beratung der 31. Juli des
    /// Folgejahres; mit Steuerberater regulär der letzte Tag des Februars zwei Jahre später
    /// (dauerhafte Regel seit der Reform 2018). Für die beratene Frist gab es für die
    /// Steuerjahre ca. 2020–2025 mehrfach befristete, coronabedingte Fristverlängerungen – hier
    /// wird bewusst nur die dauerhafte Regelfrist berechnet, siehe `deadlineCaveat`.
    func legalDeadline(usesTaxAdvisor: Bool) -> Date {
        let calendar = Calendar.current
        guard usesTaxAdvisor else {
            return calendar.date(from: DateComponents(year: taxYear + 1, month: 7, day: 31)) ?? .now
        }
        guard let firstOfMarch = calendar.date(from: DateComponents(year: taxYear + 2, month: 3, day: 1)),
              let lastDayOfFebruary = calendar.date(byAdding: .day, value: -1, to: firstOfMarch) else {
            return .now
        }
        return lastDayOfFebruary
    }

    /// Tatsächlich anzuzeigende Frist: `deadlineOverride`, falls gesetzt, sonst die berechnete
    /// gesetzliche Regelfrist.
    func effectiveDeadline(usesTaxAdvisor: Bool) -> Date {
        deadlineOverride ?? legalDeadline(usesTaxAdvisor: usesTaxAdvisor)
    }

    static let deadlineCaveat = "Berechnet ist die dauerhafte gesetzliche Regelfrist nach § 149 AO. Bei steuerlicher Beratung gab es für die Steuerjahre ca. 2020–2025 mehrfach befristete, coronabedingte Fristverlängerungen – im Zweifel die tatsächliche Frist beim Steuerberater erfragen und bei Abweichung oben manuell überschreiben."
}
