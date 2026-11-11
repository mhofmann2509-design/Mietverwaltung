import Foundation
import SwiftData

/// Eine Mietstufe innerhalb einer Staffelmiete (§ 557a BGB): ab `effectiveDate` gilt `coldRent`
/// als neue Kaltmiete, ohne dass eine gesonderte Mieterhöhungserklärung nötig ist – die Staffeln
/// müssen bereits ziffernmäßig im Mietvertrag vereinbart sein.
@Model
final class RentStep {
    var effectiveDate: Date = Date.now
    var coldRent: Double = 0

    var tenancy: Tenancy?

    init(effectiveDate: Date = .now, coldRent: Double = 0) {
        self.effectiveDate = effectiveDate
        self.coldRent = coldRent
    }
}
