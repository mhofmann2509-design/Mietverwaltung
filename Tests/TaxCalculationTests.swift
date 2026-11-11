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
        let schema = AppSchema.schema
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

    func testBuildingAfaUsesEconomicTransferDateOverPurchaseDateWhenSet() {
        // Beurkundung im Januar, Übergang Nutzen/Lasten erst im Juli – maßgeblich für den
        // AfA-Beginn ist der Übergang (§7 EStG), nicht das Beurkundungsdatum.
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2024, 1, 10), landValue: 60_000, constructionYear: 1998)
        property.economicTransferDate = calendarDate(2024, 7, 15)
        let expected = 240_000 * 0.02 * 6.0 / 12.0
        XCTAssertEqual(property.buildingAfA(forYear: 2024), expected, accuracy: 0.01, "Ohne Übergangsdatum würde der volle Jahresbetrag ab Januar berechnet statt anteilig ab Juli.")
        XCTAssertEqual(property.afaStartDate, property.economicTransferDate)
    }

    func testBuildingAfaFallsBackToPurchaseDateWithoutEconomicTransferDate() {
        // Unverändertes Verhalten für Properties ohne erfassten Übergang – keine rückwirkende
        // Änderung bereits angezeigter AfA-Werte.
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2024, 7, 15), landValue: 60_000, constructionYear: 1998)
        XCTAssertNil(property.economicTransferDate)
        XCTAssertEqual(property.afaStartDate, property.purchaseDate)
        let expected = 240_000 * 0.02 * 6.0 / 12.0
        XCTAssertEqual(property.buildingAfA(forYear: 2024), expected, accuracy: 0.01)
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

    func testPossibleAdditionalAmountIncludesCertainPositionsWithMissingNetAmount() {
        // Regressionstest: eine bereits als "sicher einzubeziehen" eingestufte Position ohne
        // hinterlegten USt-Satz trug früher lautlos mit 0 € zu `includedNetTotal` bei und wurde
        // auch nicht in `possibleAdditionalAmount` sichtbar – die Kennzahl "X € von Y €" verschleierte
        // dadurch, dass tatsächlich noch ein offener Betrag im Raum steht.
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 1_190, title: "Malerarbeiten", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain

        XCTAssertEqual(thresholdCase.includedNetTotal, 0, "Ohne Netto-Betrag fließt die Position weiterhin mit 0 € in die gesicherte Summe ein.")
        XCTAssertGreaterThan(thresholdCase.possibleAdditionalAmount, 0, "Die Position muss trotz fehlenden Netto-Betrags als möglicher zusätzlicher Betrag sichtbar bleiben, nicht lautlos verschwinden.")
        XCTAssertEqual(thresholdCase.possibleAdditionalAmount, 1_190 / 1.19, accuracy: 0.01)
    }

    func testPossibleAdditionalAmountIncludesUnclassifiedPositionsWithMissingNetAmount() {
        // Regressionstest für dieselbe Fehlerklasse wie oben, aber für eine noch gar nicht
        // eingeordnete (nicht "sicher") Position: der erste Fix deckte nur den klassifizierten
        // Fall ab; eine unklassifizierte Position ohne USt.-Satz fiel weiterhin lautlos mit 0 €
        // aus `possibleAdditionalAmount`, obwohl sie der häufigste Fall ist (frisch importierte,
        // noch nicht geprüfte Ausgabe).
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 1_190, title: "Dachreparatur", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        // Bewusst keine Statusänderung – bleibt `.unclassified`.

        XCTAssertEqual(thresholdCase.assessment(for: expense)?.status, .unclassified)
        XCTAssertGreaterThan(thresholdCase.possibleAdditionalAmount, 0, "Eine unklassifizierte Position ohne Netto-Betrag muss ebenfalls als möglicher Betrag sichtbar bleiben.")
        XCTAssertEqual(thresholdCase.possibleAdditionalAmount, 1_190 / 1.19, accuracy: 0.01)
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

    // MARK: - Ausgaben (Immobilie + Einheiten)

    /// `allExpenses(forYear:)` ist die gemeinsame Grundlage von `maintenanceExpenses`,
    /// `otherDeductibleExpenses`, `capitalizedExpenses` und `totalExpenses`, bisher aber nie direkt
    /// getestet. Prüft die Vereinigung aus direkt der Immobilie und einer ihrer Einheiten
    /// zugeordneten Ausgaben, ohne eine Ausgabe doppelt zu zählen.
    func testAllExpensesCombinesPropertyAndUnitExpensesWithoutDuplicates() {
        let property = Property(name: "Test")
        context.insert(property)
        let unit = Unit(name: "1. OG")
        unit.property = property
        context.insert(unit)

        let propertyExpense = Expense(date: calendarDate(2026, 2, 1), amount: 300, taxTreatment: .maintenanceExpense)
        propertyExpense.property = property
        context.insert(propertyExpense)

        let unitExpense = Expense(date: calendarDate(2026, 5, 1), amount: 150, taxTreatment: .otherDeductible)
        unitExpense.unit = unit
        context.insert(unitExpense)

        // Ausgabe eines anderen Jahres darf nicht mitgezählt werden.
        let otherYearExpense = Expense(date: calendarDate(2025, 12, 1), amount: 999, taxTreatment: .maintenanceExpense)
        otherYearExpense.property = property
        context.insert(otherYearExpense)

        XCTAssertEqual(property.allExpenses(forYear: 2026).count, 2)
        XCTAssertEqual(property.maintenanceExpenses(forYear: 2026), 300, accuracy: 0.01)
        XCTAssertEqual(property.otherDeductibleExpenses(forYear: 2026), 150, accuracy: 0.01)
        XCTAssertEqual(property.totalExpenses(forYear: 2026), 450, accuracy: 0.01)
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

    // MARK: - 15-%-Grenze: Zeitraum-Zuordnung, Grenzfall, ungeklärte Positionen

    func testCandidateExpensesPrefersCompletionDateOverInvoiceDate() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        // Rechnungsdatum außerhalb des Zeitraums, aber Fertigstellung innerhalb → wird einbezogen.
        let finishedInPeriod = Expense(date: calendarDate(2022, 11, 1), amount: 1_190, title: "Dachsanierung", taxTreatment: .maintenanceExpense)
        finishedInPeriod.completionDate = calendarDate(2023, 2, 1)
        finishedInPeriod.property = property
        context.insert(finishedInPeriod)

        // Rechnungsdatum innerhalb, aber Fertigstellung außerhalb → wird ausgeschlossen.
        let finishedBeforePeriod = Expense(date: calendarDate(2023, 3, 1), amount: 1_190, title: "Vorarbeiten", taxTreatment: .maintenanceExpense)
        finishedBeforePeriod.completionDate = calendarDate(2022, 10, 1)
        finishedBeforePeriod.property = property
        context.insert(finishedBeforePeriod)

        let candidateIDs = Set(thresholdCase.candidateExpenses.map(\.persistentModelID))
        XCTAssertTrue(candidateIDs.contains(finishedInPeriod.persistentModelID))
        XCTAssertFalse(candidateIDs.contains(finishedBeforePeriod.persistentModelID))
    }

    func testThresholdCaseExactlyAtThresholdCountsAsExceeded() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        // Bemessungsgrundlage 240.000 € → Schwelle exakt 36.000 € netto.
        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 42_840, title: "Sanierung", taxTreatment: .maintenanceExpense)
        expense.vatRatePercent = 19 // netto exakt 36.000 €
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain

        XCTAssertEqual(thresholdCase.includedNetTotal, 36_000, accuracy: 0.01)
        XCTAssertEqual(thresholdCase.status, .exceeded, "Der Grenzfall genau an der 15-%-Schwelle gilt bereits als überschritten, nicht als nur erreicht.")
    }

    func testPossibleAdditionalAmountOnlySumsUnclassifiedPositions() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let certain = Expense(date: calendarDate(2023, 4, 1), amount: 1_190, title: "Sicher", taxTreatment: .maintenanceExpense)
        certain.vatRatePercent = 19
        certain.property = property
        context.insert(certain)

        let open = Expense(date: calendarDate(2023, 5, 1), amount: 2_380, title: "Offen", taxTreatment: .maintenanceExpense)
        open.vatRatePercent = 19
        open.property = property
        context.insert(open)

        let excluded = Expense(date: calendarDate(2023, 6, 1), amount: 595, title: "Ausgeschlossen", taxTreatment: .maintenanceExpense)
        excluded.vatRatePercent = 19
        excluded.property = property
        context.insert(excluded)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: certain)?.status = .certain
        thresholdCase.assessment(for: excluded)?.status = .excluded
        // `open` bleibt unclassified.

        XCTAssertEqual(thresholdCase.possibleAdditionalAmount, open.netAmount ?? -1, accuracy: 0.01, "Nur ungeklärte Positionen zählen zum möglichen Zusatzbetrag, weder einbezogene noch ausgeschlossene.")
    }

    // MARK: - CapitalizationDecision: Brücke zwischen 15-%-Grenze und AfA

    func testCapitalizationDecisionCreatesImprovementAssetAndMarksExpensesCapitalized() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 20_000, title: "Badsanierung", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)

        let decision = CapitalizationDecision.create(from: [expense], property: property, thresholdCase: nil, reason: "Anschaffungsnahe Herstellungskosten", context: context)

        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.totalAmount, 20_000)
        XCTAssertEqual(decision?.effectiveYear, 2023)
        XCTAssertEqual(decision?.resultingAsset?.category, .improvement)
        XCTAssertEqual(decision?.resultingAsset?.cost, 20_000)
        XCTAssertEqual(decision?.resultingAsset?.property, property)
        XCTAssertEqual(expense.taxTreatment, .capitalized, "Die Quell-Ausgabe muss nach der Aktivierung als Herstellungskosten geführt werden, nicht mehr als Erhaltungsaufwand.")
        XCTAssertEqual(expense.capitalizationDecision, decision)
    }

    func testCapitalizationDecisionExpenseIsExcludedFromFutureThresholdCandidates() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 20_000, title: "Badsanierung", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)
        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain
        XCTAssertEqual(thresholdCase.candidateExpenses.count, 1)

        CapitalizationDecision.create(from: [expense], property: property, thresholdCase: thresholdCase, reason: "", context: context)

        XCTAssertTrue(thresholdCase.candidateExpenses.isEmpty, "Eine aktivierte Ausgabe darf nicht erneut als 15-%-Kandidat auftauchen (kein Doppelansatz).")
    }

    func testCapitalizationDecisionDoesNotDoubleLinkAlreadyCapitalizedExpenses() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000)
        context.insert(property)

        let expenseA = Expense(date: calendarDate(2023, 6, 1), amount: 10_000, title: "Teil A", taxTreatment: .maintenanceExpense)
        expenseA.property = property
        context.insert(expenseA)
        let expenseB = Expense(date: calendarDate(2023, 6, 15), amount: 5_000, title: "Teil B", taxTreatment: .maintenanceExpense)
        expenseB.property = property
        context.insert(expenseB)

        let firstDecision = CapitalizationDecision.create(from: [expenseA], property: property, thresholdCase: nil, reason: "", context: context)
        XCTAssertNotNil(firstDecision)

        // Zweiter Aufruf mit A (bereits verknüpft) + B (neu): nur B darf berücksichtigt werden.
        let secondDecision = CapitalizationDecision.create(from: [expenseA, expenseB], property: property, thresholdCase: nil, reason: "", context: context)
        XCTAssertEqual(secondDecision?.sourceExpenses?.count, 1)
        XCTAssertEqual(secondDecision?.totalAmount, 5_000)
        XCTAssertEqual(expenseA.capitalizationDecision, firstDecision, "Eine bereits aktivierte Ausgabe darf durch einen weiteren Aufruf nicht umgehängt werden.")

        // Dritter Aufruf nur mit der bereits verknüpften Ausgabe A: keine neue Entscheidung.
        let thirdDecision = CapitalizationDecision.create(from: [expenseA], property: property, thresholdCase: nil, reason: "", context: context)
        XCTAssertNil(thirdDecision)
    }

    func testCapitalizationDecisionIncreasesTotalAfaOnlyFromEffectiveYearOnward() {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2020, 1, 1), landValue: 60_000, constructionYear: 1998)
        context.insert(property)
        // Gebäudewert 240.000 €, Satz 2 % → 4.800 €/Jahr Gebäude-AfA (siehe testBuildingAfaFullYear).
        let afaBeforeDecision2022 = property.totalAfa(forYear: 2022)
        XCTAssertEqual(afaBeforeDecision2022, 4_800, accuracy: 0.01)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 20_000, title: "Badsanierung", taxTreatment: .maintenanceExpense)
        expense.property = property
        context.insert(expense)
        CapitalizationDecision.create(from: [expense], property: property, thresholdCase: nil, reason: "", context: context)

        // Vor dem Wirksamkeitsjahr (2022 < 2023): unverändert, keine rückwirkende Änderung.
        XCTAssertEqual(property.totalAfa(forYear: 2022), 4_800, accuracy: 0.01)

        // Im Wirksamkeitsjahr selbst: Gebäude-AfA + monatsanteilige AfA auf das neue Wirtschaftsgut
        // (20.000 € × 2 % × 7/12, da ab Juni/Monat 6 → 13-6=7 Monate).
        let expectedAssetAfa2023 = 20_000 * 0.02 * 7.0 / 12.0
        XCTAssertEqual(property.totalAfa(forYear: 2023), 4_800 + expectedAssetAfa2023, accuracy: 0.01)

        // Folgejahr: volle Jahres-AfA auf das Wirtschaftsgut.
        XCTAssertEqual(property.totalAfa(forYear: 2024), 4_800 + 20_000 * 0.02, accuracy: 0.01)
    }

    // MARK: - Einzelposten der Anschaffungsnebenkosten (Makler/Notar/Auflassungsvormerkung)

    func testHasItemizedAncillaryCostsIsFalseWhenAllPositionsAreZero() {
        let property = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 28_000, landValue: 60_000)
        XCTAssertFalse(property.hasItemizedAncillaryCosts)
        XCTAssertEqual(property.purchaseOtherAncillaryCosts, 28_000, accuracy: 0.01)
    }

    func testHasItemizedAncillaryCostsIsTrueAsSoonAsOnePositionIsSet() {
        let property = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 28_000, landValue: 60_000)
        property.purchaseBrokerCosts = 10_000
        XCTAssertTrue(property.hasItemizedAncillaryCosts)
    }

    func testPurchaseOtherAncillaryCostsIsTheReconcilingResidual() {
        let property = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 28_000, landValue: 60_000)
        property.purchaseBrokerCosts = 10_000
        property.purchaseNotaryCosts = 5_000
        property.purchaseLandRegistryCosts = 500
        // 28.000 − 10.000 − 5.000 − 500 = 12.500 Rest, der nicht in den Einzelposten erfasst ist.
        XCTAssertEqual(property.purchaseOtherAncillaryCosts, 12_500, accuracy: 0.01)
    }

    func testPurchaseOtherAncillaryCostsWithOnlyOnePositionMaintained() {
        // Nur Maklerkosten gepflegt, Notar/Auflassungsvormerkung bleiben bei 0 – der Rest muss
        // trotzdem korrekt als „Sonstige“ berechnet werden, nicht nur bei vollständiger Pflege.
        let property = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 6_500, landValue: 60_000)
        property.purchaseBrokerCosts = 3_500
        XCTAssertTrue(property.hasItemizedAncillaryCosts)
        XCTAssertEqual(property.purchaseOtherAncillaryCosts, 3_000, accuracy: 0.01)
    }

    func testPurchaseOtherAncillaryCostsNeverGoesNegativeWhenItemsExceedTheTotal() {
        // Einzelposten dürfen die Gesamtsumme übersteigen (z.B. unvollständig gepflegte Summe) –
        // der Rest darf dadurch nie negativ werden, nur auf 0 gedeckelt.
        let property = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 1_000, landValue: 60_000)
        property.purchaseBrokerCosts = 3_000
        XCTAssertEqual(property.purchaseOtherAncillaryCosts, 0, accuracy: 0.01)
    }

    func testItemizedAncillaryCostsDoNotChangeTotalAcquisitionCostOrBuildingValue() {
        // Die Einzelposten sind rein zur Darstellung gedacht – `purchaseAncillaryCosts` bleibt die
        // für alle Berechnungen maßgebliche Summe, unabhängig davon, ob/wie sie aufgeschlüsselt ist.
        let withoutBreakdown = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 28_000, landValue: 60_000)
        let withBreakdown = Property(purchasePrice: 300_000, purchaseAncillaryCosts: 28_000, landValue: 60_000)
        withBreakdown.purchaseBrokerCosts = 10_000
        withBreakdown.purchaseNotaryCosts = 5_000
        withBreakdown.purchaseLandRegistryCosts = 500

        XCTAssertEqual(withoutBreakdown.totalAcquisitionCost, withBreakdown.totalAcquisitionCost, accuracy: 0.01)
        XCTAssertEqual(withoutBreakdown.buildingValue, withBreakdown.buildingValue, accuracy: 0.01)
        XCTAssertEqual(withoutBreakdown.apportionedLandValue, withBreakdown.apportionedLandValue, accuracy: 0.01)
    }

    // MARK: - Mieterhöhung (RentIncreaseAdvisor)

    func testStandardContractNextIncreaseIs15MonthsAfterStartWithoutPriorIncrease() {
        let start = calendarDate(2024, 1, 1)
        let advice = RentIncreaseAdvisor.advice(contractType: .standard, startDate: start, lastRentIncreaseDate: nil, lastIndexAdjustmentDate: nil, upcomingStaffelDates: [])
        XCTAssertEqual(advice.nextPossibleDate, calendarDate(2025, 4, 1))
    }

    func testStandardContractNextIncreaseIs15MonthsAfterLastIncreaseNotStartDate() {
        let start = calendarDate(2020, 1, 1)
        let lastIncrease = calendarDate(2024, 1, 1)
        let advice = RentIncreaseAdvisor.advice(contractType: .standard, startDate: start, lastRentIncreaseDate: lastIncrease, lastIndexAdjustmentDate: nil, upcomingStaffelDates: [])
        XCTAssertEqual(advice.nextPossibleDate, calendarDate(2025, 4, 1))
    }

    func testIndexContractNextAdjustmentIs12MonthsAfterLastAdjustment() {
        let start = calendarDate(2020, 1, 1)
        let lastAdjustment = calendarDate(2024, 6, 1)
        let advice = RentIncreaseAdvisor.advice(contractType: .index, startDate: start, lastRentIncreaseDate: nil, lastIndexAdjustmentDate: lastAdjustment, upcomingStaffelDates: [])
        XCTAssertEqual(advice.nextPossibleDate, calendarDate(2025, 6, 1))
    }

    func testStaffelContractNextDateIsEarliestFutureStep() {
        let today = calendarDate(2025, 1, 1)
        let dates = [calendarDate(2024, 6, 1), calendarDate(2026, 1, 1), calendarDate(2025, 6, 1)]
        let advice = RentIncreaseAdvisor.advice(contractType: .staffel, startDate: calendarDate(2023, 1, 1), lastRentIncreaseDate: nil, lastIndexAdjustmentDate: nil, upcomingStaffelDates: dates, today: today)
        XCTAssertEqual(advice.nextPossibleDate, calendarDate(2025, 6, 1))
    }

    func testStaffelContractWithNoFutureStepsHasNoNextDate() {
        let today = calendarDate(2025, 1, 1)
        let advice = RentIncreaseAdvisor.advice(contractType: .staffel, startDate: calendarDate(2023, 1, 1), lastRentIncreaseDate: nil, lastIndexAdjustmentDate: nil, upcomingStaffelDates: [calendarDate(2024, 6, 1)], today: today)
        XCTAssertNil(advice.nextPossibleDate)
    }

    // MARK: - Steuererklärungs-Frist (TaxFilingStatus, § 149 AO)

    func testUnrepresentedDeadlineIsJuly31OfFollowingYear() {
        let status = TaxFilingStatus(taxYear: 2024)
        XCTAssertEqual(status.legalDeadline(usesTaxAdvisor: false), calendarDate(2025, 7, 31))
    }

    func testRepresentedDeadlineIsLastDayOfFebruaryTwoYearsLater() {
        let status = TaxFilingStatus(taxYear: 2024)
        XCTAssertEqual(status.legalDeadline(usesTaxAdvisor: true), calendarDate(2026, 2, 28))
    }

    func testDeadlineOverrideTakesPrecedenceOverLegalDeadline() {
        let status = TaxFilingStatus(taxYear: 2024, deadlineOverride: calendarDate(2025, 9, 30))
        XCTAssertEqual(status.effectiveDeadline(usesTaxAdvisor: false), calendarDate(2025, 9, 30))
        XCTAssertEqual(status.effectiveDeadline(usesTaxAdvisor: true), calendarDate(2025, 9, 30))
    }

    func testIsSubmittedReflectsSubmittedAt() {
        let status = TaxFilingStatus(taxYear: 2024)
        XCTAssertFalse(status.isSubmitted)
        status.submittedAt = .now
        XCTAssertTrue(status.isSubmitted)
    }

    // MARK: - Kautionsrückzahlung

    func testDaysSinceEndWithUnreturnedDepositIsNilWhileTenancyStillRuns() {
        let tenancy = Tenancy(startDate: calendarDate(2024, 1, 1), deposit: 1000)
        XCTAssertNil(tenancy.daysSinceEndWithUnreturnedDeposit(today: calendarDate(2025, 1, 1)))
    }

    func testDaysSinceEndWithUnreturnedDepositIsNilWithoutDeposit() {
        let tenancy = Tenancy(startDate: calendarDate(2024, 1, 1), endDate: calendarDate(2024, 6, 1), deposit: 0)
        XCTAssertNil(tenancy.daysSinceEndWithUnreturnedDeposit(today: calendarDate(2025, 1, 1)))
    }

    func testDaysSinceEndWithUnreturnedDepositIsNilAfterReturn() {
        let tenancy = Tenancy(startDate: calendarDate(2024, 1, 1), endDate: calendarDate(2024, 6, 1), deposit: 1000)
        tenancy.depositReturnedAt = calendarDate(2024, 7, 1)
        XCTAssertNil(tenancy.daysSinceEndWithUnreturnedDeposit(today: calendarDate(2025, 1, 1)))
    }

    func testDaysSinceEndWithUnreturnedDepositCountsFromEndDate() {
        let tenancy = Tenancy(startDate: calendarDate(2024, 1, 1), endDate: calendarDate(2024, 6, 1), deposit: 1000)
        XCTAssertEqual(tenancy.daysSinceEndWithUnreturnedDeposit(today: calendarDate(2024, 9, 1)), 92)
    }

    // MARK: - Modernisierungsmieterhöhung (§ 555c/§ 559b BGB)

    func testModernizationEarliestStartDateIsThreeMonthsAfterAnnouncement() {
        let announced = calendarDate(2025, 1, 15)
        XCTAssertEqual(RentIncreaseAdvisor.modernizationEarliestStartDate(announcedAt: announced), calendarDate(2025, 4, 15))
    }

    func testModernizationIncreaseEffectiveDateIsStartOfThirdMonthAfterReceipt() {
        // Zugang im März → wirksam ab Beginn des dritten Monats danach, also 1. Juni.
        let declaredAt = calendarDate(2025, 3, 10)
        XCTAssertEqual(RentIncreaseAdvisor.modernizationIncreaseEffectiveDate(declaredAt: declaredAt), calendarDate(2025, 6, 1))
    }
}
