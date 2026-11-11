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
        let schema = AppSchema.schema
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

    // MARK: - 15-%-Grenze erscheint ausschließlich im eigenständigen Bericht

    func testOngoingReportNeverIncludesThresholdChapter() throws {
        // Die 15-%-Grenze wird bewusst nicht mehr in den Jahresreport mit aufgenommen (auch nicht
        // optional) – sie muss unabhängig davon in jedem der ersten drei Jahre nach Erwerb separat
        // ans Finanzamt nachgereicht werden können, siehe `.standaloneThreshold`.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("15-%-Grenze"), "Der Jahresreport darf die 15-%-Grenze nicht mehr enthalten, auch nicht optional.")
    }

    func testInitialSetupNeverIncludesThresholdChapter() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("15-%-Grenze – Ergebnisübersicht"), "Die Erstanlage darf die 15-%-Grenze nicht mehr enthalten, auch nicht optional.")
    }

    func testCoverPageOmitsAusgangslageLineAndUsesCorrectTerminology() throws {
        // Direkte Nutzerrückmeldung: „Steuerliche Ausgangslage …“ entfernen, „Private Vermietung und
        // Verpachtung“ durch die in der Steuererklärung übliche Bezeichnung ersetzen.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Steuerliche Ausgangslage"), "Die Zeile „Steuerliche Ausgangslage“ darf auf dem Deckblatt nicht mehr erscheinen.")
        XCTAssertTrue(text.contains("Einkünfte aus Vermietung und Verpachtung"), "Das Deckblatt muss die Steuererklärungs-Terminologie verwenden.")
        XCTAssertFalse(text.contains("Private Vermietung und Verpachtung"), "Die alte Bezeichnung darf nicht mehr erscheinen.")
    }

    func testAfaMethodSectionOmitsRechtsgrundlageRow() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Rechtsgrundlage"), "Abschnitt D darf die Rechtsgrundlage-Zeile nicht mehr enthalten.")
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

    // MARK: - Einzelposten der Anschaffungsnebenkosten (Makler/Notar/Auflassungsvormerkung)

    func testAfaHerleitungShowsSingleSummaryLineWithoutItemizedAncillaryCosts() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Anschaffungsnebenkosten (Summe)"), "Ohne gepflegte Einzelposten muss weiterhin die Summenzeile erscheinen.")
        XCTAssertFalse(text.contains("Maklerkosten"), "Ohne gepflegte Einzelposten dürfen keine Einzelpositionen erscheinen.")
    }

    func testAfaHerleitungShowsItemizedAncillaryCostsWhenMaintained() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        property.purchaseBrokerCosts = 3_500
        property.purchaseNotaryCosts = 2_200
        property.purchaseLandRegistryCosts = 300
        property.purchaseAncillaryCosts = 6_500 // deckt Einzelposten + Rest „Sonstige Nebenkosten“

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        for expected in ["Maklerkosten", "Notarkosten", "Auflassungsvormerkung", "Sonstige Nebenkosten"] {
            XCTAssertTrue(text.contains(expected), "Erwartete Einzelposition „\(expected)“ fehlt in der aufgeschlüsselten AfA-Herleitung.")
        }
        XCTAssertFalse(text.contains("Anschaffungsnebenkosten (Summe)"), "Bei gepflegten Einzelposten darf die alte Summenzeile nicht zusätzlich erscheinen.")
    }

    func testAfaHerleitungFitsOnOnePageEvenWithItemizedAncillaryCosts() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        property.purchaseBrokerCosts = 3_500
        property.purchaseNotaryCosts = 2_200
        property.purchaseLandRegistryCosts = 300
        property.purchaseAncillaryCosts = 6_500

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(url)))
        // Anfang ("KAUFDATEN") und Ende ("Restbuchwert") des Kapitels müssen auf derselben Seite
        // stehen – die Herleitung darf trotz aufgeschlüsselter Einzelposten nicht umbrechen.
        let pageWithBoth = (0..<document.pageCount).contains { index in
            let pageText = document.page(at: index)?.string ?? ""
            return pageText.contains("KAUFDATEN") && pageText.contains("Restbuchwert")
        }
        XCTAssertTrue(pageWithBoth, "Die AfA-Herleitung darf trotz aufgeschlüsselter Nebenkosten nicht auf eine Folgeseite umbrechen.")
    }

    // MARK: - Einheitliches Design-System (Gestaltungsauftrag)

    func testLongRowLabelsAreNotTruncatedWithEllipsis() throws {
        // Regressionstest für einen Darstellungsfehler: lange Positionsbezeichnungen (z.B. die
        // Summenzeile „Anschaffungskosten gesamt (Kaufpreis + Nebenkosten)“) wurden ohne
        // `fixedSize(horizontal:false, vertical:true)` auf der Tabellenzelle abgeschnitten, statt –
        // wie gefordert – kontrolliert umzubrechen.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Anschaffungskosten gesamt (Kaufpreis + Nebenkosten)"), "Lange Positionsbezeichnungen dürfen nicht mit Auslassungszeichen abgeschnitten werden.")
        XCTAssertFalse(text.contains("…"), "Im Tabellentext darf keine Abschneidung mehr vorkommen.")
    }

    func testNumericCellsNeverWrapMidNumber() throws {
        // Regressionstest: Datums-/Betragszellen in einer überwiegend zahlenartigen Spalte wurden
        // versehentlich an der Spaltenausrichtung statt am tatsächlichen Zellinhalt festgemacht und
        // dadurch mitten in der Zahl umgebrochen ("28.10.202" / "5"), während eine lange Text-/
        // Hinweiszeile in derselben Spalte korrekt umbrechen musste statt mit „…" abgeschnitten zu
        // werden.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let asset = DepreciableAsset(name: "Einbauküche", category: .furniture, cost: 6_500, usefulLifeYears: 10, placedInServiceDate: calendarDate(2023, 6, 1))
        asset.property = property
        context.insert(asset)

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("01.06.2023"), "Ein Datum darf nicht mitten in der Zahl umgebrochen werden.")
        XCTAssertFalse(text.contains("…"), "Im Tabellentext darf keine Abschneidung vorkommen.")
    }

    func testOpenIssuesChapterIsPartOfThePDFItself() throws {
        // Auftrag Abschnitt 3G/4F: offene Punkte/fehlende Datengrundlagen gehören selbst in die
        // Unterlage, nicht nur in einen Bildschirm-Hinweis außerhalb des PDFs.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, warnings) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023))
        XCTAssertFalse(warnings.isEmpty, "Testaufbau erwartet mindestens eine Warnung (Belegverzeichnis entfällt mangels Dokumenten).")
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Beleg- und Prüfhinweise"), "Der laufende Betrieb muss ein Kapitel mit den offenen Punkten enthalten.")
        for warning in warnings {
            XCTAssertTrue(text.contains(warning), "Jede zurückgegebene Warnung muss auch im PDF selbst erscheinen.")
        }
    }

    func testInitialSetupOpenIssuesChapterUsesItsOwnTitle() throws {
        // Normaler Gebäudewert, aber ohne 15-%-Prüfung angelegt → deren Kapitel entfällt mangels
        // Datengrundlage (Warnung), die Seite 1 (Anschaffungskosten/Kaufpreisaufteilung/Gebäude-AfA)
        // wird trotzdem erzeugt.
        let property = Property(purchasePrice: 300_000, purchaseDate: calendarDate(2023, 1, 1), landValue: 60_000, constructionYear: 1998)
        context.insert(property)

        let (url, warnings) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        XCTAssertFalse(warnings.isEmpty)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Offene Punkte und Dokumentationshinweise"), "Die Erstanlage nutzt einen eigenen Titel für das Hinweis-Kapitel.")
    }

    func testAfaHerleitungOmitsSonstigeRowWhenItemizedCostsCoverTheFullTotal() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        property.purchaseBrokerCosts = 4_000
        property.purchaseNotaryCosts = 2_000
        property.purchaseLandRegistryCosts = 500
        property.purchaseAncillaryCosts = 6_500 // exakt die Summe der drei Einzelposten, kein Rest

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Sonstige Nebenkosten"), "Decken die Einzelposten die Gesamtsumme vollständig ab, darf keine Restzeile erscheinen.")
    }

    func testAfaHerleitungShowsOnlyMaintainedPositionWithPartialItemization() throws {
        // Nur Maklerkosten gepflegt – Notar/Auflassungsvormerkung bleiben 0 und dürfen nicht als
        // eigene Zeile erscheinen, der Rest läuft über „Sonstige Nebenkosten“.
        let (property, _, _) = try makePropertyWithThresholdCase()
        property.purchaseBrokerCosts = 3_500
        property.purchaseAncillaryCosts = 6_500

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Maklerkosten"), "Die gepflegte Position muss erscheinen.")
        XCTAssertTrue(text.contains("Sonstige Nebenkosten"), "Der nicht aufgeschlüsselte Rest muss als Sonstige Nebenkosten erscheinen.")
        XCTAssertFalse(text.contains("Notarkosten"), "Nicht gepflegte Positionen dürfen nicht als eigene Zeile erscheinen.")
        XCTAssertFalse(text.contains("Auflassungsvormerkung"), "Nicht gepflegte Positionen dürfen nicht als eigene Zeile erscheinen.")
    }

    func testAfaHerleitungOmitsHerstellungskostenRowWithoutCapitalizationDecision() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Herstellungskosten (ggf. aktiviert"), "Ohne Aktivierungs-Entscheidung darf keine Herstellungskosten-Zeile erscheinen.")
    }

    func testAfaHerleitungSumsMultipleCapitalizationDecisions() throws {
        let (property, thresholdCase, firstExpense) = try makePropertyWithThresholdCase()
        let secondExpense = Expense(date: calendarDate(2024, 3, 1), amount: 5_950, title: "Dachsanierung", taxTreatment: .maintenanceExpense)
        secondExpense.vatRatePercent = 19
        secondExpense.property = property
        context.insert(secondExpense)
        thresholdCase.ensureAssessments(context: context)
        thresholdCase.assessment(for: secondExpense)?.status = .certain

        CapitalizationDecision.create(from: [firstExpense], property: property, thresholdCase: thresholdCase, reason: "Erste Maßnahme", context: context)
        CapitalizationDecision.create(from: [secondExpense], property: property, thresholdCase: thresholdCase, reason: "Zweite Maßnahme", context: context)

        // 11.900 € (Badsanierung) + 5.950 € (Dachsanierung) = 17.850 € über beide Entscheidungen.
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("17.850,00"), "Die Herstellungskosten-Zeile muss die Summe über alle Aktivierungs-Entscheidungen zeigen, nicht nur die erste.")
    }

    func testInitialSetupReportShowsItemizedAncillaryCostsWithLandAndBuildingShare() throws {
        // Seite 1 der Erstanlage (Abschnitt B) muss jede erfasste Nebenkosten-Position einzeln mit
        // ihrem Grund- UND Gebäudeanteil zeigen, nicht nur die Bezeichnung.
        let (property, _, _) = try makePropertyWithThresholdCase()
        property.purchaseTransferTaxCosts = 10_500
        property.purchaseBrokerCosts = 3_500
        property.purchaseNotaryCosts = 2_200
        property.purchaseLandRegistryCosts = 300
        property.purchaseAncillaryCosts = 16_500

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        for expected in ["ANSCHAFFUNGSNEBENKOSTEN UND ZUORDNUNG", "Grunderwerbsteuer", "Maklerprovision", "Notarkosten", "Auflassungsvormerkung", "GRUND UND BODEN", "GEBÄUDE"] {
            XCTAssertTrue(text.contains(expected), "Erwarteter Inhalt „\(expected)“ fehlt in der Nebenkosten-Tabelle der Erstanlage.")
        }
    }

    func testInitialSetupShowsGebäudeAfaDerivationSections() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        for expected in ["KAUFPREIS UND AUFTEILUNG", "HERLEITUNG DER GEBÄUDE-AFA-BEMESSUNGSGRUNDLAGE", "GEBÄUDE-AFA: METHODE, NUTZUNGSDAUER UND JAHRESBETRAG", "Gebäudeanteil des Kaufpreises", "Gebäudeanteil der Anschaffungsnebenkosten"] {
            XCTAssertTrue(text.contains(expected), "Erwarteter Abschnitt „\(expected)“ fehlt auf Seite 1 der Erstanlage.")
        }
    }

    func testInitialSetupShowsRealOwnershipSharePercentWhenSet() throws {
        // Regressionstest: "Eigentumsanteil" war früher ein hartkodierter, nie befüllbarer
        // "nicht erfasst"-String ohne Bezug zu einem Property-Feld.
        let (property, _, _) = try makePropertyWithThresholdCase()
        property.ownershipSharePercent = 50
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("50,0 %"), "Ein gesetzter Eigentumsanteil muss im Bericht erscheinen, nicht pauschal „nicht erfasst“.")
    }

    func testInitialSetupDoesNotContainTheYearSeries() throws {
        // Auftrag Abschnitt 1/9: die Gebäude-AfA-Jahresreihe ist für die Erstanlage irrelevant und
        // darf dort nicht mehr erscheinen (anders als im eigenständigen AfA-Bericht).
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Jahresreihe"), "Die Erstanlage darf keine Gebäude-AfA-Jahresreihe mehr enthalten.")

        let (afaURL, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let afaText = try extractText(from: afaURL)
        XCTAssertTrue(afaText.contains("Jahresreihe"), "Der eigenständige AfA-Bericht soll die Jahresreihe weiterhin enthalten.")
    }

    func testImprovementAssetsAppearSeparatelyFromMovableAssets() throws {
        // Herstellungskosten am Gebäude (Kategorie `.improvement`, z.B. eine Fassadendämmung) dürfen
        // nicht in der Tabelle „Abschreibung beweglicher Wirtschaftsgüter" auftauchen – das wäre eine
        // fachlich falsche Einordnung – sondern in einem eigenen Gebäude-Kapitel.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let facade = DepreciableAsset(name: "Fassadendämmung", category: .improvement, cost: 18_000, usefulLifeYears: 50, placedInServiceDate: calendarDate(2023, 6, 1))
        facade.property = property
        context.insert(facade)
        let kitchen = DepreciableAsset(name: "Einbauküche", category: .furniture, cost: 6_500, usefulLifeYears: 10, placedInServiceDate: calendarDate(2023, 6, 1))
        kitchen.property = property
        context.insert(kitchen)

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Weitere Herstellungskosten am Gebäude"), "Herstellungskosten am Gebäude brauchen ein eigenes Kapitel.")
        XCTAssertTrue(text.contains("Abschreibung beweglicher Wirtschaftsgüter"), "Bewegliche Wirtschaftsgüter brauchen weiterhin ihr eigenes Kapitel.")
        XCTAssertTrue(text.contains("Einbauküche"), "Echte bewegliche Wirtschaftsgüter müssen weiterhin erscheinen.")

        // Die Fassadendämmung darf nur einmal vorkommen – im Gebäude-Kapitel, nicht zusätzlich in der
        // Tabelle der beweglichen Wirtschaftsgüter (keine Doppelzählung/Fehleinordnung).
        let occurrences = text.components(separatedBy: "Fassadendämmung").count - 1
        XCTAssertEqual(occurrences, 1, "Die Fassadendämmung darf nur in einem Kapitel erscheinen, nicht doppelt.")
    }

    func testStandaloneAfaReportSeparatesImprovementAssetsFromMovableAssets() throws {
        // Derselbe Fehler wie bei der Erstanlage (siehe testImprovementAssetsAppearSeparatelyFrom-
        // MovableAssets) bestand bislang auch im eigenständigen AfA-Bericht: eine Fassadendämmung
        // (Kategorie `.improvement`) landete in der Tabelle „Bewegliche Wirtschaftsgüter".
        let (property, _, _) = try makePropertyWithThresholdCase()
        let facade = DepreciableAsset(name: "Fassadendämmung", category: .improvement, cost: 18_000, usefulLifeYears: 50, placedInServiceDate: calendarDate(2023, 6, 1))
        facade.property = property
        context.insert(facade)
        let kitchen = DepreciableAsset(name: "Einbauküche", category: .furniture, cost: 6_500, usefulLifeYears: 10, placedInServiceDate: calendarDate(2023, 6, 1))
        kitchen.property = property
        context.insert(kitchen)

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("AfA-Herleitung – Herstellungskosten am Gebäude"), "Herstellungskosten am Gebäude brauchen im AfA-Bericht ein eigenes Kapitel.")
        XCTAssertTrue(text.contains("AfA-Herleitung – Bewegliche Wirtschaftsgüter"), "Bewegliche Wirtschaftsgüter brauchen weiterhin ihr eigenes Kapitel.")
        XCTAssertTrue(text.contains("Einbauküche"), "Echte bewegliche Wirtschaftsgüter müssen weiterhin erscheinen.")

        let occurrences = text.components(separatedBy: "Fassadendämmung").count - 1
        XCTAssertEqual(occurrences, 1, "Die Fassadendämmung darf nur in einem Kapitel erscheinen, nicht doppelt.")
    }

    func testOngoingReportSeparatesImprovementAssetAfaFromEinrichtung() throws {
        // Dieselbe Fehleinordnung konnte auch in der Anlage-V-Zusammenfassung des Jahresreports
        // auftreten: die AfA einer aktivierten Fassadendämmung wurde stillschweigend in die Zeile
        // „AfA bewegliche Wirtschaftsgüter (Einrichtung)" eingerechnet.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let facade = DepreciableAsset(name: "Fassadendämmung", category: .improvement, cost: 18_000, usefulLifeYears: 50, placedInServiceDate: calendarDate(2023, 6, 1))
        facade.property = property
        context.insert(facade)

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .ongoing(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("AfA Herstellungskosten am Gebäude"), "Die Anlage V muss aktivierte Gebäude-Herstellungskosten als eigene Zeile zeigen.")
    }

    func testMovableAssetWithBuildingLikeNameIsFlaggedForReview() throws {
        // Sicherheitsnetz: eine als beweglich kategorisierte Position, deren Bezeichnung auf eine
        // Gebäudemaßnahme hindeutet, wird nicht stillschweigend als normales bewegliches
        // Wirtschaftsgut behandelt, sondern als zu prüfen markiert – ohne die vorhandene
        // Kategorisierung selbst zu verändern.
        let (property, _, _) = try makePropertyWithThresholdCase()
        let mischaracterized = DepreciableAsset(name: "Fassadendämmung Garage", category: .other, cost: 4_000, usefulLifeYears: 10, placedInServiceDate: calendarDate(2023, 6, 1))
        mischaracterized.property = property
        context.insert(mischaracterized)

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .initialSetup)
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Abschreibung beweglicher Wirtschaftsgüter"), "Die Position bleibt in der Tabelle der beweglichen Wirtschaftsgüter, ihre Kategorie wird nicht eigenmächtig geändert.")
        XCTAssertTrue(text.contains("steuerliche Einordnung zu prüfen"), "Eine möglicherweise falsch kategorisierte Position muss als zu prüfen markiert werden.")
    }

    func testAfaHerleitungReferencesCapitalizedHerstellungskostenWhenPresent() throws {
        let (property, thresholdCase, expense) = try makePropertyWithThresholdCase()
        CapitalizationDecision.create(from: [expense], property: property, thresholdCase: thresholdCase, reason: "Testaktivierung", context: context)

        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023))
        let text = try extractText(from: url)
        XCTAssertTrue(text.contains("Herstellungskosten"), "Nach einer Aktivierungs-Entscheidung muss die Herleitung auf die aktivierten Herstellungskosten verweisen.")
    }

    // MARK: - CapitalizationDecision: Überleitungs-Kapitel nur mit tatsächlicher Entscheidung

    func testThresholdReportOmitsBridgeChapterWithoutCapitalizationDecision() throws {
        let (property, _, _) = try makePropertyWithThresholdCase()
        let (url, _) = TaxReportPDFBuilder.build(property: property, kind: .standaloneThreshold)
        let text = try extractText(from: url)
        XCTAssertFalse(text.contains("Überleitung zur AfA"), "Ohne Aktivierungs-Entscheidung darf kein Überleitungs-Kapitel erscheinen.")
    }

    func testThresholdReportIncludesBridgeChapterAfterCapitalizationDecision() throws {
        let (property, thresholdCase, expense) = try makePropertyWithThresholdCase()
        CapitalizationDecision.create(from: [expense], property: property, thresholdCase: thresholdCase, reason: "Testaktivierung", context: context)

        let thresholdURL = TaxReportPDFBuilder.build(property: property, kind: .standaloneThreshold).url
        let thresholdText = try extractText(from: thresholdURL)
        XCTAssertTrue(thresholdText.contains("15-%-Grenze – Überleitung zur AfA"), "Nach einer Aktivierungs-Entscheidung muss das Überleitungs-Kapitel im 15-%-Report erscheinen.")

        let afaURL = TaxReportPDFBuilder.build(property: property, kind: .standaloneAfa(taxYear: 2023)).url
        let afaText = try extractText(from: afaURL)
        XCTAssertTrue(afaText.contains("AfA-Herleitung – Maßnahmen und Änderungen"), "Nach einer Aktivierungs-Entscheidung muss das Kapitel „Maßnahmen und Änderungen“ im AfA-Bericht erscheinen.")
    }

}
