import SwiftUI
import SwiftData
import PDFKit

/// Welcher der beiden getrennten Steuerreports erzeugt werden soll (siehe Auftrag Abschnitt 3,
/// Modus A/B): die einmalige Erstanlage (Anschaffungskosten/Kaufpreisaufteilung/Gebäude-AfA,
/// bewegliche Wirtschaftsgüter, optional die 15-%-Grenze nach bewusster Nutzeraktion) oder der
/// laufende Betrieb eines bestimmten Steuerjahres (Anlage V – AfA dort nur als Endbetrag, die volle
/// Herleitung bleibt dem AfA-Bericht vorbehalten –, Erhaltungsaufwand/sonstige Werbungskosten,
/// Belegverzeichnis, ebenfalls optional die 15-%-Grenze). Beide Reports sind reine PDF-Unterlagen
/// fürs Finanzamt und enthalten bewusst keine Checkliste – die Vorbereitungs-Checkliste ist ein
/// reines Bildschirm-Werkzeug in TaxModulePropertyView.
enum TaxReportKind {
    case initialSetup
    case ongoing(taxYear: Int)
    /// Eigenständiger Prüfbericht nur zur 15-%-Grenze, siehe Design-Analyse Abschnitt 7.
    case standaloneThreshold
    /// Eigenständiger AfA-Bericht nur zur Gebäude-/Einrichtungs-AfA, siehe Design-Analyse Abschnitt 8.
    case standaloneAfa(taxYear: Int)

    var taxYear: Int? {
        switch self {
        case .ongoing(let year): return year
        case .standaloneAfa(let year): return year
        case .initialSetup, .standaloneThreshold: return nil
        }
    }

    var documentTitle: String {
        switch self {
        case .initialSetup: return "Steuerliche Erstanlage"
        case .ongoing(let year): return "Laufender Betrieb \(String(year))"
        case .standaloneThreshold: return "Prüfung der 15-%-Grenze"
        case .standaloneAfa(let year): return "AfA-Herleitung und -Berechnung \(String(year))"
        }
    }
}

/// Baut eines der beiden steuerlichen Reports (PDF) für eine Immobilie ausschließlich aus bereits
/// vorhandenen Daten: Deckblatt, Inhaltsverzeichnis mit korrekten Seitenzahlen und je nach
/// `TaxReportKind` eine Teilmenge der Kapitel. Fehlt die Datengrundlage für ein Kapitel, entfällt
/// es ersatzlos – an seiner Stelle erscheint ein Hinweis in `warnings`, es werden keine Werte
/// erfunden. Arbeits- und Nachweisunterlage, keine amtliche Steuererklärung.
@MainActor
enum TaxReportPDFBuilder {
    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi
    private static let maxRowsPerPage = 20

    private struct Chapter {
        let title: String
        let introLines: [String]
        let summaryLines: [String]
        let columnHeaders: [String]
        let rows: [[String]]
        /// Maximale Zeilenzahl, bevor das Kapitel auf eine Folgeseite umbricht – normalerweise der
        /// globale Standard, aber für Kapitel mit durchweg kurzen, nicht umbrechenden
        /// Positionsbezeichnungen (z.B. die AfA-Herleitung) gezielt erhöhbar, damit sie trotz
        /// zusätzlicher Einzelpositionen auf einer Seite bleiben, statt mechanisch nach einer für
        /// alle Kapitel gleichen Zeilenzahl umzubrechen.
        var rowsPerPage: Int = maxRowsPerPage
        /// Feste Fakten-Zeilen vor den eigentlichen Tabellen (z.B. Objekt-/Anschaffungsdaten der neu
        /// strukturierten Erstanlage-Seite 1) – jede als eigenes Label/Wert-Paar statt generischer
        /// Position/Wert-Tabellenzeilen.
        var headerFacts: [(label: String, value: String)] = []
        /// Mehrere eigenständige, unterschiedlich spaltige Tabellen auf einer Seite (Abschnitte A–D
        /// der neu strukturierten Erstanlage-Seite 1) – wenn gesetzt, werden `columnHeaders`/`rows`
        /// ignoriert und stattdessen diese Tabellen der Reihe nach gerendert, jede mit eigenem Titel
        /// und eigener Spaltenstruktur (z.B. die Anschaffungsnebenkosten-Tabelle mit Kostenposition/
        /// Gesamtbetrag/Anteil Grund/Anteil Gebäude/Status neben einer einfachen Position/Wert-
        /// Tabelle). Bricht an Tabellengrenzen auf eine Folgeseite um, nie mitten in einer Tabelle,
        /// sobald das Zeilenbudget `rowsPerPage` überschritten würde – siehe `blockPages`.
        var additionalTables: [(title: String, columnHeaders: [String], rows: [[String]])] = []

        private var usesBlockLayout: Bool { !additionalTables.isEmpty || !headerFacts.isEmpty }

        /// Gruppiert `additionalTables`-Indizes in Seiten anhand eines groben Zeilenbudgets (jede
        /// Tabelle zählt mit Zeilenzahl + 2 für Titel/Spaltenkopf), damit eine ungewöhnlich große
        /// Datenmenge kontrolliert auf eine Folgeseite umbricht, statt die Seite zu überfüllen oder
        /// eine Tabelle mittendrin abzuschneiden.
        private var blockPages: [[Int]] {
            var pages: [[Int]] = [[]]
            var budget = headerFacts.count + 2
            for (index, table) in additionalTables.enumerated() {
                let weight = table.rows.count + 2
                if budget + weight > rowsPerPage, !(pages.last?.isEmpty ?? true) {
                    pages.append([])
                    budget = 0
                }
                pages[pages.count - 1].append(index)
                budget += weight
            }
            return pages
        }

        var pageCount: Int {
            guard !usesBlockLayout else { return blockPages.count }
            return max(1, Int(ceil(Double(rows.count) / Double(rowsPerPage))))
        }

        func rowsForPage(_ pageIndex: Int) -> [[String]] {
            guard !usesBlockLayout else { return [] }
            let start = pageIndex * rowsPerPage
            guard start < rows.count else { return [] }
            return Array(rows[start..<min(start + rowsPerPage, rows.count)])
        }

        func headerFactsForPage(_ pageIndex: Int) -> [(label: String, value: String)] {
            pageIndex == 0 ? headerFacts : []
        }

        func tablesForPage(_ pageIndex: Int) -> [(title: String, columnHeaders: [String], rows: [[String]])] {
            let pages = blockPages
            guard pageIndex < pages.count else { return [] }
            return pages[pageIndex].map { additionalTables[$0] }
        }
    }

    /// Markiert eine Tabellenzelle mit einer Statusfarbe (siehe `TaxPDFChapterPage`-Rendering) –
    /// „§good§…“/„§warn§…“/„§bad§…“, Präfix wird beim Rendern entfernt.
    private static func tonedCell(_ text: String, _ tone: Theme.StatusTone) -> String {
        switch tone {
        case .good: return "§good§" + text
        case .warning: return "§warn§" + text
        case .critical: return "§bad§" + text
        case .neutral: return text
        }
    }

    private static func toneForThresholdStatus(_ status: ThresholdExpenseStatus) -> Theme.StatusTone {
        switch status {
        case .certain, .includedAfterReview: return .good
        case .excluded: return .neutral
        case .unclassified: return .warning
        }
    }

    /// Die 15-%-Grenze erscheint bewusst in keinem der beiden Steuerreports (`.initialSetup`/
    /// `.ongoing`) mehr, sondern ausschließlich im eigenständigen `.standaloneThreshold`-Bericht
    /// (siehe `buildStandaloneThresholdReport`): die Dreijahresüberwachung muss unabhängig vom
    /// jährlichen Anlage-V-Bericht erneut ans Finanzamt nachgereicht werden können, ohne dafür
    /// jedes Mal den kompletten Jahresbericht neu zu erzeugen.
    static func build(property: Property, kind: TaxReportKind) -> (url: URL?, warnings: [String]) {
        let generatedAt = Date.now
        var warnings: [String] = []
        var chapters: [Chapter] = []

        func add(_ chapter: Chapter?, otherwiseWarn title: String) {
            if let chapter {
                chapters.append(chapter)
            } else {
                warnings.append("Kapitel „\(title)“ entfällt: keine ausreichende Datengrundlage.")
            }
        }

        func addAll(_ newChapters: [Chapter], otherwiseWarn title: String) {
            if newChapters.isEmpty {
                warnings.append("Kapitel „\(title)“ entfällt: keine ausreichende Datengrundlage.")
            } else {
                chapters.append(contentsOf: newChapters)
            }
        }

        if property.isLandValueMissing {
            warnings.append("Bodenwert nicht erfasst – rechnerisch gilt der gesamte Kaufpreis als Gebäude, die Gebäude-AfA ist dadurch voraussichtlich zu hoch. Bodenwert lt. Kaufvertrag oder Bodenrichtwert ergänzen.")
        }
        if let taxYear = kind.taxYear {
            let withoutAfa = property.allExpenses(forYear: taxYear).filter { $0.taxTreatment == .capitalized && $0.capitalizationDecision == nil }
            if !withoutAfa.isEmpty {
                warnings.append("\(withoutAfa.count) als Herstellungskosten erfasste Ausgabe(n) \(String(taxYear)) (\(withoutAfa.reduce(0.0) { $0 + $1.amount }.asCurrency)) ohne zugehöriges Wirtschaftsgut – dafür wird noch keine AfA berechnet. In der 15-%-Prüfung oder unter Herstellungskosten als Wirtschaftsgut aktivieren.")
            }
        }
        if let appraisal = property.latestRemainingUsefulLifeAppraisal, property.applicableRemainingUsefulLifeAppraisal == nil, property.afaRatePercentOverride == nil {
            warnings.append("Restnutzungsdauergutachten vom \(appraisal.valuationDate.asShortDate) ergibt \(appraisal.suggestedAfaRatePercent.asPercent) und damit nicht mehr als den typisierten Satz (\(property.defaultAfaRatePercent.asPercent)) – § 7 Abs. 4 Satz 2 EStG erlaubt nur eine kürzere Nutzungsdauer, angewandt wird daher der typisierte Satz.")
        }

        switch kind {
        case .initialSetup:
            let asOfYear = Calendar.current.component(.year, from: generatedAt)
            add(buildInitialSetupAcquisitionChapter(property: property, taxYear: asOfYear), otherwiseWarn: "Anschaffungskosten, Kaufpreisaufteilung und Gebäude-AfA")
            // Nur angehängt, wenn tatsächlich Herstellungskosten am Gebäude vorliegen – kein
            // „entfällt mangels Datengrundlage"-Hinweis, da das der ganz normale, häufige Fall ist.
            if let improvementChapter = buildImprovementAssetsChapter(property: property, taxYear: asOfYear) {
                chapters.append(improvementChapter)
            }
            add(buildMovableAssetsChapter(property: property, taxYear: asOfYear), otherwiseWarn: "Abschreibung beweglicher Wirtschaftsgüter")
        case .ongoing(let taxYear):
            add(buildAnlageVChapter(property: property, taxYear: taxYear), otherwiseWarn: "Anlage V – Einnahmen und Werbungskosten")
            add(buildMaintenanceChapter(property: property, taxYear: taxYear), otherwiseWarn: "Erhaltungsaufwand und Herstellungskosten – Einzelnachweis")
            add(buildOtherExpensesChapter(property: property, taxYear: taxYear), otherwiseWarn: "Sonstige Werbungskosten – Einzelnachweis")
            add(buildDocumentsChapter(property: property, taxYear: taxYear), otherwiseWarn: "Belegverzeichnis \(String(taxYear))")
        case .standaloneThreshold:
            addAll(buildThresholdChapters(property: property), otherwiseWarn: "15-%-Grenze")
        case .standaloneAfa(let taxYear):
            addAll(buildAfaChapters(property: property, taxYear: taxYear), otherwiseWarn: "AfA-Herleitung")
        }

        guard !chapters.isEmpty else {
            warnings.append("Es konnte kein Kapitel erzeugt werden – keine ausreichenden Daten für diese Immobilie.")
            return (nil, warnings)
        }

        // Abschließendes Kapitel aus den bislang nur an den Aufrufer zurückgegebenen `warnings` –
        // offene Punkte/fehlende Datengrundlagen gehören selbst in die Unterlage (Auftrag Abschnitt
        // 3G/4F „Offene Punkte“/„Beleg- und Prüfhinweise“), nicht nur in einen Bildschirm-Hinweis.
        if !warnings.isEmpty {
            let title = { () -> String in
                switch kind {
                case .initialSetup: return "Offene Punkte und Dokumentationshinweise"
                default: return "Beleg- und Prüfhinweise"
                }
            }()
            chapters.append(Chapter(
                title: title,
                introLines: ["Für folgende Abschnitte lag keine ausreichende Datengrundlage vor; sie wurden ohne erfundene Werte ausgelassen und sollten ggf. in der App ergänzt werden."],
                summaryLines: [],
                columnHeaders: ["Hinweis"],
                rows: warnings.map { [$0] }
            ))
        }

        // Seitenzählung: Deckblatt = Seite 1, Inhaltsverzeichnis = Seite 2, danach die Kapitel.
        var tocEntries: [(title: String, page: Int)] = []
        var page = 3
        for chapter in chapters {
            tocEntries.append((chapter.title, page))
            page += chapter.pageCount
        }
        let totalPages = page - 1
        let label = propertyLabel(property)

        var pageDatas: [Data] = []

        if let data = PDFExporter.renderPDF(size: pageSize, content: {
            TaxPDFCoverPage(property: property, kind: kind, generatedAt: generatedAt, pageNumber: 1, totalPages: totalPages)
        }) {
            pageDatas.append(data)
        }

        if let data = PDFExporter.renderPDF(size: pageSize, content: {
            TaxPDFTOCPage(propertyLabel: label, kind: kind, entries: tocEntries, pageNumber: 2, totalPages: totalPages)
        }) {
            pageDatas.append(data)
        }

        var currentPage = 3
        for chapter in chapters {
            for pageIndex in 0..<chapter.pageCount {
                let rowsForPage = chapter.rowsForPage(pageIndex)
                if let data = PDFExporter.renderPDF(size: pageSize, content: {
                    TaxPDFChapterPage(
                        propertyLabel: label,
                        kind: kind,
                        title: chapter.title,
                        introLines: pageIndex == 0 ? chapter.introLines : [],
                        summaryLines: pageIndex == 0 ? chapter.summaryLines : [],
                        columnHeaders: chapter.columnHeaders,
                        rows: rowsForPage,
                        headerFacts: chapter.headerFactsForPage(pageIndex),
                        additionalTables: chapter.tablesForPage(pageIndex),
                        pageNumber: currentPage,
                        totalPages: totalPages
                    )
                }) {
                    pageDatas.append(data)
                }
                currentPage += 1
            }
        }

        guard let merged = mergePages(pageDatas) else { return (nil, warnings) }
        let safeName = (property.name.isEmpty ? property.address : property.name).replacingOccurrences(of: "/", with: "-")
        let url = try? ExportFileStore.write(merged, fileName: "Steuerunterlagen \(safeName) – \(kind.documentTitle).pdf")
        return (url, warnings)
    }

    /// Eigenständiger, fokussierter Bericht nur zur 15-%-Grenze (Ergebnisübersicht, Kostenüber-
    /// sicht, offene Sachverhalte, Berechnungsherleitung) – siehe Design-Analyse Abschnitt 7.
    static func buildStandaloneThresholdReport(property: Property) -> (url: URL?, warnings: [String]) {
        build(property: property, kind: .standaloneThreshold)
    }

    /// Eigenständiger, konsolidierter AfA-Bericht (Gebäude + bewegliche Wirtschaftsgüter in einem
    /// Dokument) – siehe Design-Analyse Abschnitt 8.
    static func buildStandaloneAfaReport(property: Property, taxYear: Int) -> (url: URL?, warnings: [String]) {
        build(property: property, kind: .standaloneAfa(taxYear: taxYear))
    }

    private static func mergePages(_ datas: [Data]) -> Data? {
        guard let first = datas.first, let combined = PDFDocument(data: first) else { return nil }
        for data in datas.dropFirst() {
            guard let doc = PDFDocument(data: data) else { continue }
            for index in 0..<doc.pageCount {
                if let page = doc.page(at: index) {
                    combined.insert(page, at: combined.pageCount)
                }
            }
        }
        return combined.dataRepresentation()
    }

    private static func propertyLabel(_ property: Property) -> String {
        let name = property.name.isEmpty ? property.address : property.name
        return "\(name) · \(property.address)"
    }

    /// Bezeichnung des zuerst verknüpften Belegs, gekürzt für die Tabellenspalte – „–“, wenn kein
    /// Beleg zugeordnet ist.
    private static func belegLabel(_ documents: [Document]?) -> String {
        guard let title = documents?.first?.title, !title.isEmpty else { return "–" }
        return truncated(title)
    }

    private static func truncated(_ text: String, maxLength: Int = 26) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    // MARK: - Erstanlage, Seite 1: Anschaffungskosten, Kaufpreisaufteilung und Gebäude-AfA

    /// Baut die komplette Seite 1 der Steuerlichen Erstanlage als eine Seite mit vier eigenständigen
    /// Tabellen (A–D): Kaufpreisaufteilung, Anschaffungsnebenkosten mit Grund-/Gebäudeanteil je
    /// Einzelposition, Herleitung der Gebäude-AfA-Bemessungsgrundlage und AfA-Methode/-Satz/-Betrag.
    /// Bewusst ein eigener, nicht mit `.standaloneAfa`/`.ongoing` geteilter Code-Pfad (siehe Antwort
    /// an den Nutzer): diese Struktur (Einzelaufschlüsselung mit Grund-/Gebäude-Spalten, keine
    /// Jahresreihe) gilt ausdrücklich nur für die Erstanlage.
    private static func buildInitialSetupAcquisitionChapter(property: Property, taxYear: Int) -> Chapter? {
        guard property.purchasePrice > 0 || property.purchaseDate != nil else { return nil }
        guard property.buildingValue > 0 else { return nil }

        let headerFacts: [(label: String, value: String)] = [
            ("Objekt", property.name.isEmpty ? property.address : property.name),
            ("Anschrift", property.address),
            ("Eigentumsanteil", property.ownershipSharePercent.map { $0.asPercent } ?? "100 % (Alleineigentum, keine Angabe hinterlegt)"),
            ("Baujahr", property.constructionYear.map { String($0) } ?? "nicht erfasst"),
            ("Notarielles Kaufvertragsdatum", property.purchaseDate?.asShortDate ?? "nicht erfasst – Prüfung erforderlich"),
            ("Wirtschaftlicher Übergang (Besitz/Nutzen/Lasten)", property.economicTransferDate?.asShortDate ?? "nicht erfasst – Prüfung erforderlich")
        ]

        // A. Kaufpreis und Aufteilung – aus dem im Kaufvertrag bezifferten Bodenwert berechnet, kein
        // pauschaler Prozentsatz. Ohne erfassten Bodenwert ist die Aufteilung nicht belastbar, nicht
        // „0 % Grund" – das wird als vorläufig gekennzeichnet statt stillschweigend unterschlagen.
        let landDataMissing = property.landValue <= 0
        let landShareOfPrice = property.purchasePrice * property.landValuePercentage
        let buildingShareOfPrice = property.purchasePrice - landShareOfPrice
        var tableA: [[String]] = []
        tableA.append(["Kaufpreis laut Kaufvertrag", property.purchasePrice.asCurrency])
        tableA.append(["davon Anteil Grund und Boden", "\(landShareOfPrice.asCurrency) (\((property.landValuePercentage * 100).asPercent))"])
        tableA.append(["davon Anteil Gebäude", "\(buildingShareOfPrice.asCurrency) (\(((1 - property.landValuePercentage) * 100).asPercent))"])
        tableA.append([
            "Angewendete Aufteilung",
            landDataMissing
                ? tonedCell("Bodenwert nicht erfasst – Aufteilung vorläufig, Prüfung erforderlich", .warning)
                : "aus Kaufvertrag (Bodenwert \(property.landValue.asCurrency) von \(property.purchasePrice.asCurrency))"
        ])
        tableA.append(["**Summenprüfung (Grund + Gebäude = Kaufpreis)", (landShareOfPrice + buildingShareOfPrice).asCurrency])

        // B. Anschaffungsnebenkosten und Zuordnung – jede erfasste Einzelposition mit ihrem Grund-/
        // Gebäudeanteil nach derselben Aufteilung wie der Kaufpreis selbst; ein nicht einzeln
        // aufgeschlüsselter Rest verschwindet nicht, sondern erscheint als eigene, als zu prüfen
        // markierte Zeile.
        let items: [(label: String, amount: Double)] = [
            ("Grunderwerbsteuer", property.purchaseTransferTaxCosts),
            ("Maklerprovision", property.purchaseBrokerCosts),
            ("Notarkosten", property.purchaseNotaryCosts),
            ("Auflassungsvormerkung (Grundbuch)", property.purchaseLandRegistryCosts)
        ].filter { $0.amount > 0 }
        let residual = property.purchaseOtherAncillaryCosts
        var tableB: [[String]] = []
        for item in items {
            let land = item.amount * property.landValuePercentage
            let building = item.amount - land
            tableB.append([item.label, item.amount.asCurrency, land.asCurrency, building.asCurrency, "erfasst"])
        }
        if residual > 0.01 {
            let land = residual * property.landValuePercentage
            let building = residual - land
            let label = items.isEmpty ? "Nebenkosten (nicht aufgeschlüsselt)" : "Weitere Nebenkosten (nicht aufgeschlüsselt)"
            tableB.append([label, residual.asCurrency, land.asCurrency, building.asCurrency, tonedCell("zu prüfen – Aufschlüsselung ergänzen", .warning)])
        }
        if items.isEmpty && residual <= 0.01 {
            tableB.append(["Keine Anschaffungsnebenkosten erfasst", 0.0.asCurrency, "–", "–", tonedCell("zu prüfen", .warning)])
        }
        let totalAncillaryLand = property.purchaseAncillaryCosts * property.landValuePercentage
        let totalAncillaryBuilding = property.purchaseAncillaryCosts - totalAncillaryLand
        tableB.append(["**Summe Nebenkosten", property.purchaseAncillaryCosts.asCurrency, totalAncillaryLand.asCurrency, totalAncillaryBuilding.asCurrency, ""])

        // C. Herleitung der Gebäude-AfA-Bemessungsgrundlage – als sichtbare Summenbildung aus genau
        // den beiden zuvor hergeleiteten Gebäudeanteilen, nicht nur als Endwert. Die beiden Summanden
        // addieren sich rechnerisch exakt zu `buildingValue` (siehe `Property.buildingValue`), es
        // wird also nichts doppelt gezählt oder neu berechnet.
        var tableC: [[String]] = []
        tableC.append(["Gebäudeanteil des Kaufpreises", buildingShareOfPrice.asCurrency])
        tableC.append(["+ Gebäudeanteil der Anschaffungsnebenkosten", totalAncillaryBuilding.asCurrency])
        tableC.append(["**= Gebäude-AfA-Bemessungsgrundlage", property.buildingValue.asCurrency])
        if landDataMissing {
            tableC.append(["Hinweis", tonedCell("Bodenwert nicht erfasst – Bemessungsgrundlage vorläufig, nicht abschließend prüfbar", .warning)])
        }

        // D. AfA-Methode, Nutzungsdauer und Jahresbetrag – ohne Jahresreihe, siehe Auftrag.
        var tableD: [[String]] = []
        tableD.append(["AfA-Methode", "Linear"])
        tableD.append(["AfA-Satz", property.afaRatePercent.asPercent])
        let usefulLifeText: String
        switch property.afaRateSource {
        case .appraisal:
            if let appraisal = property.latestRemainingUsefulLifeAppraisal {
                usefulLifeText = "\(Int(appraisal.remainingUsefulLifeYears.rounded())) Jahre lt. Restnutzungsdauergutachten vom \(appraisal.valuationDate.asShortDate)"
            } else {
                usefulLifeText = "nicht ermittelbar"
            }
        case .typisiert:
            usefulLifeText = property.afaRatePercent > 0 ? "\(Int((100 / property.afaRatePercent).rounded())) Jahre (aus typisiertem Satz nach Baujahr)" : "nicht ermittelbar"
        case .manual:
            usefulLifeText = property.afaRatePercent > 0 ? "\(Int((100 / property.afaRatePercent).rounded())) Jahre (aus manuell festgelegtem Satz)" : "manuell festgelegt, keine Nutzungsdauer hinterlegt"
        }
        tableD.append(["Maßgebliche Nutzungsdauer", usefulLifeText])
        // Maßgeblich ist der wirtschaftliche Übergang (Besitz/Nutzen/Lasten), ersatzweise das
        // Kaufdatum (siehe `Property.afaStartDate`) – identisch mit dem tatsächlich für
        // `buildingAfA(forYear:)` verwendeten Datum, damit Anzeige und Berechnung nie auseinanderlaufen.
        let afaBeginLabel = property.economicTransferDate != nil ? "AfA-Beginn (Übergang Nutzen/Lasten)" : "AfA-Beginn (Kaufdatum, Übergang nicht erfasst)"
        tableD.append([afaBeginLabel, property.afaStartDate?.asShortDate ?? "nicht erfasst – Prüfung erforderlich"])
        if let afaStartDate = property.afaStartDate {
            let calendar = Calendar.current
            let startYear = calendar.component(.year, from: afaStartDate)
            if taxYear == startYear {
                let monthsUsed = 13 - calendar.component(.month, from: afaStartDate)
                tableD.append(["Zeitanteilige Berechnung \(String(taxYear))", "Anschaffungsjahr: \(monthsUsed) von 12 Monaten berücksichtigt"])
            }
        } else {
            tableD.append(["Zeitanteilige Berechnung", tonedCell("AfA-Beginn nicht erfasst – Jahresbetrag ggf. nicht zeitanteilig, Prüfung erforderlich", .warning)])
        }
        tableD.append(["**Jährliche Gebäude-AfA \(String(taxYear))", property.buildingAfA(forYear: taxYear).asCurrency])

        let ancillaryColumns = ["Kostenposition", "Betrag", "Grund und Boden", "Gebäude", "Status"]

        return Chapter(
            title: "Anschaffungskosten, Kaufpreisaufteilung und Gebäude-AfA",
            introLines: [],
            summaryLines: [],
            columnHeaders: [],
            rows: [],
            // Großzügiges Zeilenbudget: alle vier Tabellen sind kurz, sollen aber laut ausdrücklichem
            // Wunsch nicht durch einen willkürlichen Seitenumbruch getrennt werden, solange sie bei
            // gut lesbarer Schrift tatsächlich auf eine Seite passen (siehe `Chapter.blockPages`).
            rowsPerPage: 60,
            headerFacts: headerFacts,
            additionalTables: [
                ("A. KAUFPREIS UND AUFTEILUNG", ["Position", "Wert"], tableA),
                ("B. ANSCHAFFUNGSNEBENKOSTEN UND ZUORDNUNG", ancillaryColumns, tableB),
                ("C. HERLEITUNG DER GEBÄUDE-AFA-BEMESSUNGSGRUNDLAGE", ["Position", "Wert"], tableC),
                ("D. GEBÄUDE-AFA: METHODE, NUTZUNGSDAUER UND JAHRESBETRAG", ["Position", "Wert"], tableD)
            ]
        )
    }

    // MARK: - Erstanlage, weitere Seiten: bewegliche Wirtschaftsgüter / weitere Herstellungskosten

    /// Nur tatsächlich bewegliche bzw. selbstständig nutzbare Wirtschaftsgüter (Kategorien
    /// `.furniture`/`.other`) – Herstellungskosten am Gebäude (`.improvement`) gehören fachlich nicht
    /// hierher (siehe `buildImprovementAssetsChapter`) und würden hier eine falsche Einordnung
    /// suggerieren. Zusätzlich ein Sicherheitshinweis, falls eine als beweglich erfasste Position
    /// nach ihrer Bezeichnung tatsächlich eine Gebäudemaßnahme sein könnte (z.B. „Fassadendämmung"),
    /// ohne die vorhandene Kategorisierung eigenmächtig zu überschreiben.
    private static func buildMovableAssetsChapter(property: Property, taxYear: Int) -> Chapter? {
        let movable = (property.depreciableAssets ?? []).filter { $0.category != .improvement }
        guard !movable.isEmpty else { return nil }
        let rows = movable.sorted { $0.placedInServiceDate < $1.placedInServiceDate }.map { asset -> [String] in
            let method = asset.isImmediatelyDeductible ? "Sofortabzug (GWG)" : "linear, \(asset.usefulLifeYears) Jahre"
            let nameLower = asset.name.lowercased()
            let looksLikeBuildingMeasure = nameLower.contains("fassade") || nameLower.contains("dämmung")
            let hinweis = looksLikeBuildingMeasure
                ? tonedCell("steuerliche Einordnung zu prüfen (möglicher Gebäudebezug)", .warning)
                : "–"
            return [
                asset.name,
                asset.placedInServiceDate.asShortDate,
                asset.depreciationBasis.asCurrency,
                method,
                asset.depreciation(forYear: taxYear).asCurrency,
                belegLabel(asset.documents),
                hinweis
            ]
        }
        return Chapter(
            title: "Abschreibung beweglicher Wirtschaftsgüter",
            introLines: ["Enthält ausschließlich tatsächlich bewegliche bzw. selbstständig nutzbare Wirtschaftsgüter. Herstellungskosten am Gebäude (Modernisierung/Umbau) sind hier nicht enthalten, siehe vorherige Seite."],
            summaryLines: [],
            columnHeaders: ["Bezeichnung", "Anschaffung", "Bemessungsgrundlage", "Methode/Nutzungsdauer", "AfA \(String(taxYear))", "Beleg", "Hinweis"],
            rows: rows
        )
    }

    /// Wirtschaftsgüter der Kategorie `.improvement` (Herstellungskosten am Gebäude) – unabhängig
    /// davon, ob sie aus einer `CapitalizationDecision` (15-%-Grenze) stammen oder direkt als
    /// Modernisierung/Umbau erfasst wurden. Beide Fälle gehören fachlich zum Gebäude, nicht zu den
    /// beweglichen Wirtschaftsgütern, und werden deshalb hier gemeinsam und vollständig ausgewiesen,
    /// statt dass nicht-Entscheidungs-Fälle (z.B. eine manuell erfasste „Fassadendämmung") in keinem
    /// Kapitel mehr auftauchen.
    private static func buildImprovementAssetsChapter(property: Property, taxYear: Int) -> Chapter? {
        let improvementAssets = (property.depreciableAssets ?? []).filter { $0.category == .improvement }
        guard !improvementAssets.isEmpty else { return nil }
        let decisionsByAssetID = Dictionary(uniqueKeysWithValues: (property.capitalizationDecisions ?? []).compactMap { decision -> (PersistentIdentifier, CapitalizationDecision)? in
            guard let asset = decision.resultingAsset else { return nil }
            return (asset.persistentModelID, decision)
        })
        let rows = improvementAssets.sorted { $0.placedInServiceDate < $1.placedInServiceDate }.map { asset -> [String] in
            let decision = decisionsByAssetID[asset.persistentModelID]
            let anlass = decision != nil ? (decision!.thresholdCase != nil ? "15-%-Grenze" : "manuell aktiviert") : "direkt erfasst"
            let hinweis = (decision?.reason.isEmpty == false) ? decision!.reason : (asset.notes.isEmpty ? "–" : asset.notes)
            return [
                asset.name,
                asset.placedInServiceDate.asShortDate,
                asset.cost.asCurrency,
                asset.depreciation(forYear: taxYear).asCurrency,
                anlass,
                hinweis
            ]
        }
        return Chapter(
            title: "Weitere Herstellungskosten am Gebäude",
            introLines: ["Diese Maßnahmen werden als eigenes Wirtschaftsgut mit dem Gebäude-AfA-Satz abgeschrieben und erhöhen die Bemessungsgrundlage ab dem genannten Jahr – bewusst getrennt von den beweglichen Wirtschaftsgütern, um keine Doppelzählung oder Fehleinordnung entstehen zu lassen."],
            summaryLines: [],
            columnHeaders: ["Maßnahme", "Wirksam ab", "Kosten", "AfA \(String(taxYear))", "Anlass", "Begründung/Hinweis"],
            rows: rows
        )
    }

    // MARK: - Kapitel: AfA-Herleitung (drei Teilkapitel: Herleitung Gebäude, Jahresreihe, bewegliche Wirtschaftsgüter)

    private static func buildAfaChapters(property: Property, taxYear: Int) -> [Chapter] {
        guard property.buildingValue > 0 else { return [] }
        var chapters: [Chapter] = []

        // 1 · Herleitung Gebäude-AfA als eine durchgehende Tabelle (Kaufdaten → Nebenkosten →
        // Grund/Gebäude-Aufteilung → AfA-Satz-Quelle → Endergebnis → Kumuliert), angelehnt an die
        // vom Nutzer beigelegte Excel-Referenz „AfA-Herleitung Gebäude – OnePager": dieselben,
        // bereits an anderer Stelle getesteten Werte, nur tabellarisch statt als Fließtext. Die
        // Anschaffungsnebenkosten werden – wenn gepflegt – einzeln ausgewiesen (Makler/Notar/
        // Auflassungsvormerkung, siehe `Property.purchaseBrokerCosts` u.a.); die Summe
        // `purchaseAncillaryCosts` bleibt dabei unverändert die für Aufteilung und AfA maßgebliche
        // Zahl, die Einzelposten sind rein zusätzliche Transparenz und müssen sich nicht vollständig
        // zu ihr aufsummieren (Restbetrag erscheint als „Sonstige Nebenkosten").
        let capitalizedDecisions = property.capitalizationDecisions ?? []
        let capitalizedTotal = capitalizedDecisions.reduce(0.0) { $0 + $1.totalAmount }

        var afaRows: [[String]] = []
        afaRows.append(["##KAUFDATEN", ""])
        afaRows.append(["Kaufdatum (Beurkundung)", property.purchaseDate?.asShortDate ?? "nicht erfasst"])
        if let economicTransferDate = property.economicTransferDate {
            afaRows.append(["Übergang Nutzen und Lasten (maßgeblich für AfA-Beginn)", economicTransferDate.asShortDate])
        }
        afaRows.append(["Kaufpreis gesamt", property.purchasePrice.asCurrency])
        afaRows.append(["Grund-und-Boden-Anteil (lt. Kaufvertrag)", property.isLandValueMissing ? tonedCell("Bodenwert nicht erfasst – 0 %, Prüfung erforderlich", .warning) : (property.landValuePercentage * 100).asPercent])

        afaRows.append(["##ANSCHAFFUNGSNEBENKOSTEN", ""])
        if property.hasItemizedAncillaryCosts {
            if property.purchaseTransferTaxCosts > 0 {
                afaRows.append(["Grunderwerbsteuer", property.purchaseTransferTaxCosts.asCurrency])
            }
            if property.purchaseBrokerCosts > 0 {
                afaRows.append(["Maklerkosten", property.purchaseBrokerCosts.asCurrency])
            }
            if property.purchaseNotaryCosts > 0 {
                afaRows.append(["Notarkosten", property.purchaseNotaryCosts.asCurrency])
            }
            if property.purchaseLandRegistryCosts > 0 {
                afaRows.append(["Auflassungsvormerkung (Grundbuch)", property.purchaseLandRegistryCosts.asCurrency])
            }
            if property.purchaseOtherAncillaryCosts > 0.01 {
                afaRows.append(["Sonstige Nebenkosten", property.purchaseOtherAncillaryCosts.asCurrency])
            }
        } else {
            afaRows.append(["Anschaffungsnebenkosten (Summe)", property.purchaseAncillaryCosts.asCurrency])
        }
        afaRows.append(["**Anschaffungskosten gesamt (Kaufpreis + Nebenkosten)", "**" + property.totalAcquisitionCost.asCurrency])

        afaRows.append(["##AUFTEILUNG GRUND UND BODEN / GEBÄUDE", ""])
        afaRows.append(["Grund und Boden, anteilig inkl. Nebenkosten", property.apportionedLandValue.asCurrency])
        afaRows.append(["**Gebäudeanteil / AfA-Bemessungsgrundlage", "**" + property.buildingValue.asCurrency])
        if capitalizedTotal > 0 {
            // Stichwort bewusst vorangestellt, nicht „Ggf. zzgl. …“: lange Positionsbezeichnungen
            // werden in der Tabelle mehrzeilig umgebrochen, aber das Stichwort soll trotzdem sofort
            // ins Auge fallen.
            afaRows.append(["Herstellungskosten (ggf. aktiviert, siehe unten)", capitalizedTotal.asCurrency])
        }

        afaRows.append(["##RESTNUTZUNGSDAUER-GUTACHTEN", ""])
        if let appraisal = property.latestRemainingUsefulLifeAppraisal {
            afaRows.append(["Gutachten vorhanden", "Ja, vom \(appraisal.valuationDate.asShortDate)"])
            afaRows.append(["Restnutzungsdauer lt. Gutachten", "\(Int(appraisal.remainingUsefulLifeYears.rounded())) Jahre → \(appraisal.suggestedAfaRatePercent.asPercent)"])
            if property.applicableRemainingUsefulLifeAppraisal == nil {
                afaRows.append(["Anwendbarkeit", tonedCell("nicht anwendbar – Satz nicht höher als typisiert (§ 7 Abs. 4 Satz 2 EStG)", .warning)])
            }
        } else {
            afaRows.append(["Gutachten vorhanden", "Nein – es gilt der typisierte Satz"])
        }
        let rateHerleitung: String
        switch property.afaRateSource {
        case .typisiert: rateHerleitung = "Typisiert nach Baujahr (\(property.afaRateSource.legalBasis))"
        case .appraisal: rateHerleitung = "Restnutzungsdauergutachten (\(property.afaRateSource.legalBasis))"
        case .manual: rateHerleitung = "Manuell festgelegt (\(property.afaRateSource.legalBasis))" + (property.latestRemainingUsefulLifeAppraisal != nil ? " – Hinweis: ein Gutachten liegt vor, wird aber nicht angewandt" : "")
        }
        afaRows.append(["Angewandte Herleitung", rateHerleitung])

        afaRows.append(["##AFA-BERECHNUNG – ENDERGEBNIS", ""])
        afaRows.append(["AfA-Satz maßgeblich", property.afaRatePercent.asPercent])
        afaRows.append(["**Jährliche Gebäude-AfA \(String(taxYear))", "**" + property.buildingAfA(forYear: taxYear).asCurrency])

        afaRows.append(["##KUMULIERT", ""])
        afaRows.append(["Kumulierte Gebäude-AfA seit Anschaffung", property.cumulativeBuildingAfA(uptoYear: taxYear).asCurrency])
        afaRows.append(["Restbuchwert Gebäude (Stand \(String(taxYear)))", property.remainingBuildingBookValue(afterYear: taxYear).asCurrency])

        chapters.append(Chapter(
            title: "AfA-Herleitung – Gebäude",
            introLines: property.hasItemizedAncillaryCosts
                ? []
                : ["Anschaffungsnebenkosten als Gesamtsumme – eine Aufschlüsselung nach Makler/Notar/Auflassungsvormerkung kann in den Objektdaten hinterlegt werden."],
            summaryLines: [],
            columnHeaders: ["Position", "Wert"],
            rows: afaRows,
            // Bewusst höher als der Standard: alle Zeilen dieses Kapitels sind kurze Einzeiler ohne
            // Zeilenumbruch, sodass auch mit aufgeschlüsselten Nebenkosten-Einzelposten noch deutlich
            // mehr als die sonst übliche Zeilenzahl auf eine Seite passt – die Herleitung soll laut
            // ausdrücklichem Wunsch nicht auf eine Folgeseite umbrechen.
            rowsPerPage: 30
        ))

        // 2 · Jahresreihe Gebäude – historisch/aktuell/Prognose unterschieden. Startjahr identisch
        // mit `buildingAfA(forYear:)` (Übergang Nutzen/Lasten, ersatzweise Kaufdatum).
        if let afaStartDate = property.afaStartDate {
            let startYear = Calendar.current.component(.year, from: afaStartDate)
            let currentCalendarYear = Calendar.current.component(.year, from: .now)
            let endYear = max(taxYear, startYear + 9)
            if startYear <= endYear {
                var previousCumulative = 0.0
                var yearRows: [[String]] = []
                for year in startYear...endYear {
                    // `cumulativeBuildingAfA`/`remainingBuildingBookValue` deckeln bereits auf den
                    // Gebäudewert; der Jahresbetrag ergibt sich als Differenz zur Vorjahres-Summe,
                    // damit die Reihe bei vollständiger Abschreibung korrekt auf 0 fällt, statt den
                    // festen Jahressatz unbegrenzt über den Gebäudewert hinaus weiterzuzählen.
                    let cumulative = property.cumulativeBuildingAfA(uptoYear: year)
                    let amount = cumulative - previousCumulative
                    previousCumulative = cumulative
                    let remaining = property.remainingBuildingBookValue(afterYear: year)
                    let status: String
                    if year == taxYear { status = "gewähltes Jahr" }
                    else if year < currentCalendarYear { status = "historisch" }
                    else if year > currentCalendarYear { status = "Prognose" }
                    else { status = "laufendes Jahr" }
                    yearRows.append([String(year), property.buildingValue.asCurrency, property.afaRatePercent.asPercent, amount.asCurrency, cumulative.asCurrency, remaining.asCurrency, status])
                }
                chapters.append(Chapter(
                    title: "AfA-Herleitung – Jahresreihe Gebäude",
                    introLines: ["Vereinfachte Reihe mit dem heute maßgeblichen Satz auf alle Jahre angewendet – spätere Änderungen an Satz oder Bemessungsgrundlage wirken sich hier rückwirkend aus und ersetzen keine Anlagenbuchhaltung."],
                    summaryLines: [],
                    columnHeaders: ["Jahr", "Bemessungsgrdl.", "Satz", "Jahresbetrag", "Kumuliert", "Restbuchwert", "Status"],
                    rows: yearRows
                ))
            }
        }

        // 4 · Bewegliche Wirtschaftsgüter – im selben Bericht, aber als eigene Tabelle (keine
        // Vermischung der Methoden). Herstellungskosten am Gebäude (.improvement, z.B. eine
        // aktivierte Fassadendämmung) gehören NICHT hierhin, obwohl sie technisch auch ein
        // `DepreciableAsset` sind – sonst erscheinen Gebäudepositionen fälschlich als „bewegliche“
        // Wirtschaftsgüter/Einrichtung (siehe eigene Tabelle unten, analog zur Erstanlage).
        func assetRow(_ asset: DepreciableAsset) -> [String] {
            let cumulative = asset.cumulativeDepreciation(uptoYear: taxYear)
            let remaining = asset.remainingDepreciationBookValue(afterYear: taxYear)
            let method: String
            if asset.isImmediatelyDeductible {
                method = "Sofortabzug (GWG)"
            } else if asset.usesBuildingAfaRate {
                method = "wie Gebäude (\(property.afaRatePercent.asPercent))"
            } else {
                method = "\(asset.usefulLifeYears) Jahre"
            }
            return [
                asset.name,
                asset.placedInServiceDate.asShortDate,
                asset.depreciationBasis.asCurrency,
                method,
                asset.depreciation(forYear: taxYear).asCurrency,
                cumulative.asCurrency,
                remaining.asCurrency,
                belegLabel(asset.documents)
            ]
        }
        let assetColumnHeaders = ["Bezeichnung", "Anschaffung", "AK/Zeitwert", "Methode", "AfA \(String(taxYear))", "Bisherige AfA", "Restwert", "Beleg"]
        let allAssets = property.depreciableAssets ?? []
        let movableAssets = allAssets.filter { $0.category != .improvement }
        let improvementAssets = allAssets.filter { $0.category == .improvement }

        if !movableAssets.isEmpty {
            chapters.append(Chapter(
                title: "AfA-Herleitung – Bewegliche Wirtschaftsgüter",
                introLines: [],
                summaryLines: [],
                columnHeaders: assetColumnHeaders,
                rows: movableAssets.sorted { $0.placedInServiceDate < $1.placedInServiceDate }.map(assetRow)
            ))
        }
        if !improvementAssets.isEmpty {
            chapters.append(Chapter(
                title: "AfA-Herleitung – Herstellungskosten am Gebäude",
                introLines: ["Nachträglich aktivierte Positionen mit Gebäudebezug – werden wie das Gebäude selbst abgeschrieben, bewusst getrennt von den beweglichen Wirtschaftsgütern ausgewiesen."],
                summaryLines: [],
                columnHeaders: assetColumnHeaders,
                rows: improvementAssets.sorted { $0.placedInServiceDate < $1.placedInServiceDate }.map(assetRow)
            ))
        }

        // 5 · Maßnahmen und Änderungen – Überleitung der AfA-Bemessungsgrundlage für nachträglich
        // als Herstellungskosten aktivierte Positionen (siehe `CapitalizationDecision`), mit Bezug
        // zur ggf. zugrundeliegenden 15-%-Prüfung. Nur sichtbar, wenn mindestens eine Entscheidung
        // vorliegt – verhindert leere, irreführende Kapitel.
        let decisions = (property.capitalizationDecisions ?? []).sorted { $0.decidedAt < $1.decidedAt }
        if !decisions.isEmpty {
            let changeRows: [[String]] = decisions.map { decision in
                [
                    decision.decidedAt.asShortDate,
                    decision.resultingAsset?.name ?? "Herstellungskosten",
                    String(decision.effectiveYear),
                    decision.totalAmount.asCurrency,
                    decision.thresholdCase != nil ? "15-%-Grenze" : "manuell",
                    decision.reason.isEmpty ? "–" : decision.reason
                ]
            }
            chapters.append(Chapter(
                title: "AfA-Herleitung – Maßnahmen und Änderungen",
                introLines: ["Nachträglich als Herstellungskosten aktivierte Positionen werden als eigenes Wirtschaftsgut mit dem Gebäude-AfA-Satz abgeschrieben (siehe Tabelle „Herstellungskosten am Gebäude“) und erhöhen die Bemessungsgrundlage erst ab dem genannten Wirksamkeitsjahr – frühere Jahre bleiben unverändert."],
                summaryLines: [],
                columnHeaders: ["Entschieden am", "Maßnahme", "Wirksam ab", "Betrag", "Anlass", "Begründung"],
                rows: changeRows
            ))
        }

        return chapters
    }

    // MARK: - Kapitel: 15-%-Grenze (vier Teilkapitel, siehe Design-Analyse Abschnitt 7)

    private static func buildThresholdChapters(property: Property) -> [Chapter] {
        guard let thresholdCase = property.thresholdCase else { return [] }
        var chapters: [Chapter] = []

        // 1 · Ergebnisübersicht – rechnerisches Ergebnis, Vollständigkeit und Beurteilung getrennt.
        var resultLines: [String] = []
        resultLines.append("Zeitraum: \(thresholdCase.periodStart.asShortDate) – \(thresholdCase.periodEnd.asShortDate) · Heute: \(Date.now.asShortDate)")
        resultLines.append("Bemessungsgrundlage (Gebäude-AK ohne Grund, siehe AfA-Herleitung): \(thresholdCase.basisAmount.asCurrency) · Schwelle (15 %): \(thresholdCase.thresholdAmount.asCurrency)")
        resultLines.append("")
        let percentText = thresholdCase.utilizationPercent.map { " (\($0.asPercent))" } ?? ""
        resultLines.append("Rechnerisch (bekannt): \(thresholdCase.includedNetTotal.asCurrency) von \(thresholdCase.thresholdAmount.asCurrency)\(percentText)")
        if thresholdCase.possibleAdditionalAmount > 0 {
            resultLines.append("Zzgl. ungeklärter Positionen möglich: + \(thresholdCase.possibleAdditionalAmount.asCurrency)")
        }
        let totalCandidates = thresholdCase.candidateExpenses.count
        let classified = totalCandidates - thresholdCase.unclassifiedCount
        var completeness = "\(classified) von \(totalCandidates) Position(en) klassifiziert"
        if !thresholdCase.missingNetAmountExpenses.isEmpty {
            completeness += ", \(thresholdCase.missingNetAmountExpenses.count) ohne Netto-Betrag"
        }
        resultLines.append("Vollständigkeit: \(completeness)")
        resultLines.append("Beurteilung: \(thresholdCase.status.label) (Hinweis, keine abschließende steuerliche Würdigung)")

        chapters.append(Chapter(
            title: "15-%-Grenze – Ergebnisübersicht",
            introLines: [],
            summaryLines: resultLines,
            columnHeaders: [],
            rows: []
        ))

        // 2 · Kostenübersicht – mit Begründungsspalte und farblich codiertem Status.
        let costRows = thresholdCase.candidateExpenses.map { expense -> [String] in
            let assessment = thresholdCase.assessment(for: expense)
            let status = assessment?.status.label ?? "Nicht klassifiziert"
            let tone = toneForThresholdStatus(assessment?.status ?? .unclassified)
            let reason = (assessment?.reason.isEmpty == false) ? assessment!.reason : "–"
            return [expense.date.asShortDate, expense.title, expense.amount.asCurrency, expense.netAmount?.asCurrency ?? "unbekannt", tonedCell(status, tone), reason, belegLabel(expense.documents)]
        }
        if !costRows.isEmpty {
            chapters.append(Chapter(
                title: "15-%-Grenze – Kostenübersicht",
                introLines: ["Maßgeblich ist der Netto-Betrag. Jede Position ist einzeln mit Einordnung und – bei Ausschluss – Begründung aufgeführt."],
                summaryLines: [],
                columnHeaders: ["Datum", "Bezeichnung", "Brutto", "Netto", "Einordnung", "Begründung", "Beleg"],
                rows: costRows
            ))
        }

        // 3 · Offene Sachverhalte – namentlich, nicht nur als Zähler.
        var openRows: [[String]] = []
        for expense in thresholdCase.candidateExpenses.sorted(by: { $0.date < $1.date }) {
            let assessment = thresholdCase.assessment(for: expense)
            if (assessment?.status ?? .unclassified) == .unclassified {
                openRows.append([expense.date.asShortDate, expense.title, expense.amount.asCurrency, "Noch nicht klassifiziert"])
            } else if expense.netAmount == nil {
                openRows.append([expense.date.asShortDate, expense.title, expense.amount.asCurrency, "Kein Netto-Betrag ermittelbar (USt-Satz fehlt)"])
            }
        }
        if !openRows.isEmpty {
            chapters.append(Chapter(
                title: "15-%-Grenze – Offene Sachverhalte",
                introLines: ["Zur weiteren Klärung in der App unter 15-%-Grenze bzw. bei der jeweiligen Ausgabe."],
                summaryLines: [],
                columnHeaders: ["Datum", "Bezeichnung", "Betrag", "Offener Punkt"],
                rows: openRows
            ))
        }

        // 4 · Berechnungsherleitung – Schritt für Schritt mit laufender Summe statt nur Endergebnis.
        var runningSum = 0.0
        var calcRows: [[String]] = []
        for expense in thresholdCase.candidateExpenses.sorted(by: { $0.date < $1.date }) {
            guard let assessment = thresholdCase.assessment(for: expense), assessment.status.countsTowardThreshold, let net = expense.netAmount else { continue }
            runningSum += net
            calcRows.append(["\(expense.date.asShortDate) – \(expense.title)", net.asCurrency, runningSum.asCurrency])
        }
        if !calcRows.isEmpty {
            calcRows.append(["**Summe (einbezogene Positionen)", "", "**" + thresholdCase.includedNetTotal.asCurrency])
            calcRows.append(["Schwelle (15 % der Bemessungsgrundlage)", "", thresholdCase.thresholdAmount.asCurrency])
            chapters.append(Chapter(
                title: "15-%-Grenze – Berechnungsherleitung",
                introLines: ["Nur sicher oder nach Prüfung einbezogene Positionen mit bekanntem Netto-Betrag, chronologisch."],
                summaryLines: [],
                columnHeaders: ["Position", "Netto-Betrag", "Kumulierte Summe"],
                rows: calcRows
            ))
        }

        // 5 · Überleitung zur AfA – nur, wenn mindestens eine Aktivierungs-Entscheidung vorliegt
        // (siehe `CapitalizationDecision`); dokumentiert bewusst gewordene Herstellungskosten mit
        // Datum, Grund und Bezug zum entstandenen Wirtschaftsgut, statt die Verbindung zur AfA nur
        // anzudeuten.
        let decisions = thresholdCase.capitalizationDecisions
        if !decisions.isEmpty {
            let bridgeRows: [[String]] = decisions.map { decision in
                [
                    decision.decidedAt.asShortDate,
                    decision.resultingAsset?.name ?? "Herstellungskosten",
                    String(decision.effectiveYear),
                    decision.totalAmount.asCurrency,
                    decision.reason.isEmpty ? "–" : decision.reason
                ]
            }
            chapters.append(Chapter(
                title: "15-%-Grenze – Überleitung zur AfA",
                introLines: ["Diese Positionen wurden bewusst als Herstellungskosten aktiviert und erhöhen seit dem genannten Steuerjahr die AfA-Bemessungsgrundlage als eigenes Wirtschaftsgut (siehe AfA-Herleitung, Abschnitt „Maßnahmen und Änderungen“)."],
                summaryLines: [],
                columnHeaders: ["Entschieden am", "Maßnahme", "Wirksam ab", "Betrag", "Begründung"],
                rows: bridgeRows
            ))
        }

        return chapters
    }

    // MARK: - Kapitel: Erhaltungsaufwand und Herstellungskosten

    private static func buildMaintenanceChapter(property: Property, taxYear: Int) -> Chapter? {
        let items = property.allExpenses(forYear: taxYear).filter { $0.taxTreatment == .maintenanceExpense || $0.taxTreatment == .capitalized }
        guard !items.isEmpty else { return nil }
        let rows = items.sorted { $0.date < $1.date }.map { expense -> [String] in
            let einordnung: String
            if expense.taxTreatment == .capitalized {
                einordnung = expense.capitalizationDecision == nil ? tonedCell("Herstellungskosten – noch keine AfA", .warning) : "Herstellungskosten"
            } else {
                einordnung = "Erhaltungsaufwand"
            }
            return [expense.date.asShortDate, expense.title, expense.amount.asCurrency, einordnung, belegLabel(expense.documents)]
        }
        return Chapter(
            title: "Erhaltungsaufwand und Herstellungskosten",
            introLines: [],
            summaryLines: [
                "Erhaltungsaufwand \(String(taxYear)) (sofort abziehbar): \(property.maintenanceExpenses(forYear: taxYear).asCurrency)",
                "Herstellungskosten \(String(taxYear)) (aktiviert, siehe AfA): \(property.capitalizedExpenses(forYear: taxYear).asCurrency)"
            ],
            columnHeaders: ["Datum", "Bezeichnung", "Betrag", "Einordnung", "Beleg"],
            rows: rows
        )
    }

    // MARK: - Kapitel: Sonstige Werbungskosten (Einzelnachweis)

    private static func buildOtherExpensesChapter(property: Property, taxYear: Int) -> Chapter? {
        let calc = AnlageVCalculation(property: property, year: taxYear)
        let financingIDs = Set(calc.excludedFinancingExpenses.map(\.persistentModelID))
        let utilityIDs = Set(calc.excludedUtilityExpenses.map(\.persistentModelID))
        var rows = property.allExpenses(forYear: taxYear)
            .filter { $0.taxTreatment == .otherDeductible }
            .sorted { $0.date < $1.date }
            .map { expense -> [String] in
                var category = expense.category.label
                if financingIDs.contains(expense.persistentModelID) {
                    category = "\(category) (nicht angesetzt – Zinsen aus Finanzierung)"
                } else if utilityIDs.contains(expense.persistentModelID) {
                    category = "\(category) (nicht angesetzt – in Nebenkostenabrechnung)"
                }
                return [expense.date.asShortDate, expense.title, category, expense.amount.asCurrency, belegLabel(expense.documents)]
            }

        let travelRows = (property.travelExpenses ?? [])
            .filter { Calendar.current.component(.year, from: $0.date) == taxYear }
            .sorted { $0.date < $1.date }
            .map { trip -> [String] in
                [trip.date.asShortDate, trip.purpose.isEmpty ? "Fahrt" : trip.purpose, "Fahrtkosten (\(Int(trip.kilometers)) km × \(trip.ratePerKilometer.asCurrency))", trip.amount.asCurrency, "–"]
            }
        rows.append(contentsOf: travelRows)

        let homeOfficeDays = HomeOfficeAllocation.ownDays(for: property, taxYear: taxYear)
        if homeOfficeDays > 0 {
            let amount = HomeOfficeAllocation.apportionedAmount(for: property, taxYear: taxYear)
            rows.append(["", "Homeoffice-Pauschale (\(homeOfficeDays) Tage, anteilig)", "Homeoffice", amount.asCurrency, "–"])
        }

        if let breakdown = property.loanBreakdown(forYear: taxYear), breakdown.interest > 0 {
            rows.append(["", "Schuldzinsen (Finanzierung)", "Finanzierung", breakdown.interest.asCurrency, "–"])
        }
        guard !rows.isEmpty else { return nil }

        var introLines = ["Tilgungsanteile der Finanzierung sind keine Werbungskosten und daher nicht enthalten."]
        if HomeOfficeAllocation.isCapExceeded(for: property, taxYear: taxYear) {
            introLines.append("Hinweis: Die \(HomeOfficeAllocation.cappedDays(forYear: taxYear))-Tage-/\(HomeOfficeAllocation.annualCapAmount(forYear: taxYear).asCurrency)-Grenze der Homeoffice-Pauschale gilt pro Person über alle Immobilien hinweg und wurde hier bereits anteilig gedeckelt.")
        }

        return Chapter(
            title: "Sonstige Werbungskosten – Einzelnachweis",
            introLines: introLines,
            summaryLines: [],
            columnHeaders: ["Datum", "Bezeichnung", "Kategorie", "Betrag", "Beleg"],
            rows: rows
        )
    }

    // MARK: - Kapitel: Anlage V – Einnahmen und Werbungskosten

    /// Fasst Einnahmen, Werbungskosten und Ergebnis als eine Positions-/Betrags-Tabelle zusammen –
    /// Aufbau und Zeilenbezeichnungen bewusst wie im Arbeitsblatt „Anlage V“ der mitgelieferten
    /// Steuererklärungs-Vorlage (Positionen in Zeilen statt Fließtext, EINNAHMEN/WERBUNGSKOSTEN/
    /// ERGEBNIS als Abschnitte). Zeilen mit „##“ sind Abschnittsüberschriften, mit „**“ Summenzeilen
    /// (siehe `TaxPDFChapterPage`).
    private static func buildAnlageVChapter(property: Property, taxYear: Int) -> Chapter? {
        let calc = AnlageVCalculation(property: property, year: taxYear)
        guard calc.totalIncome != 0 || calc.totalWerbungskosten != 0 else { return nil }

        var rows: [[String]] = [
            ["##EINNAHMEN", ""],
            ["Mieteinnahmen (Kaltmiete)", calc.coldRentIncome.asCurrency],
            ["Umlagen (vereinnahmte Nebenkostenvorauszahlungen)", calc.utilityAdvanceIncome.asCurrency],
            ["**Summe Einnahmen", calc.totalIncome.asCurrency],
            ["##WERBUNGSKOSTEN", ""],
            ["AfA Gebäude", calc.buildingAfa.asCurrency],
            ["AfA bewegliche Wirtschaftsgüter (Einrichtung)", calc.movableAssetAfa.asCurrency]
        ]
        if calc.improvementAssetAfa > 0 {
            rows.append(["AfA Herstellungskosten am Gebäude (aktiviert, siehe AfA-Bericht)", calc.improvementAssetAfa.asCurrency])
        }
        rows.append(contentsOf: [
            ["Schuldzinsen", calc.interest.asCurrency],
            ["Erhaltungsaufwand/Instandhaltung", calc.maintenance.asCurrency],
            ["Betriebskosten lt. Nebenkostenabrechnung (ohne Rücklage)", calc.utilityCosts.asCurrency],
            ["Fahrtkosten", calc.travel.asCurrency],
            ["Homeoffice-Pauschale", calc.homeOffice.asCurrency],
            ["Sonstige Werbungskosten", calc.otherDeductible.asCurrency],
            ["**Summe Werbungskosten", calc.totalWerbungskosten.asCurrency],
            ["##ERGEBNIS", ""],
            ["**Einkünfte aus Vermietung und Verpachtung", calc.result.asCurrency]
        ])
        if let share = calc.ownershipSharePercent, let ownResult = calc.ownerShareOfResult {
            rows.append(["davon Anteil lt. Eigentumsanteil (\(share.asPercent))", ownResult.asCurrency])
        }

        var intro = [
            "Einkünfte aus Vermietung und Verpachtung, Steuerjahr \(String(taxYear)). Einnahmen nach Zahlungseingang, dem Fälligkeitsmonat zugeordnet. Tilgungsanteile sind keine Werbungskosten und daher nicht enthalten.",
            "Vollständige AfA-Herleitung (inkl. Anschaffungsnebenkosten- und Grund-und-Boden-Aufteilung): siehe AfA-Bericht."
        ]
        if calc.estimatedRentMonths > 0 {
            intro.append("\(calc.estimatedRentMonths) Mietmonat(e) ohne erfasste Zahlung wurden mit der vereinbarten Miete angesetzt – bitte mit den tatsächlichen Zahlungseingängen abgleichen.")
        }
        if !calc.excludedFinancingExpenses.isEmpty {
            intro.append("Nicht angesetzt, da die Schuldzinsen aus der hinterlegten Finanzierung berechnet werden: \(calc.excludedFinancingExpenses.count) Ausgabe(n) der Kategorie „Finanzierung“ (\(calc.excludedFinancingExpenses.reduce(0.0) { $0 + $1.amount }.asCurrency)). Finanzierungsnebenkosten wie Bereitstellungszinsen bitte einer anderen Kategorie zuordnen.")
        }
        if !calc.excludedUtilityExpenses.isEmpty {
            intro.append("Nicht angesetzt, da bereits in der Nebenkostenabrechnung enthalten: \(calc.excludedUtilityExpenses.count) Ausgabe(n) der Kategorie „Betriebskosten“ (\(calc.excludedUtilityExpenses.reduce(0.0) { $0 + $1.amount }.asCurrency)).")
        }
        if !calc.excludedReserveItems.isEmpty {
            intro.append("Zuführung zur Instandhaltungsrücklage (\(calc.excludedReserveItems.reduce(0.0) { $0 + $1.amount }.asCurrency)) nicht angesetzt – abziehbar erst bei Verwendung für Erhaltungsmaßnahmen.")
        }
        if calc.utilityCostsMissing {
            intro.append("Umlagen vereinnahmt, aber keine Betriebskosten erfasst – Nebenkostenabrechnung des Jahres ergänzen, sonst ist das Ergebnis zu hoch.")
        }
        if calc.ownershipSharePercent != nil {
            intro.append("Bei Miteigentum (Bruchteilsgemeinschaft) werden die Einkünfte in der Regel gesondert und einheitlich festgestellt; der Anteil dient der Orientierung.")
        }

        return Chapter(
            title: "Anlage V – Einnahmen und Werbungskosten",
            introLines: intro,
            summaryLines: [],
            columnHeaders: ["Position", "Betrag"],
            rows: rows
        )
    }

    // MARK: - Kapitel: Belegverzeichnis

    private static func buildDocumentsChapter(property: Property, taxYear: Int) -> Chapter? {
        // `resolvedProperty` verzweigt über mehrere optionale Beziehungen (Einheit, Mietverhältnis,
        // Ausgabe, Nebenkostenabrechnung, Wirtschaftsgut) und lässt sich daher nicht in ein
        // #Predicate fassen – die Jahresgrenze aber schon: das begrenzt den geladenen Datensatz bei
        // vielen Belegen über mehrere Jahre spürbar, statt wie zuvor ausnahmslos alle Dokumente der
        // App zu laden und erst danach zu filtern.
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: taxYear, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: taxYear + 1, month: 1, day: 1)) else { return nil }
        let predicate = #Predicate<Document> { $0.receiptDate >= yearStart && $0.receiptDate < yearEnd }
        let descriptor = FetchDescriptor<Document>(predicate: predicate)
        let documentsInYear = (try? property.modelContext?.fetch(descriptor)) ?? []
        let documents = documentsInYear.filter { $0.resolvedProperty?.persistentModelID == property.persistentModelID }
        guard !documents.isEmpty else { return nil }
        let rows = documents.sorted { $0.receiptDate < $1.receiptDate }.map { document -> [String] in
            [document.receiptDate.asShortDate, document.title.isEmpty ? document.fileName : document.title, document.linkedToDescription]
        }
        return Chapter(
            title: "Belegverzeichnis \(String(taxYear))",
            introLines: ["Verzeichnis der zugeordneten Belege, ohne die Originaldokumente selbst einzubinden."],
            summaryLines: [],
            columnHeaders: ["Belegdatum", "Bezeichnung", "Zugeordnet zu"],
            rows: rows
        )
    }
}

// MARK: - Design-System der Steuerreports

/// Ein einziges, durchgängiges Erscheinungsbild für beide Steuerreports (Erstanlage und laufender
/// Betrieb) – weißer Hintergrund, dunkles Marineblau als alleinige Akzentfarbe, zurückhaltende
/// Grautöne, feine Trennlinien statt Kästen/Balken. Bewusst nicht die App-Akzentfarbe
/// (`Theme.accent`), da PDFs fürs Finanzamt unabhängig vom App-weiten Erscheinungsbild eine eigene,
/// gleichbleibend seriöse Dokumentoptik behalten. Ersetzt die früher wählbaren zwei Layout-Vorlagen
/// („Ergebnis zuerst“/„Formular-Raster“) durch ein gemeinsames, verbindliches Designsystem – siehe
/// Antwort an den Nutzer für die Begründung dieser Konsolidierung.
private enum TaxPDFPalette {
    static let accent = Color(red: 0.067, green: 0.161, blue: 0.298)
    static let tableHeaderDivider = accent
    static let sectionDivider = Color.black.opacity(0.16)
    static let rowDivider = Color.black.opacity(0.09)
    static let sumRowFill = accent.opacity(0.045)
    static let textPrimary = Color.black.opacity(0.87)
    static let textSecondary = Color.black.opacity(0.52)
}

/// Grobe Heuristik, ob eine Zellen-Zeichenkette ein Betrag/Prozentwert ist (endet auf „€"/„%" oder
/// besteht nur aus Ziffern/Zahlformat-Zeichen) – bestimmt, ob eine Spalte rechtsbündig dargestellt
/// wird, ohne sich auf Spaltenüberschriften verlassen zu müssen (die je Kapitel stark variieren, von
/// „Betrag" bis „Bemessungsgrdl." oder „Restbuchwert").
private func isNumericLikeCell(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return false }
    if trimmed.hasSuffix("€") || trimmed.hasSuffix("%") { return true }
    return trimmed.allSatisfy { $0.isNumber || ",.-".contains($0) }
}

/// Zerlegt eine Zelle in Anzeigetext + optionalen Farbton anhand des „§tone§…"-Präfixes (siehe
/// `TaxReportPDFBuilder.tonedCell`).
private func parsedTaxCell(_ cell: String) -> (text: String, tone: Theme.StatusTone?) {
    if cell.hasPrefix("§good§") { return (String(cell.dropFirst(6)), .good) }
    if cell.hasPrefix("§warn§") { return (String(cell.dropFirst(6)), .warning) }
    if cell.hasPrefix("§bad§") { return (String(cell.dropFirst(5)), .critical) }
    return (cell, nil)
}

private struct TaxPDFHeader: View {
    let propertyLabel: String
    let kind: TaxReportKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(propertyLabel)
                Spacer()
                Text(kind.taxYear.map { "Steuerjahr \(String($0))" } ?? "Erstanlage")
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(TaxPDFPalette.textSecondary)
            Rectangle().fill(TaxPDFPalette.sectionDivider).frame(height: 0.75)
        }
    }
}

private struct TaxPDFFooter: View {
    let propertyLabel: String
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(TaxPDFPalette.sectionDivider).frame(height: 0.75)
            HStack(alignment: .firstTextBaseline) {
                Text(propertyLabel)
                Spacer()
                Text("Seite \(String(pageNumber)) von \(String(totalPages))")
            }
            .font(.system(size: 7.5))
            .foregroundStyle(TaxPDFPalette.textSecondary)
        }
    }
}

private struct TaxPDFCoverPage: View {
    let property: Property
    let kind: TaxReportKind
    let generatedAt: Date
    let pageNumber: Int
    let totalPages: Int

    private var footerLabel: String {
        let name = property.name.isEmpty ? property.address : property.name
        return "\(name) · \(property.address)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STEUERLICHE UNTERLAGEN")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(TaxPDFPalette.accent)
                .tracking(1.2)
            Text(kind.documentTitle)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(TaxPDFPalette.textPrimary)
                .padding(.top, 4)
            Text("Einkünfte aus Vermietung und Verpachtung · Anlage V")
                .font(.system(size: 10.5))
                .foregroundStyle(TaxPDFPalette.textSecondary)
                .padding(.top, 2)

            Rectangle().fill(TaxPDFPalette.accent).frame(height: 1.3).padding(.top, 16)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("Immobilie").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(property.name.isEmpty ? property.address : property.name).font(.system(size: 10))
                }
                GridRow {
                    Text("Adresse").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(property.address).font(.system(size: 10))
                }
                if let taxYear = kind.taxYear {
                    GridRow {
                        Text("Steuerjahr").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(TaxPDFPalette.textSecondary)
                        Text(String(taxYear)).font(.system(size: 10)).monospacedDigit()
                    }
                }
                GridRow {
                    Text("Erstellt am").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(generatedAt.asShortDate).font(.system(size: 10)).monospacedDigit()
                }
            }
            .padding(.top, 18)

            if case .initialSetup = kind {
                acquisitionSummary.padding(.top, 24)
            }

            Spacer(minLength: 20)

            Text("Diese Zusammenstellung ist eine Arbeits- und Nachweisunterlage auf Basis der in der App erfassten Daten. Sie ist keine amtliche Steuererklärung und stellt keine behördliche Anerkennung der enthaltenen Beträge oder steuerlichen Einordnungen dar.")
                .font(.system(size: 8.5))
                .foregroundStyle(TaxPDFPalette.textSecondary)
                .padding(.bottom, 10)

            TaxPDFFooter(propertyLabel: footerLabel, pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(TaxPDFPalette.textPrimary)
    }

    /// Zentrale Anschaffungsdaten + kurze Zusammenfassung direkt auf Seite 1 der Erstanlage (siehe
    /// Auftrag Abschnitt 3) – statt einer separaten, fast leeren Titelseite ohne Inhalt.
    @ViewBuilder
    private var acquisitionSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ZENTRALE ANSCHAFFUNGSDATEN")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TaxPDFPalette.accent)
                .tracking(0.8)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Text("Kaufpreis").font(.system(size: 9.5)).foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(property.purchasePrice.asCurrency).font(.system(size: 9.5)).monospacedDigit()
                }
                GridRow {
                    Text("Kaufdatum").font(.system(size: 9.5)).foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(property.purchaseDate?.asShortDate ?? "nicht erfasst").font(.system(size: 9.5))
                }
                GridRow {
                    Text("Baujahr").font(.system(size: 9.5)).foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(property.constructionYear.map { String($0) } ?? "nicht erfasst").font(.system(size: 9.5))
                }
                if property.buildingValue > 0 {
                    GridRow {
                        Text("AfA-Bemessungsgrundlage Gebäude").font(.system(size: 9.5)).foregroundStyle(TaxPDFPalette.textSecondary)
                        Text(property.buildingValue.asCurrency).font(.system(size: 9.5)).monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct TaxPDFTOCPage: View {
    let propertyLabel: String
    let kind: TaxReportKind
    let entries: [(title: String, page: Int)]
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaxPDFHeader(propertyLabel: propertyLabel, kind: kind)
            Text("Inhaltsverzeichnis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TaxPDFPalette.textPrimary)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(String(index + 1)). \(entry.title)")
                        Spacer()
                        Text(String(entry.page)).monospacedDigit()
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(TaxPDFPalette.textPrimary)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(TaxPDFPalette.rowDivider).frame(height: 0.5)
                    }
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 0)
            TaxPDFFooter(propertyLabel: propertyLabel, pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(TaxPDFPalette.textPrimary)
    }
}

private struct TaxPDFChapterPage: View {
    let propertyLabel: String
    let kind: TaxReportKind
    let title: String
    let introLines: [String]
    let summaryLines: [String]
    let columnHeaders: [String]
    let rows: [[String]]
    /// Feste Fakten-Zeilen vor den Tabellen (siehe `TaxReportPDFBuilder.Chapter.headerFacts`).
    var headerFacts: [(label: String, value: String)] = []
    /// Mehrere eigenständige Tabellen auf einer Seite (siehe `TaxReportPDFBuilder.Chapter.additionalTables`).
    var additionalTables: [(title: String, columnHeaders: [String], rows: [[String]])] = []
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaxPDFHeader(propertyLabel: propertyLabel, kind: kind)
            content
            Spacer(minLength: 0)
            TaxPDFFooter(propertyLabel: propertyLabel, pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(TaxPDFPalette.textPrimary)
    }

    /// Letzte „**"-markierte Zeile (der Abschluss-/Ergebniswert eines Kapitels) als (Label, Wert) –
    /// nil, wenn das Kapitel keine solche Zeile hat (reine Belegtabellen o.ä.).
    private var headline: (label: String, value: String)? {
        guard let lastTotal = rows.last(where: { $0.first?.hasPrefix("**") == true }) else { return nil }
        let label = String((lastTotal.first ?? "").dropFirst(2))
        var value = lastTotal.count > 1 ? (lastTotal.last ?? "") : ""
        if value.hasPrefix("**") { value = String(value.dropFirst(2)) }
        return (label, value)
    }

    /// Fallback-Kopfzeile für Kapitel ohne Tabelle (nur `summaryLines`, z.B. 15-%-Grenze-Übersicht):
    /// die erste nichtleere Zusammenfassungszeile.
    private var fallbackHeadlineLine: String? {
        guard headline == nil, rows.isEmpty else { return nil }
        return summaryLines.first(where: { !$0.isEmpty })
    }

    private var remainingSummaryLines: [String] {
        guard let line = fallbackHeadlineLine, let idx = summaryLines.firstIndex(of: line) else { return summaryLines }
        var copy = summaryLines
        copy.remove(at: idx)
        return copy
    }

    private var tableRowsExcludingHeadline: [[String]] {
        guard let lastIndex = rows.lastIndex(where: { $0.first?.hasPrefix("**") == true }) else { return rows }
        var copy = rows
        copy.remove(at: lastIndex)
        // Falls die entfernte Zeile der einzige Inhalt ihres „##"-Abschnitts war, bliebe sonst eine
        // leere Abschnittsüberschrift ohne jede Zeile darunter stehen (z.B. „ERGEBNIS" ohne
        // Ergebniszeile, weil genau die in die Kopfzeile oben gewandert ist) – die wird dann ebenfalls
        // entfernt, statt als Karteileiche im Kapitel zu bleiben.
        if lastIndex > 0, rows[lastIndex - 1].first?.hasPrefix("##") == true {
            let isLastRow = lastIndex == rows.count - 1
            let nextIsNewSection = !isLastRow && rows[lastIndex + 1].first?.hasPrefix("##") == true
            if isLastRow || nextIsNewSection {
                copy.remove(at: lastIndex - 1)
            }
        }
        return copy
    }

    @ViewBuilder
    private func headlineLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Rectangle().fill(TaxPDFPalette.accent).frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(TaxPDFPalette.accent)
                    .tracking(0.4)
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(TaxPDFPalette.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(TaxPDFPalette.textPrimary)
            .padding(.top, 12)

        if !introLines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(introLines, id: \.self) { line in
                    Text(line).font(.system(size: 8.5)).foregroundStyle(TaxPDFPalette.textSecondary)
                }
            }
            .padding(.top, 5)
        }

        if let headline {
            headlineLine(label: headline.label, value: headline.value).padding(.top, 12)
        } else if let fallbackHeadlineLine {
            Text(fallbackHeadlineLine)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TaxPDFPalette.accent)
                .padding(.top, 12)
        }

        if !remainingSummaryLines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(remainingSummaryLines.enumerated()), id: \.offset) { _, line in
                    if line.isEmpty {
                        Color.clear.frame(height: 5)
                    } else {
                        Text(line).font(.system(size: 9.5)).foregroundStyle(TaxPDFPalette.textPrimary)
                    }
                }
            }
            .padding(.top, 10)
        }


        if !columnHeaders.isEmpty {
            TaxPDFTable(columnHeaders: columnHeaders, rows: tableRowsExcludingHeadline)
                .padding(.top, 18)
        }

        if !headerFacts.isEmpty {
            factsGrid.padding(.top, 14)
        }

        ForEach(Array(additionalTables.enumerated()), id: \.offset) { index, block in
            Text(block.title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(TaxPDFPalette.accent)
                .tracking(0.4)
                .padding(.top, index == 0 && headerFacts.isEmpty ? 14 : 16)
            TaxPDFTable(columnHeaders: block.columnHeaders, rows: block.rows)
                .padding(.top, 6)
        }
    }

    /// Objekt-/Anschaffungsdaten als kompakte Label/Wert-Zeilen vor den A–D-Tabellen der neu
    /// strukturierten Erstanlage-Seite 1 – bewusst kein generisches Tabellenformat, da es sich um
    /// Einzelfakten statt um Positionen mit Beträgen handelt.
    @ViewBuilder
    private var factsGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(Array(headerFacts.enumerated()), id: \.offset) { _, fact in
                GridRow {
                    Text(fact.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TaxPDFPalette.textSecondary)
                    Text(fact.value)
                        .font(.system(size: 9.5))
                        .foregroundStyle(TaxPDFPalette.textPrimary)
                }
            }
        }
    }
}

/// Eigenständige, wiederverwendbare Tabellen-Komponente (Kopfzeile, „##"-Abschnitte, „**"-Summenzeilen,
/// spaltenweise Rechts-/Linksbündigkeit) – sowohl für die einzelne Haupttabelle eines Kapitels als
/// auch für mehrere unabhängige Tabellen auf einer Seite (z.B. Erstanlage-Seite 1, Abschnitte A–D).
private struct TaxPDFTable: View {
    let columnHeaders: [String]
    let rows: [[String]]

    /// Je Spalte, ob sie überwiegend betrags-/zahlenartige Werte enthält – bestimmt die Ausrichtung
    /// von Kopf- UND Datenzellen dieser Spalte einheitlich (statt pro Zelle unabhängig zu
    /// entscheiden), damit z.B. eine „Betrag"-Überschrift über rechtsbündigen Eurobeträgen selbst
    /// auch rechtsbündig steht.
    private var columnIsNumeric: [Bool] {
        guard !columnHeaders.isEmpty else { return [] }
        var flags = Array(repeating: false, count: columnHeaders.count)
        let dataRows = rows.filter { ($0.first?.hasPrefix("##") ?? false) == false }
        for col in 0..<columnHeaders.count {
            var numericCount = 0
            var total = 0
            for row in dataRows {
                guard col < row.count else { continue }
                var text = row[col]
                if text.hasPrefix("**") { text = String(text.dropFirst(2)) }
                text = parsedTaxCell(text).text
                guard !text.isEmpty else { continue }
                total += 1
                if isNumericLikeCell(text) { numericCount += 1 }
            }
            flags[col] = total > 0 && Double(numericCount) / Double(total) > 0.5
        }
        return flags
    }

    private func columnAlignment(_ index: Int, in flags: [Bool]) -> HorizontalAlignment {
        (index < flags.count && flags[index]) ? .trailing : .leading
    }

    @ViewBuilder
    private func cell(_ text: String, alignment: HorizontalAlignment = .leading, bold: Bool = false, sumFill: Bool = false, tone: Theme.StatusTone? = nil, isHeader: Bool = false, isLastRow: Bool = false, minWidth: CGFloat? = nil) -> some View {
        Text(text)
            .font(.system(size: isHeader ? 8 : 9, weight: (bold || isHeader) ? .bold : .regular))
            .monospacedDigit()
            .tracking(isHeader ? 0.3 : 0)
            .foregroundStyle(isHeader ? TaxPDFPalette.accent : (tone?.color ?? TaxPDFPalette.textPrimary))
            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            // Ohne `fixedSize` ermittelt SwiftUI in diesem Grid manchmal nur die einzeilige
            // Idealhöhe und schneidet lange Bezeichnungen mit „…" ab, statt sie – wie gewünscht –
            // kontrolliert umzubrechen; erzwingt stattdessen immer die mehrzeilige Höhe. Horizontal
            // bewusst NICHT fixiert: ein `fixedSize(horizontal: true)` auf zahlenartigen Zellen (um
            // ein Umbrechen mitten in der Zahl, z.B. "28.10.202"/"5", zu verhindern) erzwingt deren
            // volle, unkomprimierte Idealbreite – bei vielen Spalten (z.B. eine achtspaltige
            // Tabelle) kann die Summe dieser Idealbreiten die verfügbare Seitenbreite übersteigen,
            // wodurch `Grid` über den Rand hinauswächst und der PDF-Renderer die GANZE Seite links
            // abschneidet. Stattdessen übernimmt `columnMinWidth` (s.u.) für zahlenartige Spalten
            // eine Mindestbreite, die ein Umbrechen mitten in der Zahl bei realistischen Beträgen/
            // Daten ebenso zuverlässig verhindert, ohne das Seitenbudget zu sprengen.
            .fixedSize(horizontal: false, vertical: true)
            // Oben statt mittig ausgerichtet: bei unterschiedlicher Zeilenzahl je Zelle (lange
            // Bezeichnungen brechen um, kurze Beträge nicht) sorgt eine vertikale Mittelausrichtung
            // sonst für eine Y-Position, die nicht mehr zur restlichen Zeile passt – das verwirrt
            // sowohl das Auge als auch die PDF-Textextraktion (Lesereihenfolge nach Y-Position).
            // `minWidth` auf der ersten (Label-)Spalte: ohne sie verteilt `Grid` bei lauter
            // `maxWidth: .infinity`-Zellen die Breite nahezu gleichmäßig, auch wenn die Label-Spalte
            // deutlich längeren Text trägt als die übrigen – das erzwingt unnötige, teils mitten im
            // Wort umbrechende Zeilenumbrüche statt eines angemessen breiteren ersten Spalte.
            .frame(minWidth: minWidth, maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
            .padding(.horizontal, 6)
            .padding(.vertical, isHeader ? 5 : 6)
            // Zweites `frame` mit `maxHeight: .infinity`: ohne das füllt die Zelle nur die Höhe
            // ihres eigenen (ggf. kürzeren) Inhalts, nicht die vom Grid vergebene Zeilenhöhe – bei
            // unterschiedlich hohen Nachbarzellen in derselben Zeile (umgebrochene Bezeichnung neben
            // einzeiligem Betrag) landete die untere Trennlinie dann auf unterschiedlicher Höhe und
            // wirkte schief/uneben, statt eine durchgehend gerade Linie über die ganze Zeile zu bilden.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
            .background(sumFill ? TaxPDFPalette.sumRowFill : Color.clear)
            .overlay(alignment: .bottom) {
                if isHeader {
                    Rectangle().fill(TaxPDFPalette.tableHeaderDivider).frame(height: 1.2)
                } else if !isLastRow {
                    Rectangle().fill(TaxPDFPalette.rowDivider).frame(height: 0.5)
                }
            }
    }

    @ViewBuilder
    private func sectionRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(TaxPDFPalette.accent)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TaxPDFPalette.sectionDivider).frame(height: 0.75)
            }
    }

    /// Mindestbreiten je Spalte, konstruktionsbedingt budgetiert: die Summe aller Mindestbreiten
    /// darf die verfügbare Seitenbreite (595pt Seitenbreite − 2×44pt Innenabstand ≈ 507pt, siehe
    /// `TaxReportPDFBuilder.pageSize`/`TaxPDFChapterPage`) bei der in dieser App größten
    /// vorkommenden Spaltenzahl (8: Spalte 0 mit 100pt + 7 weitere mit je 54pt = 478pt) nie
    /// übersteigen. Ursprünglich wurde das Umbrechen zahlenartiger Zellen mitten in der Zahl (z.B.
    /// "28.10.202"/"5") über `fixedSize(horizontal: true)` auf der Zelle selbst verhindert – das
    /// erzwingt aber die volle, unkomprimierte Idealbreite jeder einzelnen Zelle, und bei vielen
    /// Spalten (z.B. der achtspaltigen AfA-Tabelle) summierten sich diese Idealbreiten auf mehr als
    /// die verfügbare Seitenbreite: `Grid` wuchs über den Seitenrand hinaus, und der PDF-Renderer
    /// schnitt daraufhin die GESAMTE Seite links ab, statt nur die Tabelle zu stauchen. Eine fest
    /// budgetierte Mindestbreite verhindert das Umbrechen mitten in der Zahl für realistische
    /// Beträge/Daten genauso zuverlässig, ohne dieses Seitenbudget je zu sprengen.
    /// Spalte 0 (die Bezeichnung) bekommt bei bis zu sechs Spalten die volle, großzügige
    /// Mindestbreite (130pt) – dort ist genug Budget übrig, und lange zusammengesetzte Begriffe
    /// (z.B. "Auflassungsvormerkung") sollen nicht mitten im Wort umbrechen müssen. Erst ab sieben
    /// Spalten (den beiden achtspaltigen AfA-Tabellen) wird sie enger budgetiert (100pt) – dort
    /// kommen ohnehin nur kurze, frei vergebene Bezeichnungen vor (Wirtschaftsgut-Namen).
    private func columnMinWidth(_ index: Int, in flags: [Bool]) -> CGFloat? {
        guard columnHeaders.count >= 3 else { return nil }
        if index == 0 { return columnHeaders.count >= 7 ? 100 : 130 }
        if index < flags.count, flags[index] { return 54 }
        if columnHeaders.count >= 5, index < flags.count, !flags[index] { return 54 }
        return nil
    }

    var body: some View {
        let flags = columnIsNumeric
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(columnHeaders.enumerated()), id: \.offset) { index, header in
                    cell(header.uppercased(), alignment: columnAlignment(index, in: flags), isHeader: true, minWidth: columnMinWidth(index, in: flags))
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let isLast = index == rows.count - 1
                if row.first?.hasPrefix("##") == true {
                    GridRow {
                        sectionRow(String((row.first ?? "").dropFirst(2)))
                            .gridCellColumns(max(columnHeaders.count, 1))
                    }
                } else if row.first?.hasPrefix("**") == true {
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, c in
                            let display = c.hasPrefix("**") ? String(c.dropFirst(2)) : c
                            cell(display, alignment: columnAlignment(colIndex, in: flags), bold: true, sumFill: true, isLastRow: isLast, minWidth: columnMinWidth(colIndex, in: flags))
                        }
                    }
                } else {
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, c in
                            let parsed = parsedTaxCell(c)
                            cell(parsed.text, alignment: columnAlignment(colIndex, in: flags), tone: parsed.tone, isLastRow: isLast, minWidth: columnMinWidth(colIndex, in: flags))
                        }
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(TaxPDFPalette.sectionDivider, lineWidth: 0.75))
        // Die `maxHeight: .infinity`-Zellen (siehe `cell(...)`) machen das gesamte Grid selbst
        // vertikal flexibel – ohne `fixedSize` würde die Tabelle dadurch in der umgebenden Seite
        // unkontrolliert wachsen und sich den Platz des abschließenden `Spacer` (der die Fußzeile
        // nach unten schiebt) streitig machen, statt bei ihrer natürlichen Inhaltshöhe zu bleiben.
        .fixedSize(horizontal: false, vertical: true)
    }
}
