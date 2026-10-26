import Foundation
import SwiftData

/// Ein vom Nutzer manuell hinzugefügtes Jahr für eine Jahres-Unterreiter-Liste (Zahlungen,
/// Ausgaben, Herstellungskosten, …), auch wenn dafür noch keine Datensätze existieren – damit
/// sich z.B. ein kommendes Jahr schon vorab in der Seitenleiste anlegen lässt.
@Model
final class TrackedYear {
    /// Schlüssel der Liste, z.B. "payments", "expenses", "improvements".
    var category: String = ""
    var year: Int = Calendar.current.component(.year, from: .now)

    init(category: String, year: Int) {
        self.category = category
        self.year = year
    }
}
