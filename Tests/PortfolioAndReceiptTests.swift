import XCTest
import SwiftData
@testable import Mietverwaltung

private typealias Unit = Mietverwaltung.Unit

@MainActor
final class PortfolioMetricsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = AppSchema.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func property(price: Double, ancillary: Double = 0, monthlyRent: Double, expenses: Double = 0) -> Property {
        let property = Property(name: "P", purchasePrice: price, purchaseAncillaryCosts: ancillary)
        context.insert(property)
        let unit = Unit(name: "EG")
        unit.property = property
        context.insert(unit)
        let tenancy = Tenancy(startDate: Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!, coldRent: monthlyRent)
        tenancy.unit = unit
        context.insert(tenancy)
        if expenses > 0 {
            let expense = Expense(date: Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 1))!, amount: expenses, taxTreatment: .maintenanceExpense)
            expense.property = property
            context.insert(expense)
        }
        return property
    }

    func testGrossYieldIsWeightedByPurchasePriceNotAveraged() throws {
        let properties = [property(price: 200_000, monthlyRent: 10_000.0 / 12), property(price: 100_000, monthlyRent: 2_000.0 / 12)]
        let metrics = PortfolioMetrics(properties: properties, year: 2025, marginalTaxRatePercent: nil)

        // 12.000 € / 300.000 € = 4 % (nicht (5 % + 2 %) / 2 = 3,5 %).
        XCTAssertEqual(try XCTUnwrap(metrics.grossYieldPercent), 4, accuracy: 0.0001)
        XCTAssertEqual(metrics.totalRent, 12_000, accuracy: 0.01)
    }

    func testNetYieldUsesInvestmentIncludingAncillaryCosts() throws {
        let properties = [property(price: 180_000, ancillary: 20_000, monthlyRent: 1_000, expenses: 2_000)]
        let metrics = PortfolioMetrics(properties: properties, year: 2025, marginalTaxRatePercent: nil)

        // (12.000 − 2.000) / 200.000 = 5 %.
        XCTAssertEqual(try XCTUnwrap(metrics.netYieldPercent), 5, accuracy: 0.0001)
    }

    func testPropertiesWithoutPriceAreExcludedFromYield() {
        let metrics = PortfolioMetrics(properties: [property(price: 0, monthlyRent: 500)], year: 2025, marginalTaxRatePercent: nil)
        XCTAssertNil(metrics.grossYieldPercent)
        XCTAssertNil(metrics.netYieldPercent)
    }

    func testTaxBurdenNeedsLandlordAndIgnoresLosses() {
        let profitable = PortfolioMetrics(properties: [property(price: 100_000, monthlyRent: 2_000)], year: 2025, marginalTaxRatePercent: 42)
        XCTAssertGreaterThan(profitable.taxableResult, 0)
        XCTAssertEqual(profitable.estimatedTaxBurden, profitable.taxableResult * 0.42, accuracy: 0.01)
        XCTAssertEqual(profitable.cashFlowAfterTax, profitable.freeCashFlow - profitable.estimatedTaxBurden, accuracy: 0.01)

        let withoutLandlord = PortfolioMetrics(properties: profitable.properties, year: 2025, marginalTaxRatePercent: nil)
        XCTAssertEqual(withoutLandlord.estimatedTaxBurden, 0)

        let loss = PortfolioMetrics(properties: [property(price: 100_000, monthlyRent: 10, expenses: 50_000)], year: 2025, marginalTaxRatePercent: 42)
        XCTAssertLessThan(loss.taxableResult, 0)
        XCTAssertEqual(loss.estimatedTaxBurden, 0)
    }

    func testEmptyPortfolio() {
        let metrics = PortfolioMetrics(properties: [], year: 2025, marginalTaxRatePercent: 42)
        XCTAssertNil(metrics.grossYieldPercent)
        XCTAssertEqual(metrics.totalRent, 0)
        XCTAssertEqual(metrics.estimatedTaxBurden, 0)
    }
}

final class ReceiptTextExtractorTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testPrefersAmountOnTotalLine() {
        let guess = ReceiptTextExtractor.parse(lines: ["Baumarkt GmbH", "Schrauben 3,99", "Bohrmaschine 2.499,00", "Summe 1.234,56 €", "Datum 05.03.24"])
        XCTAssertEqual(guess.title, "Baumarkt GmbH")
        XCTAssertEqual(guess.amount, 1234.56)
        XCTAssertEqual(guess.date, date(2024, 3, 5))
    }

    func testFallsBackToLargestAmountWithoutKeyword() {
        let guess = ReceiptTextExtractor.parse(lines: ["Handwerker", "Material 120,00", "Arbeit 1 380,50"])
        XCTAssertEqual(guess.amount, 1380.5)
    }

    func testRejectsImpossibleAndFutureDates() {
        let guess = ReceiptTextExtractor.parse(lines: ["Firma", "31.02.24", "01.01.2099", "15.06.2023"])
        XCTAssertEqual(guess.date, date(2023, 6, 15))
    }

    func testEmptyInput() {
        let guess = ReceiptTextExtractor.parse(lines: [])
        XCTAssertNil(guess.title)
        XCTAssertNil(guess.amount)
        XCTAssertNil(guess.date)
    }
}
