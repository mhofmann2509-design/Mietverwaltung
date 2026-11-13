import XCTest
import SwiftData
@testable import Mietverwaltung

/// Gemeinsame Basis für Modelltests: jeder Test bekommt einen frischen In-Memory-Container mit dem
/// vollständigen App-Schema – echte App-Daten werden nie berührt.
@MainActor
class ModelTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = AppSchema.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @discardableResult
    func makeProperty(_ name: String = "Objekt", price: Double = 300_000, ancillary: Double = 0, land: Double = 60_000, year: Int? = 1998, transfer: Date? = nil) -> Property {
        let property = Property(name: name, purchasePrice: price, purchaseAncillaryCosts: ancillary, landValue: land, constructionYear: year)
        property.economicTransferDate = transfer
        context.insert(property)
        return property
    }

    @discardableResult
    func makeUnit(_ property: Property, _ name: String = "EG", size: Double = 0) -> Mietverwaltung.Unit {
        let unit = Mietverwaltung.Unit(name: name, sizeSquareMeters: size)
        unit.property = property
        context.insert(unit)
        return unit
    }

    @discardableResult
    func makeTenancy(_ unit: Mietverwaltung.Unit, start: Date, end: Date? = nil, coldRent: Double = 1_000, utility: Double = 0, tenant: Tenant? = nil) -> Tenancy {
        let tenancy = Tenancy(startDate: start, endDate: end, coldRent: coldRent, utilityAdvance: utility)
        tenancy.unit = unit
        tenancy.tenant = tenant
        context.insert(tenancy)
        return tenancy
    }

    @discardableResult
    func makeExpense(_ property: Property, on day: Date, amount: Double, treatment: TaxTreatment = .maintenanceExpense, vat: Double? = 19, category: ExpenseCategory = .maintenance) -> Expense {
        let expense = Expense(date: day, amount: amount, category: category, taxTreatment: treatment)
        expense.vatRatePercent = vat
        expense.property = property
        context.insert(expense)
        return expense
    }
}
