import XCTest
import SwiftData
@testable import Mietverwaltung

/// Regressionstests für Mieten, AfA, 15-%-Grenze und Darlehen – ergänzend zu
/// `TaxCalculationTests`/`TaxCorrectionTests`, mit Fokus auf Randfällen und inneren
/// Konsistenzen (Summen über Jahre, Teilzeiträume, Grenzwerte).
@MainActor
final class CalculationRegressionTests: ModelTestCase {

    // MARK: - Mietberechnungen

    func testColdRentForQuarterAndYearAreConsistent() {
        let property = makeProperty()
        let tenancy = makeTenancy(makeUnit(property), start: date(2025, 1, 1), coldRent: 1_000)
        let quarters = [(1, 3), (4, 6), (7, 9), (10, 12)].map { first, last in
            tenancy.coldRentContribution(from: date(2025, first, 1), to: date(2025, last, Calendar.current.range(of: .day, in: .month, for: date(2025, last, 1))!.count))
        }
        XCTAssertEqual(quarters, [3_000, 3_000, 3_000, 3_000])
        XCTAssertEqual(quarters.reduce(0, +), property.annualColdRent(forYear: 2025), accuracy: 0.01)
    }

    func testColdRentEndsWithTenancy() {
        let property = makeProperty()
        makeTenancy(makeUnit(property), start: date(2025, 1, 1), end: date(2025, 4, 30), coldRent: 1_000)
        XCTAssertEqual(property.annualColdRent(forYear: 2025), 4_000, accuracy: 0.01)
        XCTAssertEqual(property.annualColdRent(forYear: 2026), 0)
    }

    /// Mieterwechsel mitten im Monat: Früher zählten beide Mietverhältnisse den Juni voll
    /// (13.000 €). Tagesgenau ergibt sich exakt eine Jahresmiete.
    func testTenantChangeMidMonthIsNotDoubleCounted() {
        let property = makeProperty()
        let unit = makeUnit(property)
        makeTenancy(unit, start: date(2025, 1, 1), end: date(2025, 6, 15), coldRent: 1_000)
        makeTenancy(unit, start: date(2025, 6, 16), coldRent: 1_000)
        XCTAssertEqual(property.annualColdRent(forYear: 2025), 12_000, accuracy: 0.01)
    }

    /// Unterschiedliche Mieten im Wechselmonat werden je nach Tagen gewichtet.
    func testTenantChangeWeightsDifferentRentsByDays() {
        let property = makeProperty()
        let unit = makeUnit(property)
        let first = makeTenancy(unit, start: date(2025, 1, 1), end: date(2025, 6, 10), coldRent: 900)
        let second = makeTenancy(unit, start: date(2025, 6, 11), coldRent: 1_200)
        let juneStart = date(2025, 6, 1), juneEnd = date(2025, 6, 30)
        XCTAssertEqual(first.coldRentContribution(from: juneStart, to: juneEnd), 900 * 10 / 30, accuracy: 0.01)
        XCTAssertEqual(second.coldRentContribution(from: juneStart, to: juneEnd), 1_200 * 20 / 30, accuracy: 0.01)
        let expected: Double = 4_500 + 300 + 800 + 7_200 // Jan–Mai, Juni anteilig, Juli–Dez
        XCTAssertEqual(property.annualColdRent(forYear: 2025), expected, accuracy: 0.01)
    }

    /// Februar im Schaltjahr: 29 Tage als Nenner, ein ganzer Monat bleibt exakt eine Monatsmiete.
    func testProrationUsesActualDaysOfMonth() {
        let unit = makeUnit(makeProperty())
        let tenancy = makeTenancy(unit, start: date(2024, 2, 15), coldRent: 2_900)
        XCTAssertEqual(tenancy.coldRentContribution(from: date(2024, 2, 1), to: date(2024, 2, 29)), 1_500, accuracy: 0.01)
        XCTAssertEqual(tenancy.coldRentContribution(from: date(2024, 3, 1), to: date(2024, 3, 31)), 2_900, accuracy: 0.01)
    }

    /// Ein Zeitraum, der mitten im Monat beginnt oder endet, wird ebenfalls nur anteilig gezählt.
    func testProrationRespectsRangeBoundaries() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2020, 1, 1), coldRent: 3_000)
        XCTAssertEqual(tenancy.coldRentContribution(from: date(2025, 4, 11), to: date(2025, 4, 20)), 1_000, accuracy: 0.01)
    }

    /// Staffelmiete: Die Stufe gilt weiter ab dem Monat ihres Datums, die Tagesanteile bleiben.
    func testProrationKeepsStaffelStep() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 7, 16), coldRent: 800)
        tenancy.contractType = .staffel
        let step = RentStep(effectiveDate: date(2025, 8, 1), coldRent: 900)
        step.tenancy = tenancy
        context.insert(step)
        XCTAssertEqual(tenancy.coldRentContribution(from: date(2025, 7, 1), to: date(2025, 8, 31)), 800 * 16 / 31 + 900, accuracy: 0.01)
    }

    /// Anlage V: Monate ohne Zahlungseintrag werden tagesgenau geschätzt, ein Wechselmonat zählt
    /// also nicht doppelt – erfasste Zahlungen bleiben unverändert maßgeblich.
    func testReceivedRentEstimateIsProRataInChangeMonth() {
        let unit = makeUnit(makeProperty())
        let first = makeTenancy(unit, start: date(2025, 1, 1), end: date(2025, 6, 15), coldRent: 1_000, utility: 300)
        let second = makeTenancy(unit, start: date(2025, 6, 16), coldRent: 1_000, utility: 300)
        let firstYear = first.receivedRent(inYear: 2025)
        let secondYear = second.receivedRent(inYear: 2025)
        XCTAssertEqual(firstYear.coldRent + secondYear.coldRent, 12_000, accuracy: 0.01)
        XCTAssertEqual(firstYear.utilityAdvances + secondYear.utilityAdvances, 3_600, accuracy: 0.01)
        XCTAssertEqual(firstYear.estimatedMonths, 6)
        XCTAssertEqual(secondYear.estimatedMonths, 7)

        let june = RentPayment(dueDate: date(2025, 6, 1), coldRentDue: 1_000, utilityAdvanceDue: 300)
        june.markPaid(date: date(2025, 6, 3))
        june.tenancy = first
        context.insert(june)
        XCTAssertEqual(first.receivedRent(inYear: 2025).coldRent, 6_000, accuracy: 0.01, "tatsächlich gezahlte Juni-Miete zählt voll")
    }

    func testReceivedRentAssignsLatePaymentToDueMonth() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 12, 1), end: date(2025, 12, 31), coldRent: 1_000)
        let december = RentPayment(dueDate: date(2025, 12, 1), coldRentDue: 1_000)
        december.markPaid(date: date(2026, 1, 5))
        december.tenancy = tenancy
        context.insert(december)
        XCTAssertEqual(tenancy.receivedRent(inYear: 2025).coldRent, 1_000, accuracy: 0.01)
        XCTAssertEqual(tenancy.receivedRent(inYear: 2026).coldRent, 0)
    }

    // MARK: - AfA

    func testDefaultAfaRateBoundaries() {
        XCTAssertEqual(Property(constructionYear: 1924).defaultAfaRatePercent, 2.5)
        XCTAssertEqual(Property(constructionYear: 1925).defaultAfaRatePercent, 2.0)
        XCTAssertEqual(Property(constructionYear: 2022).defaultAfaRatePercent, 2.0)
        XCTAssertEqual(Property(constructionYear: 2023).defaultAfaRatePercent, 3.0)
        XCTAssertEqual(Property().defaultAfaRatePercent, 2.0)
    }

    func testAncillaryCostsSplitBetweenLandAndBuilding() {
        let property = makeProperty(price: 400_000, ancillary: 40_000, land: 100_000)
        XCTAssertEqual(property.landValuePercentage, 0.25, accuracy: 0.0001)
        XCTAssertEqual(property.apportionedLandValue, 110_000, accuracy: 0.01)
        XCTAssertEqual(property.buildingValue, 330_000, accuracy: 0.01)
        XCTAssertEqual(property.apportionedLandValue + property.buildingValue, property.totalAcquisitionCost, accuracy: 0.01)
    }

    func testYearlyAfaSumsExactlyToBuildingValue() {
        let property = makeProperty(ancillary: 30_000, transfer: date(2024, 9, 20))
        var previous = 0.0
        for year in 2024...2080 {
            let cumulative = property.cumulativeBuildingAfA(uptoYear: year)
            XCTAssertEqual(cumulative - previous, property.buildingAfA(forYear: year), accuracy: 0.01, "Jahr \(year)")
            previous = cumulative
        }
        XCTAssertEqual(previous, property.buildingValue, accuracy: 0.01)
        XCTAssertEqual(property.remainingBuildingBookValue(afterYear: 2080), 0, accuracy: 0.01)
    }

    func testManualOverrideWinsEvenOverApplicableAppraisal() {
        let property = makeProperty()
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 1950, valuationDate: date(2025, 1, 1))
        appraisal.property = property
        context.insert(appraisal)
        XCTAssertEqual(property.afaRateSource, .appraisal)
        property.afaRatePercentOverride = 2.5
        XCTAssertEqual(property.afaRateSource, .manual)
        XCTAssertEqual(property.afaRatePercent, 2.5)
    }

    func testTotalAfaCombinesBuildingAndAllAssetTypes() {
        let property = makeProperty(transfer: date(2020, 1, 1))
        let furniture = DepreciableAsset(name: "Küche", category: .furniture, cost: 6_000, usefulLifeYears: 10, placedInServiceDate: date(2025, 1, 1))
        let gwg = DepreciableAsset(name: "Lampe", category: .furniture, cost: 300, usefulLifeYears: 10, placedInServiceDate: date(2025, 5, 1))
        let improvement = DepreciableAsset(name: "Dach", category: .improvement, cost: 10_000, placedInServiceDate: date(2025, 9, 1))
        for asset in [furniture, gwg, improvement] { asset.property = property; context.insert(asset) }

        // Gebäude 240.000 × 2 % = 4.800; Küche 600; GWG 300 sofort; Dach 10.000 × 2 % = 200.
        XCTAssertEqual(property.assetDepreciation(forYear: 2025), 600 + 300 + 200, accuracy: 0.01)
        XCTAssertEqual(property.totalAfa(forYear: 2025), 4_800 + 1_100, accuracy: 0.01)
        XCTAssertEqual(property.assetDepreciation(forYear: 2026), 600 + 200, accuracy: 0.01)
    }

    // MARK: - 15-%-Grenze

    private func thresholdCase(_ property: Property, from start: Date = Date(), years: Int = 3) -> ThreeYearThresholdCase {
        let start = property.economicTransferDate ?? start
        let thresholdCase = ThreeYearThresholdCase(periodStart: start, periodEnd: Calendar.current.date(byAdding: .year, value: years, to: start)!)
        thresholdCase.property = property
        context.insert(thresholdCase)
        return thresholdCase
    }

    func testThresholdStatusBands() {
        // Bemessungsgrundlage 240.000 € → Schwelle 36.000 €; 85 % = 30.600 €.
        let property = makeProperty(transfer: date(2024, 1, 1))
        let thresholdCase = thresholdCase(property)
        let expense = makeExpense(property, on: date(2024, 6, 1), amount: 30_599 * 1.19)
        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain
        XCTAssertEqual(thresholdCase.status, .belowThreshold)

        expense.amount = 30_600 * 1.19
        XCTAssertEqual(thresholdCase.status, .thresholdReached)
        XCTAssertEqual(thresholdCase.remainingToThreshold ?? 0, 5_400, accuracy: 0.01)
        XCTAssertEqual(thresholdCase.utilizationPercent ?? 0, 85, accuracy: 0.001)
    }

    func testManuallyClosedCaseCountsAsCompleted() {
        let property = makeProperty(transfer: date(2024, 1, 1))
        let thresholdCase = thresholdCase(property)
        makeExpense(property, on: date(2024, 6, 1), amount: 1_000)
        thresholdCase.ensureAssessments(context: context)
        XCTAssertEqual(thresholdCase.status, .notConclusivelyCheckable)
        thresholdCase.manuallyClosed = true
        XCTAssertEqual(thresholdCase.status, .completed)
    }

    func testZeroBuildingValueIsNotCheckable() {
        let property = makeProperty(price: 0, land: 0, transfer: date(2024, 1, 1))
        XCTAssertEqual(thresholdCase(property).status, .notConclusivelyCheckable)
    }

    func testCandidatesIncludeUnitExpensesOnceAndStartDay() {
        let property = makeProperty(transfer: date(2024, 1, 15))
        let thresholdCase = thresholdCase(property)
        let unit = makeUnit(property)
        let onBothLinks = makeExpense(property, on: date(2024, 1, 15, hour: 9), amount: 1_190)
        onBothLinks.unit = unit
        let dayBefore = makeExpense(property, on: date(2024, 1, 14), amount: 1_190)
        makeExpense(property, on: date(2024, 3, 1), amount: 500, treatment: .otherDeductible, category: .insurance)

        let candidates = thresholdCase.candidateExpenses
        XCTAssertEqual(candidates.map(\.persistentModelID), [onBothLinks.persistentModelID])
        XCTAssertFalse(candidates.contains(dayBefore))
    }

    // MARK: - Darlehen

    func testAnnuityAndNoLoanCases() {
        let property = makeProperty()
        XCTAssertNil(property.loanBreakdown(forYear: 2025), "Ohne Finanzierung kein Ergebnis")
        property.loanAmount = 200_000
        property.interestRatePercent = 3.5
        property.initialRepaymentRatePercent = 2
        XCTAssertEqual(property.annualAnnuity, 11_000, accuracy: 0.01)
        XCTAssertNil(property.loanBreakdown(forYear: 2025), "Ohne Startdatum kein Tilgungsplan")
        property.loanStartDate = date(2025, 1, 1)
        XCTAssertNil(property.loanBreakdown(forYear: 2024), "Vor Darlehensbeginn kein Ergebnis")
        XCTAssertEqual(property.annuity(forYear: 2025), 11_000, accuracy: 0.01)
    }

    func testLoanIsFullyRepaidAndThenStops() throws {
        let property = makeProperty()
        property.loanAmount = 100_000
        property.interestRatePercent = 5
        property.initialRepaymentRatePercent = 15
        property.loanStartDate = date(2025, 1, 1)

        var principalSum = 0.0
        var previousInterest = Double.infinity
        var year = 2025
        while let breakdown = property.loanBreakdown(forYear: year), breakdown.principal > 0 {
            XCTAssertLessThan(breakdown.interest, previousInterest, "Zinsanteil sinkt jährlich")
            previousInterest = breakdown.interest
            principalSum += breakdown.principal
            year += 1
        }
        XCTAssertEqual(principalSum, 100_000, accuracy: 0.01)
        let afterPayoff = try XCTUnwrap(property.loanBreakdown(forYear: year))
        XCTAssertEqual(afterPayoff.remainingBalance, 0)
        XCTAssertEqual(property.annuity(forYear: year), 0)
    }

    func testInterestCountsAsWerbungskostenButPrincipalDoesNot() {
        let property = makeProperty(transfer: date(2025, 1, 1))
        property.loanAmount = 100_000
        property.interestRatePercent = 4
        property.initialRepaymentRatePercent = 3
        property.loanStartDate = date(2025, 1, 1)
        XCTAssertEqual(property.werbungskosten(forYear: 2025), 4_000, accuracy: 0.01)
    }
}
