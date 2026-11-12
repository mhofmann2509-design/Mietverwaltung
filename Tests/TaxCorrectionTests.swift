import XCTest
import SwiftData
@testable import Mietverwaltung

private typealias Unit = Mietverwaltung.Unit

/// Testfälle aus der steuerlichen Prüfung (T1–T19) und den daraus folgenden Korrekturen.
/// Grundfall: Kaufpreis 300.000 €, Nebenkosten 30.000 €, Bodenwert 60.000 €, Baujahr 1998,
/// Übergang von Besitz, Nutzen und Lasten am 15.05.2024.
@MainActor
final class TaxCorrectionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = AppSchema.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func baseProperty() -> Property {
        let property = Property(name: "Grundfall", purchasePrice: 300_000, purchaseAncillaryCosts: 30_000, landValue: 60_000, constructionYear: 1998)
        property.economicTransferDate = date(2024, 5, 15)
        context.insert(property)
        return property
    }

    private func expense(_ property: Property, _ day: Date, gross: Double, vat: Double? = 19, treatment: TaxTreatment = .maintenanceExpense, category: ExpenseCategory = .maintenance) -> Expense {
        let expense = Expense(date: day, amount: gross, category: category, taxTreatment: treatment)
        expense.vatRatePercent = vat
        expense.property = property
        context.insert(expense)
        return expense
    }

    // MARK: - T1–T4 Gebäude-AfA

    func testT1BuildingValueAndLandShare() {
        let property = baseProperty()
        XCTAssertEqual(property.buildingValue, 264_000, accuracy: 0.01)
        XCTAssertEqual(property.apportionedLandValue, 66_000, accuracy: 0.01)
    }

    func testT2T3AfaFirstAndFollowingYear() {
        let property = baseProperty()
        XCTAssertEqual(property.buildingAfA(forYear: 2024), 3_520, accuracy: 0.01)
        XCTAssertEqual(property.buildingAfA(forYear: 2025), 5_280, accuracy: 0.01)
    }

    func testT4AfaEndsWithRemainderAfterFullDepreciation() {
        let property = baseProperty()
        XCTAssertEqual(property.buildingAfA(forYear: 2073), 5_280, accuracy: 0.01)
        XCTAssertEqual(property.buildingAfA(forYear: 2074), 1_760, accuracy: 0.01)
        XCTAssertEqual(property.buildingAfA(forYear: 2075), 0, accuracy: 0.01)
        XCTAssertEqual(property.cumulativeBuildingAfA(uptoYear: 2075), 264_000, accuracy: 0.01)
    }

    // MARK: - T5–T10 15-%-Grenze

    private func thresholdCase(for property: Property) -> ThreeYearThresholdCase {
        let thresholdCase = ThreeYearThresholdCase(periodStart: date(2024, 5, 15), periodEnd: date(2027, 5, 15))
        thresholdCase.property = property
        context.insert(thresholdCase)
        return thresholdCase
    }

    func testT5ThresholdAmount() {
        let property = baseProperty()
        XCTAssertEqual(thresholdCase(for: property).thresholdAmount, 39_600, accuracy: 0.01)
    }

    func testT8CapitalizedCostsCountTowardThreshold() {
        let property = baseProperty()
        let thresholdCase = thresholdCase(for: property)
        let maintenance = expense(property, date(2024, 8, 1), gross: 29_750)                       // netto 25.000 €
        let standardUpgrade = expense(property, date(2025, 3, 1), gross: 23_800, treatment: .capitalized) // netto 20.000 €
        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: maintenance)?.status = .certain
        thresholdCase.assessment(for: standardUpgrade)?.status = .certain

        XCTAssertEqual(thresholdCase.includedNetTotal, 45_000, accuracy: 0.01)
        XCTAssertEqual(thresholdCase.status, .exceeded)
    }

    func testT9PeriodEndDayIsIncludedRegardlessOfTime() {
        let property = baseProperty()
        let thresholdCase = thresholdCase(for: property)
        let lastDay = expense(property, date(2027, 5, 15, hour: 18), gross: 1_190)
        let dayAfter = expense(property, date(2027, 5, 16), gross: 1_190)
        let ids = Set(thresholdCase.candidateExpenses.map(\.persistentModelID))
        XCTAssertTrue(ids.contains(lastDay.persistentModelID))
        XCTAssertFalse(ids.contains(dayAfter.persistentModelID))
    }

    func testT10MissingVatRateMakesCaseNotConclusive() {
        let property = baseProperty()
        let thresholdCase = thresholdCase(for: property)
        let withoutVat = expense(property, date(2024, 9, 1), gross: 5_000, vat: nil)
        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: withoutVat)?.status = .certain
        XCTAssertEqual(thresholdCase.status, .notConclusivelyCheckable)
    }

    // MARK: - T11–T13 Bewegliche Wirtschaftsgüter

    func testT11FurnitureRemainderFallsIntoYearAfterUsefulLife() {
        let asset = DepreciableAsset(name: "Küche", category: .furniture, cost: 6_000, usefulLifeYears: 10, placedInServiceDate: date(2020, 7, 1))
        asset.vatRatePercent = 19
        XCTAssertEqual(asset.depreciation(forYear: 2020), 300, accuracy: 0.01)
        XCTAssertEqual(asset.depreciation(forYear: 2021), 600, accuracy: 0.01)
        XCTAssertEqual(asset.depreciation(forYear: 2029), 600, accuracy: 0.01)
        XCTAssertEqual(asset.depreciation(forYear: 2030), 300, accuracy: 0.01)
        XCTAssertEqual(asset.depreciation(forYear: 2031), 0, accuracy: 0.01)
        XCTAssertEqual(asset.cumulativeDepreciation(uptoYear: 2031), 6_000, accuracy: 0.01)
    }

    func testFurnitureStartingInJanuaryEndsExactlyAfterUsefulLife() {
        let asset = DepreciableAsset(name: "Sofa", category: .furniture, cost: 5_000, usefulLifeYears: 10, placedInServiceDate: date(2020, 1, 15))
        XCTAssertEqual(asset.depreciation(forYear: 2029), 500, accuracy: 0.01)
        XCTAssertEqual(asset.depreciation(forYear: 2030), 0, accuracy: 0.01)
    }

    func testT12GwgLimitIsCheckedNetButDeductedGross() {
        let asset = DepreciableAsset(name: "Schrank", category: .furniture, cost: 900, usefulLifeYears: 13, placedInServiceDate: date(2024, 3, 1))
        XCTAssertEqual(asset.gwgNetBasis, 756.30, accuracy: 0.01)
        XCTAssertTrue(asset.isImmediatelyDeductible)
        XCTAssertEqual(asset.depreciation(forYear: 2024), 900, accuracy: 0.01)

        asset.vatRatePercent = 0 // privat ohne Umsatzsteuer gekauft
        XCTAssertFalse(asset.isImmediatelyDeductible)
    }

    func testT13GwgBoundary() {
        let atLimit = DepreciableAsset(name: "A", category: .furniture, cost: 952, usefulLifeYears: 10, placedInServiceDate: date(2024, 1, 1))
        let justAbove = DepreciableAsset(name: "B", category: .furniture, cost: 952.02, usefulLifeYears: 10, placedInServiceDate: date(2024, 1, 1))
        XCTAssertTrue(atLimit.isImmediatelyDeductible)
        XCTAssertFalse(justAbove.isImmediatelyDeductible)
    }

    func testUsedAssetAssumesNoVat() {
        let asset = DepreciableAsset(name: "Tisch gebraucht", category: .furniture, cost: 0, usefulLifeYears: 5, placedInServiceDate: date(2024, 1, 1), isUsed: true, estimatedValueAtAcquisition: 850)
        XCTAssertEqual(asset.gwgNetBasis, 850, accuracy: 0.01)
        XCTAssertFalse(asset.isImmediatelyDeductible)
    }

    // MARK: - T14/T15 Restnutzungsdauer und Gutachten

    func testT14YoungBuildingKeepsFullRemainingLifeAndAppraisalDoesNotApply() {
        let property = baseProperty()
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 2010, valuationDate: date(2025, 1, 1), totalUsefulLifeYears: 80)
        appraisal.property = property
        context.insert(appraisal)

        XCTAssertEqual(appraisal.remainingUsefulLifeYears, 65, accuracy: 0.001)
        XCTAssertNil(property.applicableRemainingUsefulLifeAppraisal)
        XCTAssertEqual(property.afaRateSource, .typisiert)
        XCTAssertEqual(property.afaRatePercent, 2.0)
        XCTAssertEqual(property.buildingAfA(forYear: 2025), 5_280, accuracy: 0.01)
    }

    func testT15AppraisalRateIsNotRoundedBeforeCalculation() {
        let property = baseProperty()
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 1960, valuationDate: date(2026, 1, 1), totalUsefulLifeYears: 80)
        appraisal.property = property
        context.insert(appraisal)

        let rnd = appraisal.remainingUsefulLifeYears
        XCTAssertEqual(rnd, 16.8125, accuracy: 0.0001)
        XCTAssertEqual(property.afaRateSource, .appraisal)
        XCTAssertEqual(property.annualBuildingAfA, 264_000 / rnd, accuracy: 0.01)
    }

    func testModernizationStretchesRemainingLifeToAtMostSeventyPercent() {
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 1926, valuationDate: date(2026, 1, 1), totalUsefulLifeYears: 80)
        appraisal.roofPoints = 4; appraisal.facadePoints = 4; appraisal.windowsPoints = 2; appraisal.utilityLinesPoints = 2
        appraisal.heatingPoints = 2; appraisal.bathroomsPoints = 2; appraisal.interiorPoints = 2; appraisal.floorPlanPoints = 2
        XCTAssertEqual(appraisal.remainingUsefulLifeYears, 56, accuracy: 0.001, "Modellwert 56,36 Jahre, begrenzt auf 70 % von 80")

        appraisal.isCoreRenovation = true
        XCTAssertEqual(appraisal.remainingUsefulLifeYears, 56.36, accuracy: 0.001, "Bei Kernsanierung gilt die 90-%-Grenze")
    }

    func testCoreRenovationCapsAtNinetyPercent() {
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 2022, valuationDate: date(2025, 1, 1), totalUsefulLifeYears: 80)
        appraisal.isCoreRenovation = true
        XCTAssertEqual(appraisal.remainingUsefulLifeYears, 72, accuracy: 0.001)
    }

    /// Plausibilitätsprüfung der Koeffizienten (Tabelle 3, Anlage 2 ImmoWertV): An der jeweiligen
    /// Altersschwelle schließt die Modellformel an GND − Alter an. Ein Tippfehler in a, b oder c
    /// würde hier einen deutlichen Sprung erzeugen; die amtliche Tabelle weicht nur um bis zu
    /// rund 1,4 Jahre (bei GND 100) ab.
    func testCoefficientTableJoinsSimpleFormulaAtEachThreshold() {
        let maxima = [4, 4, 2, 2, 2, 2, 2, 2]
        for points in 0...20 {
            var remaining = points
            let distribution = maxima.map { maximum -> Int in let value = min(maximum, remaining); remaining -= value; return value }
            func appraisal(age: Int) -> RemainingUsefulLifeAppraisal {
                let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 2000, valuationDate: date(2000 + age, 6, 1), totalUsefulLifeYears: 100)
                appraisal.roofPoints = distribution[0]; appraisal.facadePoints = distribution[1]; appraisal.windowsPoints = distribution[2]
                appraisal.utilityLinesPoints = distribution[3]; appraisal.heatingPoints = distribution[4]; appraisal.bathroomsPoints = distribution[5]
                appraisal.interiorPoints = distribution[6]; appraisal.floorPlanPoints = distribution[7]
                return appraisal
            }
            let thresholds = [60, 60, 55, 55, 40, 35, 30, 25, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 10, 10]
            let atThreshold = appraisal(age: thresholds[points])
            XCTAssertEqual(atThreshold.totalModernizationPoints, points)
            XCTAssertEqual(atThreshold.remainingUsefulLifeYears, Double(100 - thresholds[points]), accuracy: 1.5, "Punkte \(points)")
            let justBefore = appraisal(age: thresholds[points] - 1)
            XCTAssertLessThanOrEqual(justBefore.remainingUsefulLifeYears - atThreshold.remainingUsefulLifeYears, 2.5, "Kein Sprung an der Schwelle bei \(points) Punkten")
        }
    }

    // MARK: - T16 Schuldzinsen

    func testT16LoanStartingInDecemberCountsOneMonth() throws {
        let property = baseProperty()
        property.loanAmount = 200_000
        property.interestRatePercent = 4
        property.initialRepaymentRatePercent = 2
        property.loanStartDate = date(2024, 12, 1)

        let firstYear = try XCTUnwrap(property.loanBreakdown(forYear: 2024))
        XCTAssertEqual(firstYear.interest, 666.67, accuracy: 0.01)
        XCTAssertEqual(firstYear.principal, 333.33, accuracy: 0.01)
        let secondYear = try XCTUnwrap(property.loanBreakdown(forYear: 2025))
        XCTAssertEqual(secondYear.interest, (200_000 - 333.33) * 0.04, accuracy: 0.05)
    }

    // MARK: - T17–T19 Bodenwert, Eigentumsanteil

    func testT17MissingLandValueIsFlagged() {
        let property = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 30_000)
        XCTAssertTrue(property.isLandValueMissing)
        XCTAssertEqual(property.buildingValue, 330_000, accuracy: 0.01)
        XCTAssertFalse(baseProperty().isLandValueMissing)
    }

    func testT18LandValueAbovePriceMeansNoAfa() {
        let property = Property(purchasePrice: 300_000, landValue: 400_000)
        XCTAssertEqual(property.buildingValue, 0)
        XCTAssertEqual(property.buildingAfA(forYear: 2025), 0)
    }

    func testT19OwnershipShareIsShownAsShareOfResult() {
        let property = baseProperty()
        property.ownershipSharePercent = 50
        let calc = AnlageVCalculation(property: property, year: 2025)
        XCTAssertEqual(calc.ownershipSharePercent, 50)
        XCTAssertEqual(calc.ownerShareOfResult ?? 0, calc.result / 2, accuracy: 0.01)

        property.ownershipSharePercent = 100
        XCTAssertNil(AnlageVCalculation(property: property, year: 2025).ownerShareOfResult)
    }

    // MARK: - Herstellungskosten am Gebäude

    func testImprovementGetsFullYearAfaInYearOfIncurrence() {
        let property = baseProperty()
        let asset = DepreciableAsset(name: "Fassade", category: .improvement, cost: 20_000, placedInServiceDate: date(2026, 9, 1))
        asset.property = property
        context.insert(asset)
        XCTAssertEqual(asset.depreciation(forYear: 2026), 400, accuracy: 0.01)
    }

    func testImprovementInAcquisitionYearStartsWithBuildingAfa() {
        let property = baseProperty()
        let asset = DepreciableAsset(name: "Bad", category: .improvement, cost: 12_000, placedInServiceDate: date(2024, 8, 1))
        asset.property = property
        context.insert(asset)
        XCTAssertEqual(asset.depreciation(forYear: 2024), 12_000 * 0.02 * 8 / 12, accuracy: 0.01)
    }

    func testCapitalizationCreatesOneAssetPerCalendarYear() {
        let property = baseProperty()
        let first = expense(property, date(2024, 10, 1), gross: 10_000)
        let second = expense(property, date(2025, 4, 1), gross: 5_000)
        let decisions = CapitalizationDecision.create(from: [first, second], property: property, thresholdCase: nil, reason: "Sanierung", context: context)

        XCTAssertEqual(decisions.map(\.effectiveYear), [2024, 2025])
        XCTAssertEqual(decisions.map(\.totalAmount), [10_000, 5_000])
        XCTAssertEqual(property.assetDepreciation(forYear: 2024), 10_000 * 0.02 * 8 / 12, accuracy: 0.01)
        XCTAssertEqual(property.assetDepreciation(forYear: 2025), 10_000 * 0.02 + 5_000 * 0.02, accuracy: 0.01)
    }

    // MARK: - Homeoffice-Pauschale je Jahr

    func testHomeOfficeAllowanceDependsOnYear() {
        let property = Property(name: "Objekt")
        context.insert(property)
        for (year, days) in [(2019, 100), (2022, 150), (2023, 150)] {
            let entry = HomeOfficeEntry(taxYear: year, days: days)
            entry.property = property
            context.insert(entry)
        }
        XCTAssertEqual(property.homeOfficeAllowance(forYear: 2019), 0)
        XCTAssertEqual(property.homeOfficeAllowance(forYear: 2022), 600, accuracy: 0.01)
        XCTAssertTrue(HomeOfficeAllocation.isCapExceeded(for: property, taxYear: 2022))
        XCTAssertEqual(property.homeOfficeAllowance(forYear: 2023), 900, accuracy: 0.01)
        XCTAssertFalse(HomeOfficeAllocation.isCapExceeded(for: property, taxYear: 2023))
    }

    // MARK: - Mietstaffeln

    private func tenancyInUnit(_ property: Property, start: Date, coldRent: Double, utility: Double = 0, type: TenancyContractType = .standard) -> Tenancy {
        let unit = Unit(name: "EG")
        unit.property = property
        context.insert(unit)
        let tenancy = Tenancy(startDate: start, coldRent: coldRent, utilityAdvance: utility, contractType: type)
        tenancy.unit = unit
        context.insert(tenancy)
        return tenancy
    }

    func testRentStepsAreIncludedInAnnualColdRent() {
        let property = baseProperty()
        let tenancy = tenancyInUnit(property, start: date(2024, 1, 1), coldRent: 800, type: .staffel)
        let step = RentStep(effectiveDate: date(2024, 7, 1), coldRent: 900)
        step.tenancy = tenancy
        context.insert(step)

        XCTAssertEqual(tenancy.coldRent(forMonthContaining: date(2024, 6, 15)), 800)
        XCTAssertEqual(tenancy.coldRent(forMonthContaining: date(2024, 7, 1)), 900)
        XCTAssertEqual(property.annualColdRent(forYear: 2024), 6 * 800 + 6 * 900, accuracy: 0.01)
        XCTAssertEqual(property.annualColdRent(forYear: 2025), 12 * 900, accuracy: 0.01)
    }

    func testRentStepEffectiveMidMonthAppliesFromNextMonth() {
        let property = baseProperty()
        let tenancy = tenancyInUnit(property, start: date(2024, 1, 1), coldRent: 800, type: .staffel)
        let step = RentStep(effectiveDate: date(2024, 7, 15), coldRent: 900)
        step.tenancy = tenancy
        context.insert(step)
        XCTAssertEqual(tenancy.coldRent(forMonthContaining: date(2024, 7, 20)), 800)
        XCTAssertEqual(tenancy.coldRent(forMonthContaining: date(2024, 8, 1)), 900)
    }

    func testRentStepsIgnoredForNonStaffelContracts() {
        let property = baseProperty()
        let tenancy = tenancyInUnit(property, start: date(2024, 1, 1), coldRent: 800, type: .standard)
        let step = RentStep(effectiveDate: date(2024, 7, 1), coldRent: 900)
        step.tenancy = tenancy
        context.insert(step)
        XCTAssertEqual(property.annualColdRent(forYear: 2024), 9_600, accuracy: 0.01)
    }

    func testArrearsUseRentStepAmount() {
        let property = baseProperty()
        let tenancy = tenancyInUnit(property, start: date(2026, 1, 1), coldRent: 800, utility: 100, type: .staffel)
        let step = RentStep(effectiveDate: date(2026, 2, 1), coldRent: 850)
        step.tenancy = tenancy
        context.insert(step)
        XCTAssertEqual(tenancy.arrearsBalance(upTo: date(2026, 2, 28)), 900 + 950, accuracy: 0.01)
    }

    // MARK: - Anlage V

    func testAnlageVUsesReceivedPaymentsUmlagenAndUtilityStatement() throws {
        let property = baseProperty()
        let tenancy = tenancyInUnit(property, start: date(2024, 1, 1), coldRent: 1_000, utility: 200)
        let january = RentPayment(dueDate: date(2025, 1, 1), coldRentDue: 1_000, utilityAdvanceDue: 200)
        january.markPaid(date: date(2025, 1, 3))
        january.tenancy = tenancy
        context.insert(january)
        let february = RentPayment(dueDate: date(2025, 2, 1), coldRentDue: 1_000, utilityAdvanceDue: 200)
        february.tenancy = tenancy // nicht bezahlt
        context.insert(february)

        let statement = UtilityStatement(propertyTaxAmount: 150)
        statement.periodStart = date(2025, 1, 1)
        statement.periodEnd = date(2025, 12, 31)
        statement.property = property
        context.insert(statement)
        for (type, amount, apportionable) in [("Heizung", 1_000.0, true), ("Verwaltergebühr", 300.0, false), ("Zuführung Instandhaltungsrücklage", 500.0, false)] {
            let item = UtilityCostLineItem(costType: type, amount: amount, isApportionable: apportionable)
            item.statement = statement
            context.insert(item)
        }
        let duplicateUtility = expense(property, date(2025, 3, 1), gross: 400, vat: nil, treatment: .otherDeductible, category: .utilities)

        property.loanAmount = 100_000
        property.interestRatePercent = 3
        property.initialRepaymentRatePercent = 2
        property.loanStartDate = date(2024, 1, 1)
        let duplicateInterest = expense(property, date(2025, 6, 1), gross: 2_900, vat: nil, treatment: .otherDeductible, category: .financing)
        _ = expense(property, date(2025, 6, 1), gross: 120, vat: nil, treatment: .otherDeductible, category: .insurance)

        let calc = AnlageVCalculation(property: property, year: 2025)
        XCTAssertEqual(calc.coldRentIncome, 11_000, accuracy: 0.01)
        XCTAssertEqual(calc.utilityAdvanceIncome, 2_200, accuracy: 0.01)
        XCTAssertEqual(calc.estimatedRentMonths, 10)
        XCTAssertEqual(calc.utilityCosts, 1_150 + 300, accuracy: 0.01)
        XCTAssertEqual(calc.excludedReserveItems.map(\.costType), ["Zuführung Instandhaltungsrücklage"])
        XCTAssertEqual(calc.excludedUtilityExpenses.map(\.persistentModelID), [duplicateUtility.persistentModelID])
        XCTAssertEqual(calc.excludedFinancingExpenses.map(\.persistentModelID), [duplicateInterest.persistentModelID])
        XCTAssertEqual(calc.otherDeductible, 120, accuracy: 0.01)
        XCTAssertEqual(calc.interest, (100_000 - 2_000) * 0.03, accuracy: 0.01)
        XCTAssertEqual(property.estimatedTaxableResult(forYear: 2025), calc.result, accuracy: 0.01)
        XCTAssertEqual(property.werbungskosten(forYear: 2025), calc.werbungskostenWithoutAfa, accuracy: 0.01)
    }

    func testUmlagenWithoutUtilityCostsAreFlagged() {
        let property = baseProperty()
        _ = tenancyInUnit(property, start: date(2024, 1, 1), coldRent: 1_000, utility: 200)
        XCTAssertTrue(AnlageVCalculation(property: property, year: 2025).utilityCostsMissing)
    }
}
