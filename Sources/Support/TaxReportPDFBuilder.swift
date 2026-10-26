import SwiftUI
import SwiftData
import PDFKit

/// Welcher der beiden getrennten Steuerreports erzeugt werden soll (siehe Auftrag Abschnitt 3,
/// Modus A/B): die einmalige Erstanlage (Objekt-/Anschaffungsdaten, AfA-Herleitung, 15-%-Grenze,
/// Möbelverzeichnis) oder der laufende Betrieb eines bestimmten Steuerjahres (Werbungskosten,
/// Einnahmen, Belege, Jahres-Checkliste).
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
        /// Optionaler Ist/Soll-Balken direkt unter den Zusammenfassungszeilen (z.B. Auslastung der
        /// 15-%-Grenze) – derselbe `UtilizationBar`-Baustein wie im Steuer-Cockpit.
        var progressFraction: Double? = nil
        var progressTone: Theme.StatusTone = .neutral

        var pageCount: Int { max(1, Int(ceil(Double(rows.count) / Double(maxRowsPerPage)))) }

        func rowsForPage(_ pageIndex: Int) -> [[String]] {
            let start = pageIndex * maxRowsPerPage
            guard start < rows.count else { return [] }
            return Array(rows[start..<min(start + maxRowsPerPage, rows.count)])
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

    private static func toneForThresholdCaseStatus(_ status: ThresholdCaseStatus) -> Theme.StatusTone {
        switch status {
        case .belowThreshold, .completed: return .good
        case .thresholdReached: return .warning
        case .exceeded: return .critical
        case .notConclusivelyCheckable: return .neutral
        }
    }

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

        switch kind {
        case .initialSetup:
            let asOfYear = Calendar.current.component(.year, from: generatedAt)
            add(buildObjectChapter(property: property), otherwiseWarn: "Objekt- und Anschaffungsdaten")
            addAll(buildAfaChapters(property: property, taxYear: asOfYear), otherwiseWarn: "AfA-Herleitung")
            addAll(buildThresholdChapters(property: property), otherwiseWarn: "15-%-Grenze")
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
                        progressFraction: pageIndex == 0 ? chapter.progressFraction : nil,
                        progressTone: chapter.progressTone,
                        columnHeaders: chapter.columnHeaders,
                        rows: rowsForPage,
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Steuerunterlagen \(safeName) – \(kind.documentTitle).pdf")
        do {
            try merged.write(to: url, options: .atomic)
            return (url, warnings)
        } catch {
            return (nil, warnings)
        }
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

    // MARK: - Kapitel: Objekt- und Anschaffungsdaten

    private static func buildObjectChapter(property: Property) -> Chapter? {
        guard property.purchasePrice > 0 || property.purchaseDate != nil else { return nil }
        var lines: [String] = []
        lines.append("Kaufpreis: \(property.purchasePrice.asCurrency)")
        lines.append("Kaufnebenkosten: \(property.purchaseAncillaryCosts.asCurrency)")
        lines.append("Kaufdatum (Beurkundung): \(property.purchaseDate?.asShortDate ?? "nicht erfasst")")
        lines.append("Wirtschaftlicher Übergang: \(property.economicTransferDate?.asShortDate ?? "nicht erfasst")")
        if let year = property.constructionYear { lines.append("Baujahr: \(String(year))") }
        lines.append("Grund und Boden (lt. Kaufvertrag, ohne Nebenkosten): \(property.landValue.asCurrency) (\((property.landValuePercentage * 100).asPercent))")
        return Chapter(title: "Objekt- und Anschaffungsdaten", introLines: [], summaryLines: lines, columnHeaders: [], rows: [])
    }

    // MARK: - Kapitel: AfA-Herleitung (vier Teilkapitel, siehe Design-Analyse Abschnitt 8)

    private static func buildAfaChapters(property: Property, taxYear: Int) -> [Chapter] {
        guard property.buildingValue > 0 else { return [] }
        var chapters: [Chapter] = []

        // 1 · Ergebnis und Anschaffungskosten
        var lines: [String] = []
        lines.append("Gebäude-AfA \(String(taxYear)): \(property.buildingAfA(forYear: taxYear).asCurrency) · Bewegliche Wirtschaftsgüter: \(property.assetDepreciation(forYear: taxYear).asCurrency) · Summe: \(property.totalAfa(forYear: taxYear).asCurrency)")
        lines.append("Kumulierte Gebäude-AfA: \(property.cumulativeBuildingAfA(uptoYear: taxYear).asCurrency) · Restbuchwert: \(property.remainingBuildingBookValue(afterYear: taxYear).asCurrency)")
        lines.append("")
        lines.append("1 · Kaufpreis gesamt: \(property.purchasePrice.asCurrency)")
        if property.purchaseAncillaryCosts > 0 {
            lines.append("2 · Anschaffungsnebenkosten (Gesamtsumme): \(property.purchaseAncillaryCosts.asCurrency)")
        }
        lines.append("3 · Anschaffungskosten gesamt (1+2): \(property.totalAcquisitionCost.asCurrency)")
        lines.append("4 · Grund-und-Boden-Anteil (lt. Kaufvertrag): \((property.landValuePercentage * 100).asPercent)")
        lines.append("5 · Grund und Boden, anteilig inkl. Nebenkosten (3×4): \(property.apportionedLandValue.asCurrency)")
        lines.append("6 · AfA-Bemessungsgrundlage Gebäude (3−5): \(property.buildingValue.asCurrency)")
        chapters.append(Chapter(title: "AfA-Herleitung – Ergebnis und Anschaffungskosten", introLines: [], summaryLines: lines, columnHeaders: [], rows: []))

        // 2 · AfA-Satz und Nutzungsdauer – drei Fälle sauber unterschieden, siehe Property.afaRateSource.
        var rateLines: [String] = []
        rateLines.append("Angewandter Satz: \(property.afaRatePercent.asPercent) (\(property.afaRateSource.label), \(property.afaRateSource.legalBasis))")
        rateLines.append("")
        let typisiertMarker = property.afaRateSource == .typisiert ? "  ← angewandt" : ""
        rateLines.append("1) Typisiert nach Baujahr: \(property.defaultAfaRatePercent.asPercent)\(typisiertMarker)")
        if let appraisal = property.latestRemainingUsefulLifeAppraisal {
            let appraisalMarker = property.afaRateSource == .appraisal ? "  ← angewandt" : ""
            rateLines.append("2) Restnutzungsdauergutachten vom \(appraisal.valuationDate.asShortDate): RND \(Int(appraisal.remainingUsefulLifeYears.rounded())) Jahre → Satz \(appraisal.suggestedAfaRatePercent.asPercent)\(appraisalMarker)")
        } else {
            rateLines.append("2) Restnutzungsdauergutachten: nicht erfasst")
        }
        if let override = property.afaRatePercentOverride {
            rateLines.append("3) Manuell festgelegter Satz: \(override.asPercent)  ← angewandt")
        } else {
            rateLines.append("3) Manuell festgelegter Satz: nicht gesetzt")
        }
        if property.afaRatePercentOverride != nil, property.latestRemainingUsefulLifeAppraisal != nil {
            rateLines.append("Hinweis: Ein Gutachten liegt vor, angewandt wird jedoch der manuell festgelegte Satz – bitte prüfen, ob das weiterhin gewollt ist.")
        }
        chapters.append(Chapter(title: "AfA-Herleitung – AfA-Satz und Nutzungsdauer", introLines: [], summaryLines: rateLines, columnHeaders: [], rows: []))

        // 3 · Jahresreihe Gebäude – historisch/aktuell/Prognose unterschieden.
        if let purchaseDate = property.purchaseDate {
            let startYear = Calendar.current.component(.year, from: purchaseDate)
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

        // 4 · Bewegliche Wirtschaftsgüter – im selben Bericht, aber als eigene Tabelle (keine Vermischung der Methoden).
        let assets = property.depreciableAssets ?? []
        if !assets.isEmpty {
            let assetRows = assets.sorted { $0.placedInServiceDate < $1.placedInServiceDate }.map { asset -> [String] in
                let cumulative = asset.cumulativeDepreciation(uptoYear: taxYear)
                let remaining = asset.remainingDepreciationBookValue(afterYear: taxYear)
                return [
                    asset.name,
                    asset.placedInServiceDate.asShortDate,
                    asset.depreciationBasis.asCurrency,
                    asset.isImmediatelyDeductible ? "Sofortabzug (GWG)" : "\(asset.usefulLifeYears) Jahre",
                    asset.depreciation(forYear: taxYear).asCurrency,
                    cumulative.asCurrency,
                    remaining.asCurrency,
                    belegLabel(asset.documents)
                ]
            }
            chapters.append(Chapter(
                title: "AfA-Herleitung – Bewegliche Wirtschaftsgüter",
                introLines: [],
                summaryLines: [],
                columnHeaders: ["Bezeichnung", "Anschaffung", "AK/Zeitwert", "Methode", "AfA \(String(taxYear))", "Bisherige AfA", "Restwert", "Beleg"],
                rows: assetRows
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
        resultLines.append("Rechnerisch: \(thresholdCase.includedNetTotal.asCurrency) von \(thresholdCase.thresholdAmount.asCurrency)\(percentText)")
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
            rows: [],
            progressFraction: thresholdCase.utilizationPercent.map { $0 / 100 },
            progressTone: toneForThresholdCaseStatus(thresholdCase.status)
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

        return chapters
    }

    // MARK: - Kapitel: Erhaltungsaufwand und Herstellungskosten

    private static func buildMaintenanceChapter(property: Property, taxYear: Int) -> Chapter? {
        let items = property.allExpenses(forYear: taxYear).filter { $0.taxTreatment == .maintenanceExpense || $0.taxTreatment == .capitalized }
        guard !items.isEmpty else { return nil }
        let rows = items.sorted { $0.date < $1.date }.map { expense -> [String] in
            [expense.date.asShortDate, expense.title, expense.amount.asCurrency, expense.taxTreatment == .capitalized ? "Herstellungskosten" : "Erhaltungsaufwand", belegLabel(expense.documents)]
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
        var rows = property.allExpenses(forYear: taxYear)
            .filter { $0.taxTreatment == .otherDeductible }
            .sorted { $0.date < $1.date }
            .map { expense -> [String] in
                [expense.date.asShortDate, expense.title, expense.category.label, expense.amount.asCurrency, belegLabel(expense.documents)]
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
            introLines.append("Hinweis: Die 210-Tage-/1.260-€-Grenze der Homeoffice-Pauschale gilt pro Person über alle Immobilien hinweg und wurde hier bereits anteilig gedeckelt.")
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
        let coldRent = property.annualColdRent(forYear: taxYear)
        let werbungskosten = property.werbungskosten(forYear: taxYear)
        let afaTotal = property.totalAfa(forYear: taxYear)
        guard coldRent != 0 || werbungskosten != 0 || afaTotal != 0 else { return nil }

        let afaBuilding = property.buildingAfA(forYear: taxYear)
        let afaAssets = property.assetDepreciation(forYear: taxYear)
        let travel = property.travelExpenseTotal(forYear: taxYear)
        let homeOffice = property.homeOfficeAllowance(forYear: taxYear)
        let interest = property.loanBreakdown(forYear: taxYear)?.interest ?? 0
        let maintenance = property.maintenanceExpenses(forYear: taxYear)
        let otherWK = property.otherDeductibleExpenses(forYear: taxYear)

        let totalIncome = coldRent
        let totalExpenses = afaBuilding + afaAssets + travel + homeOffice + interest + maintenance + otherWK
        let result = totalIncome - totalExpenses

        let rows: [[String]] = [
            ["##EINNAHMEN", ""],
            ["Kaltmiete / Grundmiete", coldRent.asCurrency],
            ["**Summe Einnahmen", totalIncome.asCurrency],
            ["##WERBUNGSKOSTEN", ""],
            ["AfA Gebäude", afaBuilding.asCurrency],
            ["AfA bewegliche Wirtschaftsgüter (Einrichtung)", afaAssets.asCurrency],
            ["Fahrtkosten", travel.asCurrency],
            ["Homeoffice-Pauschale", homeOffice.asCurrency],
            ["Schuldzinsen", interest.asCurrency],
            ["Erhaltungsaufwand/Instandhaltung", maintenance.asCurrency],
            ["Sonstige Werbungskosten", otherWK.asCurrency],
            ["**Summe Werbungskosten", totalExpenses.asCurrency],
            ["##ERGEBNIS", ""],
            ["**Einkünfte aus Vermietung und Verpachtung", result.asCurrency]
        ]

        return Chapter(
            title: "Anlage V – Einnahmen und Werbungskosten",
            introLines: ["Einkünfte aus Vermietung und Verpachtung, Steuerjahr \(String(taxYear)). Tilgungsanteile sind keine Werbungskosten und daher nicht enthalten."],
            summaryLines: [],
            columnHeaders: ["Position", "Betrag"],
            rows: rows
        )
    }

    // MARK: - Kapitel: Belegverzeichnis

    private static func buildDocumentsChapter(property: Property, taxYear: Int) -> Chapter? {
        let allDocuments = (try? property.modelContext?.fetch(FetchDescriptor<Document>())) ?? []
        let documents = allDocuments
            .filter { $0.resolvedProperty?.persistentModelID == property.persistentModelID }
            .filter { Calendar.current.component(.year, from: $0.receiptDate) == taxYear }
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

// MARK: - Seiten

private struct TaxPDFHeader: View {
    let propertyLabel: String
    let kind: TaxReportKind

    var body: some View {
        HStack {
            Text(propertyLabel)
            Spacer()
            Text(kind.taxYear.map { "Steuerjahr \(String($0))" } ?? "Erstanlage")
        }
        .font(.system(size: 8.5))
        .foregroundStyle(.secondary)
    }
}

private struct TaxPDFFooter: View {
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        HStack {
            Spacer()
            Text("Seite \(pageNumber) von \(totalPages)")
            Spacer()
        }
        .font(.system(size: 8))
        .foregroundStyle(.secondary)
    }
}

private struct TaxPDFCoverPage: View {
    let property: Property
    let kind: TaxReportKind
    let generatedAt: Date
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 60)
            Text("Steuerliche Unterlagen")
                .font(.system(size: 26, weight: .bold))
            Text("Private Vermietung und Verpachtung · Anlage V · \(kind.documentTitle)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Rectangle().fill(Color.black).frame(height: 1).padding(.top, 20)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Immobilie").fontWeight(.semibold)
                    Text(property.name.isEmpty ? property.address : property.name)
                }
                GridRow {
                    Text("Adresse").fontWeight(.semibold)
                    Text(property.address)
                }
                if let taxYear = kind.taxYear {
                    GridRow {
                        Text("Steuerjahr").fontWeight(.semibold)
                        Text(String(taxYear))
                    }
                }
                GridRow {
                    Text("Erstellt am").fontWeight(.semibold)
                    Text(generatedAt.asShortDate)
                }
            }
            .font(.system(size: 12))
            .padding(.top, 28)

            Spacer()

            Text("Diese Zusammenstellung ist eine Arbeits- und Nachweisunterlage auf Basis der in der App erfassten Daten. Sie ist keine amtliche Steuererklärung und stellt keine behördliche Anerkennung der enthaltenen Beträge oder steuerlichen Einordnungen dar.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            TaxPDFFooter(pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
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
                .font(.system(size: 19, weight: .bold))
                .padding(.top, 10)
            Rectangle().fill(Color.black).frame(height: 1).padding(.top, 10)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text("\(index + 1). \(entry.title)")
                        Spacer()
                        Text(String(entry.page))
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.top, 20)

            Spacer(minLength: 0)
            TaxPDFFooter(pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

private struct TaxPDFChapterPage: View {
    let propertyLabel: String
    let kind: TaxReportKind
    let title: String
    let introLines: [String]
    let summaryLines: [String]
    var progressFraction: Double? = nil
    var progressTone: Theme.StatusTone = .neutral
    let columnHeaders: [String]
    let rows: [[String]]
    let pageNumber: Int
    let totalPages: Int

    /// Zerlegt eine Zelle in Anzeigetext + optionalen Farbton anhand des „§tone§…“-Präfixes
    /// (siehe `TaxReportPDFBuilder.tonedCell`).
    private func parsedCell(_ cell: String) -> (text: String, tone: Theme.StatusTone?) {
        if cell.hasPrefix("§good§") { return (String(cell.dropFirst(6)), .good) }
        if cell.hasPrefix("§warn§") { return (String(cell.dropFirst(6)), .warning) }
        if cell.hasPrefix("§bad§") { return (String(cell.dropFirst(5)), .critical) }
        return (cell, nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaxPDFHeader(propertyLabel: propertyLabel, kind: kind)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 10)
            Rectangle().fill(Color.black).frame(height: 1).padding(.top, 8)

            if !introLines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(introLines, id: \.self) { line in
                        Text(line).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }

            if !summaryLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summaryLines, id: \.self) { line in
                        Text(line).font(.system(size: 11))
                    }
                }
                .padding(.top, 10)
            }

            if let progressFraction {
                UtilizationBar(fraction: progressFraction, tone: progressTone, height: 10)
                    .padding(.top, 10)
            }

            if !columnHeaders.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        ForEach(columnHeaders, id: \.self) { header in
                            Text(header).fontWeight(.semibold)
                        }
                    }
                    GridRow { Divider().gridCellColumns(max(columnHeaders.count, 1)) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        let isSection = row.first?.hasPrefix("##") == true
                        let isEmphasized = row.first?.hasPrefix("**") == true
                        let displayRow = row.map { cell -> String in
                            if cell.hasPrefix("##") { return String(cell.dropFirst(2)) }
                            if cell.hasPrefix("**") { return String(cell.dropFirst(2)) }
                            return cell
                        }
                        GridRow {
                            ForEach(Array(displayRow.enumerated()), id: \.offset) { _, cell in
                                let parsed = parsedCell(cell)
                                Text(parsed.text)
                                    .fontWeight(isSection || isEmphasized ? .bold : .regular)
                                    .foregroundStyle(parsed.tone?.color ?? .primary)
                            }
                        }
                    }
                }
                .font(.system(size: 9))
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
            TaxPDFFooter(pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}
