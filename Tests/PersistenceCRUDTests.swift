import XCTest
import SwiftData
@testable import Mietverwaltung

/// Datenbankoperationen und CRUD: Anlegen, Lesen, Ändern, Löschen je Kernmodell sowie die
/// Lösch-Kaskaden zwischen den Modellen.
@MainActor
final class PersistenceCRUDTests: ModelTestCase {

    // MARK: - CRUD je Modell

    func testPropertyCRUD() throws {
        let property = makeProperty("Musterstraße 1")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Property>()).first?.name, "Musterstraße 1")

        property.name = "Musterstraße 1a"
        property.purchasePrice = 310_000
        try context.save()
        let reloaded = try XCTUnwrap(context.fetch(FetchDescriptor<Property>(predicate: #Predicate { $0.name == "Musterstraße 1a" })).first)
        XCTAssertEqual(reloaded.purchasePrice, 310_000)

        context.delete(property)
        try context.save()
        XCTAssertEqual(try count(Property.self), 0)
    }

    func testTenantCRUD() throws {
        let tenant = Tenant(firstName: "Erika", lastName: "Musterfrau", email: "erika@example.com")
        context.insert(tenant)
        try context.save()
        XCTAssertEqual(try count(Tenant.self), 1)

        tenant.lastName = "Beispiel"
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tenant>()).first?.fullName, "Erika Beispiel")

        context.delete(tenant)
        try context.save()
        XCTAssertEqual(try count(Tenant.self), 0)
    }

    func testTenancyAndPaymentCRUD() throws {
        let unit = makeUnit(makeProperty())
        let tenancy = makeTenancy(unit, start: date(2025, 1, 1), coldRent: 900, utility: 150)
        let payment = RentPayment(dueDate: date(2025, 1, 1), coldRentDue: 900, utilityAdvanceDue: 150)
        payment.tenancy = tenancy
        context.insert(payment)
        try context.save()

        XCTAssertEqual(tenancy.payments?.count, 1)
        payment.markPaid(amount: 1_050, date: date(2025, 1, 3))
        try context.save()
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<RentPayment>()).first).isPaid)

        context.delete(payment)
        try context.save()
        XCTAssertEqual(try count(RentPayment.self), 0)
        XCTAssertTrue((tenancy.payments ?? []).isEmpty)
    }

    func testExpenseCRUDAndYearFilter() throws {
        let property = makeProperty()
        let expense = makeExpense(property, on: date(2025, 3, 1), amount: 500)
        try context.save()
        XCTAssertEqual(property.allExpenses(forYear: 2025).count, 1)

        expense.date = date(2024, 12, 31)
        try context.save()
        XCTAssertTrue(property.allExpenses(forYear: 2025).isEmpty)
        XCTAssertEqual(property.allExpenses(forYear: 2024).count, 1)

        context.delete(expense)
        try context.save()
        XCTAssertEqual(try count(Expense.self), 0)
    }

    func testFetchWithPredicateAndSort() throws {
        for (name, price) in [("C", 300_000.0), ("A", 100_000.0), ("B", 200_000.0)] {
            makeProperty(name, price: price)
        }
        try context.save()
        let descriptor = FetchDescriptor<Property>(predicate: #Predicate { $0.purchasePrice >= 150_000 }, sortBy: [SortDescriptor(\.name)])
        XCTAssertEqual(try context.fetch(descriptor).map(\.name), ["B", "C"])
    }

    // MARK: - Dauerhafte Speicherung auf der Platte

    /// Schreibt in eine eigene, temporäre Datenbankdatei (nicht die der App) und liest sie mit einem
    /// neuen Container wieder – prüft, dass Daten inkl. extern gespeicherter Dokument-Daten und
    /// Beziehungen einen Neustart überstehen.
    func testDataSurvivesContainerRestartOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MietverwaltungTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Test.store")
        let schema = AppSchema.schema
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })

        do {
            let writer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
            let writeContext = ModelContext(writer)
            let property = Property(name: "Persistiert", purchasePrice: 250_000)
            writeContext.insert(property)
            let unit = Mietverwaltung.Unit(name: "1. OG")
            unit.property = property
            writeContext.insert(unit)
            let document = Document(title: "Kaufvertrag", fileName: "kv.pdf", fileExtension: "pdf", data: payload)
            document.property = property
            writeContext.insert(document)
            try writeContext.save()
        }

        let reader = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
        let readContext = ModelContext(reader)
        let property = try XCTUnwrap(readContext.fetch(FetchDescriptor<Property>()).first)
        XCTAssertEqual(property.name, "Persistiert")
        XCTAssertEqual(property.units?.map(\.name), ["1. OG"])
        XCTAssertEqual(property.documents?.first?.data, payload)
    }

    // MARK: - Lösch-Kaskaden

    func testDeletingPropertyRemovesAllDependentData() throws {
        let property = makeProperty()
        let unit = makeUnit(property)
        let tenancy = makeTenancy(unit, start: date(2025, 1, 1))
        let payment = RentPayment(dueDate: date(2025, 1, 1), coldRentDue: 1_000)
        payment.tenancy = tenancy
        context.insert(payment)
        let step = RentStep(effectiveDate: date(2026, 1, 1), coldRent: 1_050)
        step.tenancy = tenancy
        context.insert(step)
        makeExpense(property, on: date(2025, 2, 1), amount: 300)
        let statement = UtilityStatement()
        statement.property = property
        context.insert(statement)
        let item = UtilityCostLineItem(costType: "Wasser", amount: 400)
        item.statement = statement
        context.insert(item)
        let tenant = Tenant(firstName: "Max", lastName: "Mieter")
        context.insert(tenant)
        tenancy.tenant = tenant
        try context.save()

        context.delete(property)
        try context.save()

        for countOfType in [try count(Property.self), try count(Mietverwaltung.Unit.self), try count(Tenancy.self), try count(RentPayment.self),
                            try count(RentStep.self), try count(Expense.self), try count(UtilityStatement.self), try count(UtilityCostLineItem.self)] {
            XCTAssertEqual(countOfType, 0)
        }
        XCTAssertEqual(try count(Tenant.self), 1, "Der Mieter als Kontakt bleibt erhalten, nur das Mietverhältnis entfällt.")
    }

    func testDeletingTenancyKeepsTenantAndUnit() throws {
        let unit = makeUnit(makeProperty())
        let tenant = Tenant(firstName: "Max", lastName: "Mieter")
        context.insert(tenant)
        let tenancy = makeTenancy(unit, start: date(2025, 1, 1), tenant: tenant)
        try context.save()

        context.delete(tenancy)
        try context.save()
        XCTAssertEqual(try count(Tenant.self), 1)
        XCTAssertEqual(try count(Mietverwaltung.Unit.self), 1)
        XCTAssertTrue((tenant.tenancies ?? []).isEmpty)
    }

    /// Dokumentiertes Verhalten: Ein Mieter löscht seine Mietverhältnisse mit (die App fragt vorher
    /// mit Auflistung nach).
    func testDeletingTenantCascadesToTenancies() throws {
        let unit = makeUnit(makeProperty())
        let tenant = Tenant(firstName: "Max", lastName: "Mieter")
        context.insert(tenant)
        makeTenancy(unit, start: date(2025, 1, 1), tenant: tenant)
        try context.save()

        context.delete(tenant)
        try context.save()
        XCTAssertEqual(try count(Tenancy.self), 0)
        XCTAssertEqual(try count(Mietverwaltung.Unit.self), 1)
    }

    func testDeletingFolderKeepsDocuments() throws {
        let folder = DocumentFolder(name: "Verträge")
        context.insert(folder)
        let document = Document(title: "Mietvertrag")
        document.folder = folder
        context.insert(document)
        try context.save()

        context.delete(folder)
        try context.save()
        XCTAssertEqual(try count(Document.self), 1)
        XCTAssertNil(document.folder)
    }

    func testDeletingExpenseRemovesItsReceipts() throws {
        let expense = makeExpense(makeProperty(), on: date(2025, 1, 1), amount: 100)
        let receipt = Document(title: "Beleg")
        receipt.expense = expense
        context.insert(receipt)
        try context.save()

        context.delete(expense)
        try context.save()
        XCTAssertEqual(try count(Document.self), 0)
    }
}
