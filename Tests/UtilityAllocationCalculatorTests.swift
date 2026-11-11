import XCTest
import SwiftData
@testable import Mietverwaltung

private typealias Unit = Mietverwaltung.Unit

@MainActor
final class UtilityAllocationCalculatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = AppSchema.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @discardableResult
    private func addUnit(_ property: Property, size: Double = 0, share: Double = 0, tenancies: [Tenancy] = []) -> Unit {
        let unit = Unit(name: "E\((property.units ?? []).count + 1)", sizeSquareMeters: size, coOwnershipShare: share)
        unit.property = property
        context.insert(unit)
        for tenancy in tenancies {
            tenancy.unit = unit
            context.insert(tenancy)
        }
        return unit
    }

    private func statement(for property: Property, total: Double, method: AllocationMethod) -> UtilityStatement {
        let statement = UtilityStatement(allocationMethod: method)
        statement.periodStart = date(2025, 1, 1)
        statement.periodEnd = date(2025, 12, 31)
        statement.property = property
        context.insert(statement)
        let item = UtilityCostLineItem(costType: "Heizung", amount: total)
        item.statement = statement
        context.insert(item)
        return statement
    }

    private func fullYearTenancy(occupants: Int = 1) -> Tenancy {
        Tenancy(startDate: date(2024, 1, 1), occupantCount: occupants)
    }

    func testThreeEqualUnitsSumExactlyToTotal() {
        let property = Property(name: "Haus")
        context.insert(property)
        for _ in 0..<3 { addUnit(property, tenancies: [fullYearTenancy()]) }
        let shares = UtilityAllocationCalculator.shares(for: statement(for: property, total: 100, method: .unitCount))

        XCTAssertEqual(shares.count, 3)
        XCTAssertEqual(shares.map(\.allocatedCost).reduce(0, +), 100, accuracy: 0.0001)
        XCTAssertEqual(shares.map(\.allocatedCost).sorted(), [33.33, 33.33, 33.34])
    }

    func testLivingSpaceWeights() {
        let property = Property(name: "Haus")
        context.insert(property)
        addUnit(property, size: 60, tenancies: [fullYearTenancy()])
        addUnit(property, size: 40, tenancies: [fullYearTenancy()])
        let shares = UtilityAllocationCalculator.shares(for: statement(for: property, total: 1_000, method: .livingSpace))
            .sorted { $0.allocatedCost > $1.allocatedCost }

        XCTAssertEqual(shares.map(\.allocatedCost), [600, 400])
        XCTAssertEqual(shares[0].keyDetail, "60/100 m²")
    }

    func testVacancyStaysWithLandlord() {
        let property = Property(name: "Haus")
        context.insert(property)
        addUnit(property, size: 50, tenancies: [fullYearTenancy()])
        addUnit(property, size: 50)
        let shares = UtilityAllocationCalculator.shares(for: statement(for: property, total: 1_000, method: .livingSpace))

        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares[0].allocatedCost, 500)
    }

    func testMidYearMoveInIsProratedByDays() {
        let property = Property(name: "Haus")
        context.insert(property)
        // 2025 hat 365 Tage; Einzug am 2.7. → 183 Tage.
        addUnit(property, size: 100, tenancies: [Tenancy(startDate: date(2025, 7, 2))])
        let shares = UtilityAllocationCalculator.shares(for: statement(for: property, total: 365, method: .livingSpace))

        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares[0].allocatedCost, 183, accuracy: 0.001)
    }

    func testTenantChangeWithinUnitSplitsWithoutDoubleCounting() {
        let property = Property(name: "Haus")
        context.insert(property)
        addUnit(property, size: 100, tenancies: [
            Tenancy(startDate: date(2024, 1, 1), endDate: date(2025, 6, 30)),
            Tenancy(startDate: date(2025, 7, 1))
        ])
        let shares = UtilityAllocationCalculator.shares(for: statement(for: property, total: 3_650, method: .livingSpace))

        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(shares.map(\.allocatedCost).reduce(0, +), 3_650, accuracy: 0.001)
    }

    func testPersonCountUsesOccupantsAtPeriodEnd() {
        let property = Property(name: "Haus")
        context.insert(property)
        addUnit(property, tenancies: [fullYearTenancy(occupants: 3)])
        addUnit(property, tenancies: [fullYearTenancy(occupants: 1)])
        let shares = UtilityAllocationCalculator.shares(for: statement(for: property, total: 400, method: .personCount))
            .sorted { $0.allocatedCost > $1.allocatedCost }

        XCTAssertEqual(shares.map(\.allocatedCost), [300, 100])
        XCTAssertEqual(shares[0].keyDetail, "3/4")
    }

    func testZeroTotalsProduceNoShares() {
        let property = Property(name: "Haus")
        context.insert(property)
        addUnit(property, size: 0, share: 0, tenancies: [fullYearTenancy()])
        XCTAssertTrue(UtilityAllocationCalculator.shares(for: statement(for: property, total: 100, method: .livingSpace)).isEmpty)
        XCTAssertTrue(UtilityAllocationCalculator.shares(for: statement(for: property, total: 100, method: .coOwnershipShare)).isEmpty)
    }

    func testDistributeToCentsKeepsRoundedTotal() {
        XCTAssertEqual(UtilityAllocationCalculator.distributeToCents([]), [])
        XCTAssertEqual(UtilityAllocationCalculator.distributeToCents([10.005, 10.005]).reduce(0, +), 20.01, accuracy: 0.0001)
        let parts: [Double] = Array(repeating: 100.0 / 7, count: 7)
        XCTAssertEqual(UtilityAllocationCalculator.distributeToCents(parts).reduce(0, +), 100, accuracy: 0.0001)
    }

    func testDayCountIgnoresTimeOfDay() {
        let start = date(2025, 1, 1).addingTimeInterval(15 * 3600)
        let end = date(2025, 1, 31).addingTimeInterval(2 * 3600)
        XCTAssertEqual(UtilityAllocationCalculator.dayCount(from: start, to: end), 31)
        XCTAssertEqual(UtilityAllocationCalculator.dayCount(from: end, to: start), 0)
    }
}
