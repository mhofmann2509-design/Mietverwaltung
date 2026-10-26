import XCTest
import SwiftData
@testable import Mietverwaltung

/// Automatisierte Tests für die steuerlichen Kernberechnungen des Steuermoduls (siehe Auftrag
/// Abschnitt 12): Gebäude-AfA, 15-%-Grenze/Dreijahresüberwachung, Möbel-AfA/Doppelvermeidung,
/// Netto-Betrag-Ermittlung und Checklisten-Seeding. Unabhängig von der App-UI nachgerechnet, mit
/// eigenen Referenzwerten statt gegen die zu testende Implementierung selbst zu prüfen.
@MainActor
final class TaxCalculationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            Property.self, Unit.self, Tenant.self, Tenancy.self, RentPayment.self, Expense.self, Document.self,
            DepreciableAsset.self, UtilityStatement.self, UtilityCostLineItem.self, Landlord.self,
            RemainingUsefulLifeAppraisal.self, WirtschaftsplanStatement.self, WirtschaftsplanLineItem.self,
            TrackedYear.self, TaxChecklistItem.self, ThreeYearThresholdCase.self, ThresholdExpenseAssessment.self,
            TravelExpense.self, HomeOfficeEntry.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func calendarDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    // MARK: - Gebäude-AfA

    func testBuildingAfaFullYear() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2000, 1, 1), landValue: 60_000, constructionYear: 1998)
        // Gebäudewert 240.000 €, Satz 2 % (Baujahr < 2023 und ≥ 1925) → 4.800 €/Jahr.
        XCTAssertEqual(property.buildingValue, 240_000)
        XCTAssertEqual(property.afaRatePercent, 2.0)
        XCTAssertEqual(property.buildingAfA(forYear: 2010), 4_800, accuracy: 0.01)
    }

    func testBuildingAfaProRataInPurchaseYear() {
        // Kauf im Juli → nur 6 von 12 Monaten AfA im Anschaffungsjahr (Monat der Anschaffung zählt mit).
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2024, 7, 15), landValue: 60_000, constructionYear: 1998)
        let expected = 240_000 * 0.02 * 6.0 / 12.0
        XCTAssertEqual(property.buildingAfA(forYear: 2024), expected, accuracy: 0.01)
        XCTAssertEqual(property.buildingAfA(forYear: 2025), 240_000 * 0.02, accuracy: 0.01)
        XCTAssertEqual(property.buildingAfA(forYear: 2023), 0)
    }

    func testBuildingValueApportionsAncillaryCostsByLandPercentage() {
        // Kaufpreis 245.000 € (Grund 61.250 € / Gebäude 183.750 € → Grundanteil 25 %),
        // Anschaffungsnebenkosten 24.000 € (Grunderwerbsteuer+Notar+Makler+Sonstiges). Die
        // Nebenkosten erhöhen die AfA-Bemessungsgrundlage und werden im selben Verhältnis wie der
        // reine Kaufpreis auf Grund und Gebäude verteilt (siehe Steuererklärung_Vermietung_Vorlage.xlsx).
        let property = Property(purchasePrice: 245_000, purchaseAncillaryCosts: 24_000, landValue: 61_250)
        XCTAssertEqual(property.landValuePercentage, 0.25, accuracy: 0.0001)
        XCTAssertEqual(property.totalAcquisitionCost, 269_000, accuracy: 0.01)
        XCTAssertEqual(property.apportionedLandValue, 67_250, accuracy: 0.01)
        XCTAssertEqual(property.buildingValue, 201_750, accuracy: 0.01)
    }

    func testBuildingValueWithoutAncillaryCostsMatchesSimpleSubtraction() {
        // Ohne Anschaffungsnebenkosten muss sich exakt die bisherige, einfache Berechnung ergeben
        // (Kaufpreis − Bodenwert) – reine Erweiterung, keine Verhaltensänderung für diesen Fall.
        let property = Property(purchasePrice: 300_000, landValue: 60_000)
        XCTAssertEqual(property.buildingValue, 240_000, accuracy: 0.01)
    }

    func testBuildingAfaRateByConstructionYear() {
        XCTAssertEqual(Property(constructionYear: 2024).defaultAfaRatePercent, 3.0)
        XCTAssertEqual(Property(constructionYear: 1920).defaultAfaRatePercent, 2.5)
        XCTAssertEqual(Property(constructionYear: 1960).defaultAfaRatePercent, 2.0)
    }

    func testManualAfaRateOverrideIsNotSilentlyIgnored() {
        let property = Property(constructionYear: 1998)
        property.afaRatePercentOverride = 2.5
        XCTAssertEqual(property.afaRatePercent, 2.5)
        XCTAssertEqual(property.afaRateSource, .manual)
    }

    func testAppraisalRateAppliesWithoutManualOverride() {
        let property = Property(constructionYear: 1998)
        context.insert(property)
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 1998, totalUsefulLifeYears: 80)
        appraisal.property = property
        context.insert(appraisal)

        XCTAssertEqual(property.afaRateSource, .appraisal)
        XCTAssertEqual(property.afaRatePercent, appraisal.suggestedAfaRatePercent, accuracy: 0.01)
        XCTAssertNotEqual(property.afaRatePercent, property.defaultAfaRatePercent, "Das Gutachten muss den typisierten Satz tatsächlich ersetzen, nicht nur informativ danebenstehen.")
    }

    func testManualOverrideWinsOverAppraisal() {
        let property = Property(constructionYear: 1998)
        context.insert(property)
        let appraisal = RemainingUsefulLifeAppraisal(constructionYear: 1998, totalUsefulLifeYears: 80)
        appraisal.property = property
        context.insert(appraisal)
        property.afaRatePercentOverride = 3.3

        XCTAssertEqual(property.afaRateSource, .manual)
        XCTAssertEqual(property.afaRatePercent, 3.3, accuracy: 0.01)
    }

    func testWithoutAppraisalOrOverrideUsesTypisiertenSatz() {
        let property = Property(constructionYear: 1998)
        XCTAssertEqual(property.afaRateSource, .typisiert)
        XCTAssertEqual(property.afaRatePercent, property.defaultAfaRatePercent)
    }

    // MARK: - Netto-Betrag

    func testNetAmountRequiresVatRate() {
        let expense = Expense(amount: 1_190, title: "Dachreparatur")
        XCTAssertNil(expense.netAmount, "Ohne hinterlegten USt-Satz darf kein Netto-Betrag erfunden werden.")
        expense.vatRatePercent = 19
        XCTAssertEqual(expense.netAmount!, 1_000, accuracy: 0.01)
    }

    // MARK: - 15-%-Grenze

    func testThresholdCaseBelowThreshold() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        // Bemessungsgrundlage 240.000 € → Schwelle 36.000 €.
        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 11_900, title: "Badsanierung", taxTreatment: .maintenanceExpense)
        expense.vatRatePercent = 19
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain

        XCTAssertEqual(thresholdCase.thresholdAmount, 36_000, accuracy: 0.01)
        XCTAssertEqual(thresholdCase.includedNetTotal, 10_000, accuracy: 0.01)
        XCTAssertEqual(thresholdCase.status, .belowThreshold)
    }

    func testThresholdCaseExceeded() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        // Schwelle 36.000 € – Netto-Position von 40.000 € überschreitet sie.
        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 47_600, title: "Komplettsanierung", taxTreatment: .maintenanceExpense)
        expense.vatRatePercent = 19
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain

        XCTAssertEqual(thresholdCase.status, .exceeded)
    }

    func testThresholdCaseNotConclusivelyCheckableWhileUnclassified() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 1_190, title: "Fenstertausch", taxTreatment: .maintenanceExpense)
        expense.vatRatePercent = 19
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        // Neu erkannte Position bleibt unklassifiziert, solange niemand sie einordnet.
        XCTAssertEqual(thresholdCase.assessment(for: expense)?.status, .unclassified)
        XCTAssertEqual(thresholdCase.status, .notConclusivelyCheckable)
    }

    func testThresholdCaseFlagsMissingNetAmount() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        // Kein USt-Satz hinterlegt → Netto-Betrag nicht ermittelbar, obwohl "certain" gesetzt ist.
        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 1_000, title: "Malerarbeiten", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain

        XCTAssertEqual(thresholdCase.missingNetAmountExpenses.count, 1)
        XCTAssertEqual(thresholdCase.status, .notConclusivelyCheckable)
    }

    func testThresholdCaseExcludesOtherDeductibleAndCapitalizedExpenses() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let insurance = Expense(date: calendarDate(2023, 6, 1), amount: 500, title: "Versicherung", taxTreatment: .otherDeductible)
        insurance.property = property
        context.insert(insurance)
        let capitalized = Expense(date: calendarDate(2023, 6, 1), amount: 20_000, title: "Anbau", taxTreatment: .capitalized)
        capitalized.property = property
        context.insert(capitalized)

        XCTAssertTrue(thresholdCase.candidateExpenses.isEmpty, "Sonstige Werbungskosten und Herstellungskosten gehören nicht in die 15-%-Grenze.")
    }

    func testEnsureAssessmentsIsIdempotent() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 1_000, title: "Fenstertausch", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain
        thresholdCase.ensureAssessments(context: context)
        thresholdCase.ensureAssessments(context: context)

        XCTAssertEqual(thresholdCase.assessments?.count, 1, "Mehrfaches Aufrufen darf keine doppelten Einordnungen erzeugen.")
        XCTAssertEqual(thresholdCase.assessment(for: expense)?.status, .certain, "Ein bereits gesetzter Status darf nicht zurückgesetzt werden.")
    }

    // MARK: - Möbel-AfA / Doppelvermeidung

    func testFurnitureGwgImmediateDeduction() {
        let asset = DepreciableAsset(name: "Lampe", category: .furniture, cost: 400, usefulLifeYears: 10, placedInServiceDate: calendarDate(2024, 3, 1))
        XCTAssertTrue(asset.isImmediatelyDeductible)
        XCTAssertEqual(asset.depreciation(forYear: 2024), 400)
        XCTAssertEqual(asset.depreciation(forYear: 2025), 0, "GWG wird nur im Anschaffungsjahr abgezogen, nicht nochmal in Folgejahren.")
    }

    func testFurnitureLinearDepreciationDoesNotDoubleCountWithBuildingAfa() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000, constructionYear: 1998)
        let asset = DepreciableAsset(name: "Einbauküche", category: .furniture, cost: 5_000, usefulLifeYears: 10, placedInServiceDate: calendarDate(2023, 1, 1))
        asset.property = property
        context.insert(property)
        context.insert(asset)

        // Gebäude-AfA und Möbel-AfA sind getrennte, additive Größen – keine Position fließt in beide ein.
        XCTAssertEqual(property.buildingAfA(forYear: 2023), 4_800, accuracy: 0.01)
        XCTAssertEqual(asset.depreciation(forYear: 2023), 500, accuracy: 0.01)
        XCTAssertEqual(property.totalAfa(forYear: 2023), 5_300, accuracy: 0.01)
    }

    // MARK: - Zinsen/Tilgung, Werbungskosten

    func testPrincipalRepaymentIsNotCountedAsDeductibleInterest() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        property.loanAmount = 200_000
        property.interestRatePercent = 3.0
        property.initialRepaymentRatePercent = 2.0
        property.loanStartDate = calendarDate(2023, 1, 1)

        guard let breakdown = property.loanBreakdown(forYear: 2023) else {
            return XCTFail("Finanzierung sollte einen Zins-/Tilgungssplit liefern.")
        }
        XCTAssertEqual(breakdown.interest, 6_000, accuracy: 0.01)
        XCTAssertEqual(breakdown.principal, 4_000, accuracy: 0.01)
        // Schuldzinsen sind Werbungskosten (§9 Abs.1 S.3 Nr.1 EStG), die Tilgung dagegen nicht –
        // werbungskosten(forYear:) muss daher exakt dem Zinsanteil entsprechen, nie dem Tilgungsanteil.
        XCTAssertEqual(property.werbungskosten(forYear: 2023), 6_000, accuracy: 0.01)
    }

    // MARK: - Fahrtkosten

    func testTravelExpenseAmountUsesActualRoundTripKilometers() {
        let property = Property(name: "Teststraße 1")
        context.insert(property)
        let trip = TravelExpense(date: calendarDate(2026, 3, 1), purpose: "Besichtigung", kilometers: 40, ratePerKilometer: 0.30)
        trip.property = property
        context.insert(trip)

        XCTAssertEqual(trip.amount, 12, accuracy: 0.01)
        XCTAssertEqual(property.travelExpenseTotal(forYear: 2026), 12, accuracy: 0.01)
        XCTAssertEqual(property.travelExpenseTotal(forYear: 2025), 0)
    }

    // MARK: - Homeoffice-Pauschale

    func testHomeOfficeAllowanceBelowCapUsesFullDaysTimesRate() {
        let property = Property(name: "Teststraße 1")
        context.insert(property)
        let entry = HomeOfficeEntry(taxYear: 2026, days: 50, dailyRate: 6)
        entry.property = property
        context.insert(entry)

        XCTAssertEqual(HomeOfficeAllocation.apportionedAmount(for: property, taxYear: 2026), 300, accuracy: 0.01)
        XCTAssertFalse(HomeOfficeAllocation.isCapExceeded(for: property, taxYear: 2026))
    }

    func testHomeOfficeAllowanceCappedAndApportionedAcrossProperties() {
        // 250 Tage über zwei Immobilien hinweg (150 + 100) überschreiten die 210-Tage-/1.260-€-
        // Grenze, die pro Person über ALLE Immobilien gilt – die gedeckelte Summe wird nach
        // Tagesanteil aufgeteilt, nicht je Immobilie einzeln gedeckelt.
        let propertyA = Property(name: "Objekt A")
        let propertyB = Property(name: "Objekt B")
        context.insert(propertyA)
        context.insert(propertyB)

        let entryA = HomeOfficeEntry(taxYear: 2026, days: 150, dailyRate: 6)
        entryA.property = propertyA
        context.insert(entryA)
        let entryB = HomeOfficeEntry(taxYear: 2026, days: 100, dailyRate: 6)
        entryB.property = propertyB
        context.insert(entryB)

        XCTAssertTrue(HomeOfficeAllocation.isCapExceeded(for: propertyA, taxYear: 2026))
        // Gedeckelte Gesamtsumme: min(250*6, 1260) = 1.260 € – aufgeteilt 150/250 bzw. 100/250.
        XCTAssertEqual(HomeOfficeAllocation.apportionedAmount(for: propertyA, taxYear: 2026), 1_260 * 150.0 / 250.0, accuracy: 0.01)
        XCTAssertEqual(HomeOfficeAllocation.apportionedAmount(for: propertyB, taxYear: 2026), 1_260 * 100.0 / 250.0, accuracy: 0.01)
    }

    func testHomeOfficeAllowanceWithoutEntriesIsZero() {
        let property = Property(name: "Teststraße 1")
        context.insert(property)
        XCTAssertEqual(HomeOfficeAllocation.apportionedAmount(for: property, taxYear: 2026), 0)
        XCTAssertFalse(HomeOfficeAllocation.isCapExceeded(for: property, taxYear: 2026))
    }

    // MARK: - Checkliste

    func testChecklistSeederDoesNotCreateDuplicatesOnRepeatedCalls() {
        let property = Property(name: "Teststraße 1")
        context.insert(property)

        TaxChecklistSeeder.ensureSeeded(for: property, taxYear: 2024, context: context)
        TaxChecklistSeeder.ensureSeeded(for: property, taxYear: 2024, context: context)

        let expectedCount = TaxChecklistTemplate.initialSetupEntries.count + TaxChecklistTemplate.ongoingEntries.count
        XCTAssertEqual(property.taxChecklistItems?.count, expectedCount)
    }

    func testChecklistSeederAddsOngoingEntriesPerYearWithoutTouchingInitialSetup() {
        let property = Property(name: "Teststraße 1")
        context.insert(property)

        TaxChecklistSeeder.ensureSeeded(for: property, taxYear: 2023, context: context)
        (property.taxChecklistItems ?? []).first(where: { $0.mode == .initialSetup })?.status = .done
        TaxChecklistSeeder.ensureSeeded(for: property, taxYear: 2024, context: context)

        let initialSetupItems = (property.taxChecklistItems ?? []).filter { $0.mode == .initialSetup }
        XCTAssertEqual(initialSetupItems.count, TaxChecklistTemplate.initialSetupEntries.count, "Erstanlage-Einträge dürfen bei einem neuen Jahr nicht verdoppelt werden.")
        XCTAssertTrue(initialSetupItems.contains { $0.status == .done }, "Ein bereits gesetzter Status darf durch erneutes Seeding nicht zurückgesetzt werden.")

        let ongoing2024 = (property.taxChecklistItems ?? []).filter { $0.mode == .ongoing && $0.taxYear == 2024 }
        XCTAssertEqual(ongoing2024.count, TaxChecklistTemplate.ongoingEntries.count)
    }

    func testChecklistStatusIsNeverSetAutomatically() {
        let property = Property(name: "Teststraße 1")
        context.insert(property)
        TaxChecklistSeeder.ensureSeeded(for: property, taxYear: 2024, context: context)

        XCTAssertTrue((property.taxChecklistItems ?? []).allSatisfy { $0.status == .open }, "Neu angelegte Checklisten-Einträge müssen immer offen starten.")
    }
}
