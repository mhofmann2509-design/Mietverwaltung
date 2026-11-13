import XCTest
import SwiftData
@testable import Mietverwaltung

/// Beziehungen zwischen Immobilien, Einheiten und Mietern sowie die Mietvertragslogik.
@MainActor
final class RelationshipAndTenancyTests: ModelTestCase {

    // MARK: - Immobilie ↔ Einheit ↔ Mietverhältnis ↔ Mieter

    func testInverseRelationshipsAreMaintained() throws {
        let property = makeProperty()
        let unit = makeUnit(property, size: 70)
        let tenant = Tenant(firstName: "Laura", lastName: "Fischer")
        context.insert(tenant)
        let tenancy = makeTenancy(unit, start: date(2024, 1, 1), tenant: tenant)
        try context.save()

        XCTAssertEqual(property.units?.first, unit)
        XCTAssertEqual(unit.tenancies?.first, tenancy)
        XCTAssertEqual(tenant.tenancies?.first, tenancy)
        XCTAssertEqual(tenancy.unit?.property, property)
    }

    func testTenantCanRentInSeveralPropertiesOverTime() {
        let tenant = Tenant(firstName: "Jonas", lastName: "Keller")
        context.insert(tenant)
        let old = makeTenancy(makeUnit(makeProperty("A")), start: date(2018, 1, 1), end: date(2022, 12, 31), tenant: tenant)
        let current = makeTenancy(makeUnit(makeProperty("B")), start: date(2023, 1, 1), tenant: tenant)

        XCTAssertEqual(tenant.tenancies?.count, 2)
        XCTAssertEqual(tenant.activeTenancy, current)
        XCTAssertFalse(old.isActive)
    }

    func testOccupancyCountsAndUnitTotals() {
        let property = makeProperty()
        let occupied = makeUnit(property, "EG", size: 60)
        occupied.coOwnershipShare = 120
        let vacant = makeUnit(property, "OG", size: 40)
        vacant.coOwnershipShare = 80
        makeTenancy(occupied, start: date(2020, 1, 1))
        makeTenancy(vacant, start: date(2019, 1, 1), end: date(2020, 6, 30))

        XCTAssertEqual(property.unitCount, 2)
        XCTAssertEqual(property.occupiedUnitCount, 1)
        XCTAssertEqual(property.totalSizeSquareMeters, 100)
        XCTAssertEqual(property.totalCoOwnershipShare, 200)
        XCTAssertNotNil(occupied.activeTenancy)
        XCTAssertNil(vacant.activeTenancy)
    }

    func testSortedTenanciesNewestFirst() {
        let unit = makeUnit(makeProperty())
        makeTenancy(unit, start: date(2015, 1, 1), end: date(2018, 12, 31))
        makeTenancy(unit, start: date(2022, 1, 1))
        makeTenancy(unit, start: date(2019, 1, 1), end: date(2021, 12, 31))
        XCTAssertEqual(unit.sortedTenancies.map { Calendar.current.component(.year, from: $0.startDate) }, [2022, 2019, 2015])
    }

    func testDocumentResolvesPropertyThroughAnyLink() {
        let property = makeProperty()
        let unit = makeUnit(property)
        let tenancy = makeTenancy(unit, start: date(2024, 1, 1))
        let expense = makeExpense(property, on: date(2024, 2, 1), amount: 100)

        let viaTenancy = Document(title: "Mietvertrag")
        viaTenancy.tenancy = tenancy
        let viaExpense = Document(title: "Rechnung")
        viaExpense.expense = expense
        let unlinked = Document(title: "Lose")
        [viaTenancy, viaExpense, unlinked].forEach(context.insert)

        XCTAssertEqual(viaTenancy.resolvedProperty, property)
        XCTAssertEqual(viaExpense.resolvedProperty, property)
        XCTAssertNil(unlinked.resolvedProperty)
        XCTAssertEqual(viaTenancy.linkedToDescription, "Mietvertrag · EG")
    }

    func testDocumentCategoryDerivation() {
        let statement = UtilityStatement()
        context.insert(statement)
        let folder = DocumentFolder(name: "Rechnungen", category: .invoicesReceipts)
        context.insert(folder)

        let fromStatement = Document(title: "NK")
        fromStatement.utilityStatement = statement
        let fromFolder = Document(title: "Im Ordner")
        fromFolder.folder = folder
        let explicit = Document(title: "Explizit")
        explicit.category = .utilityStatements
        explicit.folder = folder
        [fromStatement, fromFolder, explicit].forEach(context.insert)

        XCTAssertEqual(fromStatement.category, .utilityStatements)
        XCTAssertEqual(fromFolder.category, .invoicesReceipts)
        XCTAssertEqual(explicit.category, .utilityStatements, "Ein explizit gesetzter Reiter hat Vorrang vor dem Ordner.")
        XCTAssertEqual(Document(title: "Nichts").category, .propertyDocuments)
    }

    // MARK: - Mieter

    func testTenantNamesAndSalutations() {
        let male = Tenant(firstName: "Max", lastName: "Mustermann", salutation: .male)
        let female = Tenant(firstName: "Erika", lastName: "Musterfrau", salutation: .female)
        let unknown = Tenant(firstName: "Alex", lastName: "Beispiel")
        XCTAssertEqual(male.formalSalutation, "Sehr geehrter Herr Mustermann,")
        XCTAssertEqual(female.formalSalutation, "Sehr geehrte Frau Musterfrau,")
        XCTAssertEqual(unknown.formalSalutation, "Sehr geehrte(r) Alex Beispiel,")
        XCTAssertEqual(Tenant().fullName, "Unbenannter Mieter")
    }

    // MARK: - Mietvertragslogik

    func testIsRunningIncludesStartAndEndDay() {
        let tenancy = Tenancy(startDate: date(2025, 3, 1), endDate: date(2025, 8, 31))
        XCTAssertFalse(tenancy.isRunning(on: date(2025, 2, 28, hour: 23)))
        XCTAssertTrue(tenancy.isRunning(on: date(2025, 3, 1)))
        XCTAssertTrue(tenancy.isRunning(on: date(2025, 8, 31, hour: 22)))
        XCTAssertFalse(tenancy.isRunning(on: date(2025, 9, 1)))
    }

    func testOpenEndedTenancyRunsIndefinitely() {
        let tenancy = Tenancy(startDate: date(2020, 1, 1))
        XCTAssertTrue(tenancy.isRunning(on: date(2099, 1, 1)))
        XCTAssertTrue(tenancy.isActive)
    }

    func testPaymentLookupByMonth() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 1, 1))
        let march = RentPayment(dueDate: date(2025, 3, 1), coldRentDue: 1_000)
        march.tenancy = tenancy
        context.insert(march)
        XCTAssertEqual(tenancy.payment(forMonthContaining: date(2025, 3, 25)), march)
        XCTAssertNil(tenancy.payment(forMonthContaining: date(2025, 4, 1)))
    }

    func testUtilityAdvancesPaidSplitsPartialPayments() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 1, 1), coldRent: 800, utility: 200)
        let full = RentPayment(dueDate: date(2025, 1, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        full.markPaid(date: date(2025, 1, 2))
        let partial = RentPayment(dueDate: date(2025, 2, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        partial.markPaid(amount: 500, date: date(2025, 2, 5))
        let open = RentPayment(dueDate: date(2025, 3, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        for payment in [full, partial, open] { payment.tenancy = tenancy; context.insert(payment) }

        XCTAssertEqual(tenancy.utilityAdvancesPaid(from: date(2025, 1, 1), to: date(2025, 12, 31)), 200 + 100, accuracy: 0.01)
    }

    func testActiveDaysAcrossLeapYearAndPartialPeriods() {
        let tenancy = Tenancy(startDate: date(2024, 2, 15), endDate: date(2024, 3, 10))
        XCTAssertEqual(tenancy.activeDays(inYear: 2024), 25, "15.–29.02. (Schaltjahr) = 15 Tage, 01.–10.03. = 10 Tage")
        XCTAssertEqual(tenancy.activeDays(inYear: 2023), 0)
        XCTAssertEqual(Tenancy(startDate: date(2020, 1, 1)).activeDays(inYear: 2024), 366)
    }

    func testArrearsWithOverpaymentBecomesCredit() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 1, 1), coldRent: 800, utility: 200)
        let payment = RentPayment(dueDate: date(2025, 1, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        payment.markPaid(amount: 1_100, date: date(2025, 1, 2))
        payment.tenancy = tenancy
        context.insert(payment)
        XCTAssertEqual(tenancy.arrearsBalance(upTo: date(2025, 1, 31)), -100, accuracy: 0.01)
    }

    func testArrearsIgnoreMonthsBeforeStartAndAfterEnd() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 3, 1), end: date(2025, 4, 30), coldRent: 500)
        XCTAssertEqual(tenancy.arrearsBalance(upTo: date(2025, 12, 31)), 1_000, accuracy: 0.01)
    }

    func testRentIncreaseAdvisorRespectsLastIncrease() {
        let tenancy = Tenancy(startDate: date(2020, 1, 1), coldRent: 800)
        tenancy.lastRentIncreaseDate = date(2024, 6, 1)
        let advice = RentIncreaseAdvisor.advice(for: tenancy, today: date(2025, 1, 1))
        XCTAssertEqual(advice.nextPossibleDate, Calendar.current.date(byAdding: .month, value: 15, to: date(2024, 6, 1)))
    }
}
