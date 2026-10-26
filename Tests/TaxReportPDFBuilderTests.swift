import XCTest
import SwiftData
import PDFKit
@testable import Mietverwaltung

/// Tests für `TaxReportPDFBuilder` – bisher nur indirekt über die Modellrechnungen abgedeckt,
/// nie direkt auf Kapitel-Ebene. `PDFExporter.renderPDF` zeichnet Text direkt in den PDF-Kontext
/// statt ihn zu rastern (siehe Kommentar dort) – die erzeugten PDFs sind also durchsuchbar, und
/// `PDFPage.string` liefert den tatsächlich sichtbaren Text zurück. Das nutzen diese Tests, um die
/// Kapitelauswahl je `TaxReportKind` zu prüfen, ohne die privaten Chapter-Bauer-Funktionen selbst
/// testbar machen zu müssen.
@MainActor
final class TaxReportPDFBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            Property.self, Unit.self, Tenant.self, Tenancy.self, RentPayment.self, Expense.self, Document.self,
            DepreciableAsset.self, UtilityStatement.self, UtilityCostLineItem.self, Landlord.self,
            RemainingUsefulLifeAppraisal.self, WirtschaftsplanStatement.self, WirtschaftsplanLineItem.self,
            TrackedYear.self, TaxChecklistItem.self, ThreeYearThresholdCase.self, ThresholdExpenseAssessment.self,
            CapitalizationDecision.self, TravelExpense.self, HomeOfficeEntry.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func calendarDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    /// Extrahiert den vollständigen, tatsächlich sichtbaren Text aller Seiten eines erzeugten PDFs,
    /// mit auf je ein Leerzeichen normalisierten Whitespace-Läufen (Zeilenumbrüche durch
    /// PDF-internen Textumbruch sollen Teilstring-Prüfungen nicht künstlich zum Scheitern bringen).
    private func extractText(from url: URL?) throws -> String {
        let url = try XCTUnwrap(url, "PDF wurde nicht erzeugt")
        let document = try XCTUnwrap(PDFDocument(url: url), "PDF konnte nicht gelesen werden")
        let raw = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        return raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Legt eine Immobilie mit Gebäudewert > 0 (Voraussetzung für `buildAfaChapters`) sowie eine
    /// 15-%-Prüfung mit genau einer sicher einzubeziehenden Erhaltungsaufwand-Position an.
    private func makePropertyWithThresholdCase() throws -> (property: Property, thresholdCase: ThreeYearThresholdCase, expense: Expense) {
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000, constructionYear: 1998)
        context.insert(property)
        let thresholdCase = ThreeYearThresholdCase(periodStart: calendarDate(2023, 1, 1), periodEnd: calendarDate(2025, 12, 31))
        thresholdCase.property = property
        context.insert(thresholdCase)

        let expense = Expense(date: calendarDate(2023, 6, 1), amount: 11_900, title: "Badsanierung", taxTreatment: .maintenanceExpense)
        expense.vatRatePercent = 19
        expense.property = property
        context.insert(expense)

        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: expense)?.status = .certain

        return (property, thresholdCase, expense)
    }

    // MARK: - Anforderung 6: 15-%-Grenze im laufenden Betrieb nur nach bewusster Aktion

    func testOngoingReportOmitsThresholdChapterByDefault() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("15-%-Grenze"), "Ohne ausdrückliche Anforderung darf der Jahresreport die 15-%-Grenze nicht enthalten.")
    }

    func testOngoingReportIncludesThresholdChapterWhenRequested() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023), includeThresholdCheck: true)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("15-%-Grenze – Ergebnisübersicht"), "Nach ausdrücklicher Anforderung muss die 15-%-Grenze enthalten sein.")
    }

    func testOngoingReportWithThresholdHasMorePagesThanWithout() throws {
        // Beide Aufrufe erzeugen denselben Dateinamen (Property/Kind unverändert) – der zweite
        // Aufruf überschreibt die Datei des ersten. Deshalb muss die erste PDF-Seitenzahl
        // ausgelesen werden, BEVOR der zweite Aufruf dieselbe Datei überschreibt.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (urlWithout, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023))
        let pagesWithout = try XCTUnwrap(PDFDocument(url: XCTUnwrap(urlWithout))).pageCount

        let (urlWith, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023), includeThresholdCheck: true)
        let pagesWith = try XCTUnwrap(PDFDocument(url: XCTUnwrap(urlWith))).pageCount

        XCTAssertGreaterThan(pagesWith, pagesWithout, "Das zusätzliche Kapitel muss sich auch in der Seitenzahl niederschlagen.")
    }

    // MARK: - Anforderung 5: Erstanlage enthält die 15-%-Grenze immer

    func testInitialSetupAlwaysIncludesThresholdChapter() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("15-%-Grenze"), "Die Erstanlage muss die 15-%-Grenze ohne gesonderte Anforderung enthalten.")
    }

    // MARK: - Anforderung 4: AfA im Jahresreport nur als Endbetrag

    func testOngoingReportShowsAfaOnlyAsSingleLineNotFullHerleitung() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("AfA-Herleitung – Gebäude"), "Der Jahresreport darf die volle AfA-Herleitung nicht mehr enthalten.")
        XCTAssertTrue(text.contains("AfA Gebäude"), "Die Anlage V muss die AfA weiterhin als Einzeiler zeigen.")
        XCTAssertTrue(text.contains("siehe AfA-Bericht"), "Die Anlage V muss auf den AfA-Bericht für die vollständige Herleitung verweisen.")
    }

    func testStandaloneAfaReportContainsFullTabularHerleitung() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        // "Jährliche Gebäude-AfA" wird als Kennzahl in der hervorgehobenen Box oben GROSSGESCHRIEBEN
        // dargestellt (siehe resultBox), erscheint im Fließtext also nicht mehr mit gemischter
        // Groß-/Kleinschreibung – das ist beabsichtigt (Headline-Extraktion), nicht geprüft wird
        // hier daher die Originalschreibweise, sondern die tatsächlich sichtbare Variante.
        for expected in ["AfA-Herleitung – Gebäude", "KAUFDATEN", "ANSCHAFFUNGSNEBENKOSTEN", "AUFTEILUNG GRUND UND BODEN", "AFA-BERECHNUNG", "JÄHRLICHE GEBÄUDE-AFA", "KUMULIERT"] {
            XCTAssertTrue(text.contains(expected), "Erwarteter Abschnitt „\(expected)“ fehlt in der tabellarischen AfA-Herleitung.")
        }
    }

    // MARK: - CapitalizationDecision: Überleitungs-Kapitel nur mit tatsächlicher Entscheidung

    func testThresholdReportOmitsBridgeChapterWithoutCapitalizationDecision() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023), includeThresholdCheck: true)
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Überleitung zur AfA"), "Ohne Aktivierungs-Entscheidung darf kein Überleitungs-Kapitel erscheinen.")
    }

    func testThresholdReportIncludesBridgeChapterAfterCapitalizationDecision() throws {
        let (property, thresholdCase, expense) = try makePropertyWithThresholdCase()
        CapitalizationDecision.create(from: [expense], property: property, thresholdCase: thresholdCase, reason: "Testaktivierung", context: context)

        let thresholdURL = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023), includeThresholdCheck: true).url
        let thresholdText = try extractText(from: thresholdURL)
        XCTAssertTrue(thresholdText.contains("15-%-Grenze – Überleitung zur AfA"), "Nach einer Aktivierungs-Entscheidung muss das Überleitungs-Kapitel im 15-%-Report erscheinen.")

        let afaURL = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023)).url
        let afaText = try extractText(from: afaURL)
        XCTAssertTrue(afaText.contains("AfA-Herleitung – Maßnahmen und Änderungen"), "Nach einer Aktivierungs-Entscheidung muss das Kapitel „Maßnahmen und Änderungen“ im AfA-Bericht erscheinen.")
    }

}
