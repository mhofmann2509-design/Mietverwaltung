import Foundation
import SwiftData

@Model
final class Unit {
    var name: String = ""
    var sizeSquareMeters: Double = 0
    var rooms: Double = 0
    var notes: String = ""
    var createdAt: Date = Date.now
    var featureRawValues: [String] = []    // Ausstattung, siehe `UnitFeature`

    /// Miteigentumsanteil (MEA) dieser Einheit, z.B. 55,34 von insgesamt 1.000 Anteilen am Objekt.
    /// Üblicher Umlageschlüssel laut Teilungserklärung – unabhängig von der Wohnfläche.
    var coOwnershipShare: Double = 0

    var property: Property?

    @Relationship(deleteRule: .cascade, inverse: \Tenancy.unit)
    var tenancies: [Tenancy]? = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.unit)
    var expenses: [Expense]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.unit)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \DepreciableAsset.unit)
    var depreciableAssets: [DepreciableAsset]? = []

    init(name: String = "", sizeSquareMeters: Double = 0, rooms: Double = 0, notes: String = "", coOwnershipShare: Double = 0) {
        self.name = name
        self.sizeSquareMeters = sizeSquareMeters
        self.rooms = rooms
        self.notes = notes
        self.coOwnershipShare = coOwnershipShare
        self.createdAt = .now
    }

    /// The tenancy that is currently running (no end date, or end date in the future).
    var activeTenancy: Tenancy? {
        tenancies?.first(where: { $0.isActive })
    }

    var sortedTenancies: [Tenancy] {
        (tenancies ?? []).sorted { $0.startDate > $1.startDate }
    }

    var features: [UnitFeature] {
        get { featureRawValues.compactMap { UnitFeature(rawValue: $0) } }
        set { featureRawValues = newValue.map { $0.rawValue } }
    }
}
