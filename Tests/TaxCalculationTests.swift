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

    /// Deckt den im Design-Audit geforderten Fall ab, dass die Portfolio-Summen im Steuer-Cockpit
    /// (`TaxModuleView`, Summe über alle Immobilien) auch bei Objekten ohne vollständige Stammdaten
    /// nicht abstürzen und korrekt mit 0 statt mit falschen/undefinierten Werten in die Summe
    /// einfließen – kein Kaufpreis, keine Einheiten, kein Baujahr.
    func testPropertyWithoutMasterDataContributesZeroToPortfolioSums() {
        let property = Property()
        XCTAssertEqual(property.annualColdRent(forYear: 2026), 0)
        XCTAssertEqual(property.werbungskosten(forYear: 2026), 0)
        XCTAssertEqual(property.totalAfa(forYear: 2026), 0)
        XCTAssertEqual(property.estimatedTaxableResult(forYear: 2026), 0)
    }

    /// Ohne Kaufdatum (nur Baujahr erfasst) lieferte `cumulativeBuildingAfA` zuvor keine echte
    /// Summe über mehrere Jahre, sondern nur den Betrag eines einzelnen Jahres – im Widerspruch zur
    /// Gebäudeabschreibungs-PDF (`PropertyDetailView.gebaeudeAfaReportURL`), die für denselben Fall
    /// bereits korrekt ab dem Baujahr akkumulierte. Fund aus einer gezielten Suche nach weiteren
    /// Fällen desselben Musters wie die beiden bereits behobenen AfA-Deckelungsbugs.
    func testCumulativeBuildingAfaFallsBackToConstructionYearWithoutPurchaseDate() {
        let property = Property(purchasePrice: 300_000, landValue: 50_000, constructionYear: 1990)
        XCTAssertNil(property.purchaseDate)
        XCTAssertEqual(property.buildingValue, 250_000, accuracy: 0.01)
        XCTAssertEqual(property.afaRatePercent, 2.0)

        // 15 Jahre (1990...2004) à 5.000 €/Jahr = 75.000 € – wie im PDF-Report, nicht nur 5.000 €
        // für ein einzelnes Jahr.
        XCTAssertEqual(property.cumulativeBuildingAfA(uptoYear: 2004), 75_000, accuracy: 0.01)
        XCTAssertEqual(property.remainingBuildingBookValue(afterYear: 2004), 175_000, accuracy: 0.01)

        // Deckelung greift weiterhin: nach 50 Jahren (250.000 / 5.000) vollständig abgeschrieben.
        XCTAssertEqual(property.cumulativeBuildingAfA(uptoYear: 2039), 250_000, accuracy: 0.01)
        XCTAssertEqual(property.remainingBuildingBookValue(afterYear: 2039), 0, accuracy: 0.01)
    }

    func testBuildingAfaRateByConstructionYear() {
        XCTAssertEqual(Property(constructionYear: 2024).defaultAfaRatePercent, 3.0)
        XCTAssertEqual(Property(constructionYear: 1920).defaultAfaRatePercent, 2.5)
        XCTAssertEqual(Property(constructionYear: 1960).defaultAfaRatePercent, 2.0)
    }

    /// Deckt die im Design-Audit geforderte Prüfung ab: der AfA-Report leitet seine „Jahresreihe
    /// Gebäude" seit dem Fix aus `cumulativeBuildingAfA`/`remainingBuildingBookValue` ab, statt die
    /// Jahresbeträge selbst unbegrenzt aufzusummieren. Ohne die Deckelung hier würde die Tabelle bei
    /// einem weit in der Zukunft liegenden Betrachtungsjahr über den Gebäudewert hinaus abschreiben.
    func testCumulativeBuildingAfaCapsAtBuildingValueAcrossManyYears() {
        // Gebäudewert 240.000 € bei 2 %/Jahr → nach genau 50 Jahren vollständig abgeschrieben.
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2000, 1, 1), landValue: 60_000, constructionYear: 1998)
        XCTAssertEqual(property.cumulativeBuildingAfA(uptoYear: 2049), 240_000, accuracy: 0.01)
        XCTAssertEqual(property.remainingBuildingBookValue(afterYear: 2049), 0, accuracy: 0.01)

        // Weit darüber hinaus (z.B. Report für ein Steuerjahr in ferner Zukunft gewählt) darf die
        // kumulierte Summe nicht über den Gebäudewert hinauswachsen, auch wenn `buildingAfA(forYear:)`
        // für sich genommen weiterhin den festen Jahresbetrag zurückgibt.
        XCTAssertEqual(property.buildingAfA(forYear: 2080), 4_800, accuracy: 0.01)
        XCTAssertEqual(property.cumulativeBuildingAfA(uptoYear: 2080), 240_000, accuracy: 0.01)
        XCTAssertEqual(property.remainingBuildingBookValue(afterYear: 2080), 0, accuracy: 0.01)

        // Der im AfA-Report verwendete Jahresbetrag (Differenz zur Vorjahres-Kumulation) muss nach
        // vollständiger Abschreibung auf 0 fallen, nicht weiter den festen Jahressatz ausweisen.
        let deltaAfterFullDepreciation = property.cumulativeBuildingAfA(uptoYear: 2080) - property.cumulativeBuildingAfA(uptoYear: 2079)
        XCTAssertEqual(deltaAfterFullDepreciation, 0, accuracy: 0.01)
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

    /// Herstellungskosten (`usesBuildingAfaRate`) haben laut `depreciation(forYear:)` bewusst kein
    /// eigenes Laufzeitende (wie die Gebäude-AfA selbst) – ohne die Deckelung in
    /// `cumulativeDepreciation(uptoYear:)` würde die kumulierte Summe bei einem weit in der Zukunft
    /// liegenden Jahr über die Bemessungsgrundlage hinauswachsen (gleicher Fehlerfall wie bei der
    /// Gebäude-AfA-Jahresreihe, siehe `testCumulativeBuildingAfaCapsAtBuildingValueAcrossManyYears`).
    func testCumulativeDepreciationCapsAtBasisForBuildingRateAssets() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2000, 1, 1), landValue: 60_000, constructionYear: 1998)
        let asset = DepreciableAsset(name: "Dachsanierung", category: .improvement, cost: 24_000, placedInServiceDate: calendarDate(2000, 1, 1))
        asset.property = property
        context.insert(property)
        context.insert(asset)

        // 2 %/Jahr von 24.000 € → nach 50 Jahren vollständig abgeschrieben.
        XCTAssertEqual(asset.cumulativeDepreciation(uptoYear: 2049), 24_000, accuracy: 0.01)
        XCTAssertEqual(asset.remainingDepreciationBookValue(afterYear: 2049), 0, accuracy: 0.01)

        // Weit darüber hinaus darf die Summe nicht über die Bemessungsgrundlage hinauswachsen, auch
        // wenn `depreciation(forYear:)` für sich genommen weiterhin den festen Jahresbetrag liefert.
        XCTAssertEqual(asset.depreciation(forYear: 2080), 480, accuracy: 0.01)
        XCTAssertEqual(asset.cumulativeDepreciation(uptoYear: 2080), 24_000, accuracy: 0.01)
        XCTAssertEqual(asset.remainingDepreciationBookValue(afterYear: 2080), 0, accuracy: 0.01)
    }

    // MARK: - Kaltmiete

    /// Deckt den vom Recherche-Agenten gefundenen Fund ab: `Tenancy.coldRentContribution(from:to:)`
    /// ist jetzt die gemeinsame Basis für `Property.annualColdRent(forYear:)` UND die
    /// Dashboard-Kennzahl je gewähltem Zeitraum. Ein unterjährig (am 20. eines Monats) begonnenes
    /// Mietverhältnis muss den Startmonat trotzdem voll anteilig zählen – die alte, inzwischen
    /// entfernte Tag-1-Stichprobe im Dashboard hätte für genau diesen Monat 0 € geliefert.
    func testColdRentContributionCountsPartialStartMonthFully() {
        let property = Property(name: "Test")
        let unit = Unit(name: "1. OG")
        unit.property = property
        let tenancy = Tenancy(startDate: calendarDate(2026, 3, 20), coldRent: 1_000)
        tenancy.unit = unit
        context.insert(property)
        context.insert(unit)
        context.insert(tenancy)

        let monthStart = calendarDate(2026, 3, 1)
        let monthEnd = calendarDate(2026, 3, 31)
        XCTAssertEqual(tenancy.coldRentContribution(from: monthStart, to: monthEnd), 1_000, accuracy: 0.01)

        // Beide Stellen müssen für denselben Zeitraum exakt dieselbe Zahl liefern.
        XCTAssertEqual(property.annualColdRent(forYear: 2026), tenancy.coldRentContribution(from: calendarDate(2026, 1, 1), to: calendarDate(2026, 12, 31)), accuracy: 0.01)
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

    /// Prüft die jahresweise Simulation über mehr als ein Jahr hinweg: bei einem Annuitätendarlehen
    /// sinkt der Zinsanteil und steigt der Tilgungsanteil von Jahr zu Jahr, weil sich beide auf die
    /// jeweils aktuelle (fallende) Restschuld beziehen – ein reiner Eins-Jahr-Test könnte eine
    /// falsche, nicht kumulierende Implementierung nicht von der korrekten unterscheiden.
    func testLoanBreakdownCompoundsDecliningBalanceAcrossYears() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2024, 1, 1), landValue: 60_000)
        property.loanAmount = 100_000
        property.interestRatePercent = 5.0
        property.initialRepaymentRatePercent = 2.0
        property.loanStartDate = calendarDate(2024, 1, 1)
        XCTAssertEqual(property.annualAnnuity, 7_000, accuracy: 0.01)

        guard let year1 = property.loanBreakdown(forYear: 2024) else {
            return XCTFail("Finanzierung sollte für 2024 einen Zins-/Tilgungssplit liefern.")
        }
        XCTAssertEqual(year1.interest, 5_000, accuracy: 0.01)
        XCTAssertEqual(year1.principal, 2_000, accuracy: 0.01)
        XCTAssertEqual(year1.remainingBalance, 98_000, accuracy: 0.01)

        // Jahr 2: Zins auf die gesunkene Restschuld (98.000 statt 100.000) → weniger Zins, mehr Tilgung.
        guard let year2 = property.loanBreakdown(forYear: 2025) else {
            return XCTFail("Finanzierung sollte für 2025 einen Zins-/Tilgungssplit liefern.")
        }
        XCTAssertEqual(year2.interest, 4_900, accuracy: 0.01)
        XCTAssertEqual(year2.principal, 2_100, accuracy: 0.01)
        XCTAssertEqual(year2.remainingBalance, 95_900, accuracy: 0.01)
    }

    // MARK: - Cashflow

    /// `freeCashFlow(forYear:)` speist die Cashflow-Kacheln in PropertyDetailView/TaxModule, war
    /// aber bisher komplett ungetestet. Prüft, dass Kaltmiete, Barausgaben (außer Finanzierung) und
    /// Annuität korrekt zusammenspielen, und dass `operativeCashFlow` zusätzlich die umlagefähigen
    /// Betriebskosten abzieht (hier 0, da keine Nebenkostenabrechnung erfasst ist).
    func testFreeCashFlowSubtractsExpensesAndAnnuityFromColdRent() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2024, 1, 1), landValue: 60_000)
        property.loanAmount = 100_000
        property.interestRatePercent = 5.0
        property.initialRepaymentRatePercent = 2.0
        property.loanStartDate = calendarDate(2024, 1, 1)
        context.insert(property)

        let unit = Unit(name: "1. OG")
        unit.property = property
        context.insert(unit)

        let tenancy = Tenancy(startDate: calendarDate(2024, 1, 1), coldRent: 1_000)
        tenancy.unit = unit
        context.insert(tenancy)

        let maintenance = Expense(date: calendarDate(2024, 6, 1), amount: 1_500, category: .other, taxTreatment: .maintenanceExpense)
        maintenance.property = property
        context.insert(maintenance)

        // Kaltmiete 12.000 € (12 × 1.000 €) − Barausgaben 1.500 € − Annuität 7.000 € (100.000 € × 7 %) = 3.500 €.
        XCTAssertEqual(property.annualColdRent(forYear: 2024), 12_000, accuracy: 0.01)
        XCTAssertEqual(property.freeCashFlow(forYear: 2024), 3_500, accuracy: 0.01)
        // Ohne erfasste Nebenkostenabrechnung sind die umlagefähigen Kosten 0 € → identisch zum freien Cashflow.
        XCTAssertEqual(property.operativeCashFlow(forYear: 2024), 3_500, accuracy: 0.01)
    }

    // MARK: - Mietrückstände

    /// `Tenancy.arrearsBalance` ist die Grundlage der Mietrückstands-Anzeige in Zahlungen/Dashboard
    /// (durchgängig mit echten Zahlen im Simulator gezeigt), hatte bisher aber keinen eigenen Test:
    /// ein Monat ohne erfasste Zahlung muss voll als offen zählen, eine Teilzahlung nur anteilig.
    func testArrearsBalanceAccumulatesUnpaidAndPartialMonths() {
        let tenancy = Tenancy(startDate: calendarDate(2026, 1, 1), coldRent: 800, utilityAdvance: 200)
        context.insert(tenancy)

        let january = RentPayment(dueDate: calendarDate(2026, 1, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        january.tenancy = tenancy
        january.markPaid(date: calendarDate(2026, 1, 5)) // volle Zahlung (amount = totalDue)
        context.insert(january)

        // Februar: bewusst keine Zahlung erfasst -> muss voll als Rückstand zählen.

        let march = RentPayment(dueDate: calendarDate(2026, 3, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        march.tenancy = tenancy
        march.markPaid(amount: 400, date: calendarDate(2026, 3, 10)) // Teilzahlung
        context.insert(march)

        // Januar 0 € offen, Februar 1.000 € offen, März 1.000 − 400 = 600 € offen.
        XCTAssertEqual(tenancy.arrearsBalance(upTo: calendarDate(2026, 3, 31)), 1_600, accuracy: 0.01)
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
