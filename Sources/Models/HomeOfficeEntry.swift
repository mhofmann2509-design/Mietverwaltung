import Foundation
import SwiftData

/// Homeoffice-Pauschale für die Verwaltung einer Immobilie (§ 4 Abs. 5 S. 1 Nr. 6c i.V.m. § 9
/// Abs. 5 EStG): Tagessatz × erfasste Tage, ein Eintrag je Immobilie und Steuerjahr. Die
/// Jahresdeckelung (210 Tage / 1.260 €) gilt pro Person über ALLE Immobilien hinweg und wird daher
/// nicht hier, sondern in `HomeOfficeAllocation` objektübergreifend berechnet.
@Model
final class HomeOfficeEntry {
    var taxYear: Int = Calendar.current.component(.year, from: Date.now)
    var days: Int = 0
    var dailyRate: Double = 6.0

    var property: Property?

    init(taxYear: Int, days: Int = 0, dailyRate: Double = 6.0) {
        self.taxYear = taxYear
        self.days = days
        self.dailyRate = dailyRate
    }
}
