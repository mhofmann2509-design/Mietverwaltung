import XCTest
import SwiftData
@testable import Mietverwaltung

/// WEG-Verwaltung (Wirtschaftsplan, Nebenkostenabrechnung, Versand, Eigentümerversammlung) und die
/// testbaren Dashboard-Auswertungen.
@MainActor
final class WEGAndDashboardTests: ModelTestCase {

    // MARK: - Wirtschaftsplan

    func testWirtschaftsplanTotals() {
        let plan = WirtschaftsplanStatement(year: 2026, propertyTaxAmount: 250)
        context.insert(plan)
        for (type, amount, apportionable) in [("Heizung", 1_200.0, true), ("Hausmeister", 400.0, true), ("Verwaltergebühr", 360.0, false), ("Instandhaltungsrücklage", 900.0, false)] {
            let item = WirtschaftsplanLineItem(costType: type, amount: amount, isApportionable: apportionable)
            item.statement = plan
            context.insert(item)
        }
        XCTAssertEqual(plan.lineItemsTotal, 2_860)
        XCTAssertEqual(plan.apportionableLineItemsTotal, 1_600)
        XCTAssertEqual(plan.nonApportionableLineItemsTotal, 1_260)
        XCTAssertEqual(plan.totalApportionableCosts, 1_850)
        XCTAssertEqual(plan.totalCosts, 3_110)
    }

    func testDeletingWirtschaftsplanRemovesLineItems() throws {
        let property = makeProperty()
        let plan = WirtschaftsplanStatement(year: 2026)
        plan.property = property
        context.insert(plan)
        let item = WirtschaftsplanLineItem(costType: "Heizung", amount: 100)
        item.statement = plan
        context.insert(item)
        try context.save()

        context.delete(plan)
        try context.save()
        XCTAssertEqual(try count(WirtschaftsplanLineItem.self), 0)
        XCTAssertTrue((property.wirtschaftsplaene ?? []).isEmpty)
    }

    // MARK: - Nebenkostenabrechnung der Hausverwaltung

    func testUtilityStatementTotalsAndYearFromPeriodEnd() {
        let statement = UtilityStatement(propertyTaxAmount: 150)
        statement.periodStart = date(2024, 7, 1)
        statement.periodEnd = date(2025, 6, 30)
        context.insert(statement)
        for (type, amount, apportionable) in [("Wasser", 600.0, true), ("Bankgebühren", 40.0, false)] {
            let item = UtilityCostLineItem(costType: type, amount: amount, isApportionable: apportionable)
            item.statement = statement
            context.insert(item)
        }
        XCTAssertEqual(statement.year, 2025, "Abweichendes Wirtschaftsjahr: maßgeblich ist das Jahr des Zeitraumendes")
        XCTAssertEqual(statement.totalApportionableCosts, 750)
        XCTAssertEqual(statement.nonApportionableLineItemsTotal, 40)
        XCTAssertEqual(statement.totalCosts, 790)
    }

    func testDispatchMarkingAndCascade() throws {
        let unit = makeUnit(makeProperty())
        let tenancy = makeTenancy(unit, start: date(2024, 1, 1))
        let statement = UtilityStatement()
        context.insert(statement)
        let dispatch = UtilityStatementDispatch(sentDate: date(2025, 3, 1))
        dispatch.statement = statement
        dispatch.tenancy = tenancy
        context.insert(dispatch)
        try context.save()

        XCTAssertEqual(statement.dispatches?.count, 1)
        XCTAssertEqual(tenancy.statementDispatches?.count, 1)

        context.delete(statement)
        try context.save()
        XCTAssertEqual(try count(UtilityStatementDispatch.self), 0)
        XCTAssertEqual(try count(Tenancy.self), 1)
    }

    func testCostsCheckedAgainstPlanVsActual() {
        let property = makeProperty()
        let plan = WirtschaftsplanStatement(year: 2025)
        plan.property = property
        context.insert(plan)
        let planned = WirtschaftsplanLineItem(costType: "Heizung", amount: 1_000)
        planned.statement = plan
        context.insert(planned)
        let statement = UtilityStatement()
        statement.periodStart = date(2025, 1, 1)
        statement.periodEnd = date(2025, 12, 31)
        statement.property = property
        context.insert(statement)
        let actual = UtilityCostLineItem(costType: "Heizung", amount: 1_150)
        actual.statement = statement
        context.insert(actual)

        let planForYear = property.wirtschaftsplaene?.first { $0.year == 2025 }
        let statementForYear = property.utilityStatements?.first { $0.year == 2025 }
        XCTAssertEqual((statementForYear?.lineItemsTotal ?? 0) - (planForYear?.lineItemsTotal ?? 0), 150)
        XCTAssertEqual(property.apportionableUtilityCosts(forYear: 2025), 1_150)
    }

    // MARK: - Eigentümerversammlung

    func testOwnersMeetingBelongsToPropertyAndIsDeletedWithIt() throws {
        let property = makeProperty()
        let meeting = OwnersMeetingEvent(title: "ETV 2026", date: date(2026, 5, 20), location: "Gemeindesaal")
        meeting.property = property
        context.insert(meeting)
        try context.save()
        XCTAssertEqual(property.ownersMeetings?.first?.title, "ETV 2026")

        context.delete(property)
        try context.save()
        XCTAssertEqual(try count(OwnersMeetingEvent.self), 0)
    }

    // MARK: - Dashboard-Auswertungen (testbarer Teil)

    func testMonthlyCashFlowsSumToYearlyCashFlow() {
        let property = makeProperty()
        makeTenancy(makeUnit(property), start: date(2024, 1, 1), coldRent: 1_000)
        makeExpense(property, on: date(2025, 3, 10), amount: 1_200)
        property.loanAmount = 100_000
        property.interestRatePercent = 4
        property.initialRepaymentRatePercent = 2
        property.loanStartDate = date(2024, 1, 1)

        let monthly = (1...12).reduce(0.0) { $0 + property.freeCashFlow(forMonth: date(2025, $1, 15)) }
        XCTAssertEqual(monthly, property.freeCashFlow(forYear: 2025), accuracy: 0.01)
    }

    func testFreeCashFlowIgnoresFinancingExpensesButOperativeSubtractsUtilities() {
        let property = makeProperty()
        makeTenancy(makeUnit(property), start: date(2024, 1, 1), coldRent: 1_000)
        makeExpense(property, on: date(2025, 2, 1), amount: 999, treatment: .otherDeductible, category: .financing)
        let statement = UtilityStatement()
        statement.periodStart = date(2025, 1, 1)
        statement.periodEnd = date(2025, 12, 31)
        statement.property = property
        context.insert(statement)
        let item = UtilityCostLineItem(costType: "Müll", amount: 300)
        item.statement = statement
        context.insert(item)

        XCTAssertEqual(property.freeCashFlow(forYear: 2025), 12_000, accuracy: 0.01)
        XCTAssertEqual(property.operativeCashFlow(forYear: 2025), 11_700, accuracy: 0.01)
    }

    func testAvailableTaxYearsCoverDataAndCurrentYear() {
        let property = makeProperty()
        makeTenancy(makeUnit(property), start: date(2019, 4, 1), end: date(2021, 3, 31))
        makeExpense(property, on: date(2017, 6, 1), amount: 100)
        let years = property.availableTaxYears
        let currentYear = Calendar.current.component(.year, from: .now)
        for expected in [2017, 2019, 2021, currentYear] {
            XCTAssertTrue(years.contains(expected), "\(expected)")
        }
        XCTAssertEqual(years, years.sorted(by: >))
    }

    func testPortfolioMetricsMatchSumOfProperties() {
        let first = makeProperty("A", transfer: date(2020, 1, 1))
        let second = makeProperty("B", price: 200_000, land: 50_000, transfer: date(2020, 1, 1))
        makeTenancy(makeUnit(first), start: date(2020, 1, 1), coldRent: 1_200)
        makeTenancy(makeUnit(second), start: date(2020, 1, 1), coldRent: 800)
        let metrics = PortfolioMetrics(properties: [first, second], year: 2025, marginalTaxRatePercent: 42)

        XCTAssertEqual(metrics.totalRent, first.annualColdRent(forYear: 2025) + second.annualColdRent(forYear: 2025), accuracy: 0.01)
        XCTAssertEqual(metrics.totalAfa, first.totalAfa(forYear: 2025) + second.totalAfa(forYear: 2025), accuracy: 0.01)
        XCTAssertEqual(metrics.taxableResult, first.estimatedTaxableResult(forYear: 2025) + second.estimatedTaxableResult(forYear: 2025), accuracy: 0.01)
    }
}
