import SwiftUI
import SwiftData
import PDFKit

/// Welcher der beiden getrennten Steuerreports erzeugt werden soll (siehe Auftrag Abschnitt 3,
/// Modus A/B): die einmalige Erstanlage (Objekt-/Anschaffungsdaten, AfA-Herleitung, 15-%-Grenze,
/// Möbelverzeichnis) oder der laufende Betrieb eines bestimmten Steuerjahres (Anlage V,
/// AfA-Herleitung, Erhaltungsaufwand/sonstige Werbungskosten, Belegverzeichnis). Beide Reports
/// sind reine PDF-Unterlagen fürs Finanzamt und enthalten bewusst keine Checkliste – die
/// Vorbereitungs-Checkliste ist ein reines Bildschirm-Werkzeug in TaxModulePropertyView.
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
        /// Optionaler zweiter Balken direkt unter dem ersten – zeigt z.B. den Stand inklusive noch
        /// ungeklärter Positionen, damit „bekannter" und „möglicher zusätzlicher" Betrag sichtbar
        /// getrennt bleiben, statt eine Sicherheit vorzutäuschen, die von offenen Punkten abhängt.
        var secondaryProgressFraction: Double? = nil
        var secondaryProgressLabel: String? = nil

        var pageCount: Int { max(1, Int(ceil(Double(rows.count) / Double(maxRowsPerPage)))) }

        func rowsForPage(_ pageIndex: Int) -> [[String]] {
            let start = pageIndex * maxRowsPerPage
            guard start < rows.count else { return [] }
            return Array(rows[start..<min(start + maxRowsPerPage, rows.count)])
        }

        /// Laufende Nummer, mit der die erste normale (nicht „##“-/„**“-markierte) Zeile auf dieser
        /// Seite beginnt – für die Vorlage „Formular-Raster“, deren Nr.-Spalte über Seitenumbrüche
        /// hinweg weiterzählt statt auf jeder Fortsetzungsseite wieder bei 1 zu beginnen.
        func startingRowNumber(forPage pageIndex: Int) -> Int {
            let start = min(pageIndex * maxRowsPerPage, rows.count)
            let precedingNormalRows = rows.prefix(start).filter {
                let first = $0.first ?? ""
                return !first.hasPrefix("##") && !first.hasPrefix("**")
            }
            return precedingNormalRows.count + 1
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
            addAll(buildAfaChapters(property: property, taxYear: taxYear), otherwiseWarn: "AfA-Herleitung")
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
                        secondaryProgressFraction: pageIndex == 0 ? chapter.secondaryProgressFraction : nil,
                        secondaryProgressLabel: chapter.secondaryProgressLabel,
                        columnHeaders: chapter.columnHeaders,
                        rows: rowsForPage,
                        startingRowNumber: chapter.startingRowNumber(forPage: pageIndex),
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
            chapters.append(Chapter(
                title: "AfA-Herleitung – Bewegliche Wirtschaftsgüter",
                introLines: [],
                summaryLines: [],
                columnHeaders: ["Bezeichnung", "Anschaffung", "AK/Zeitwert", "Methode", "AfA \(String(taxYear))", "Bisherige AfA", "Restwert", "Beleg"],
                rows: assetRows
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
                introLines: ["Nachträglich als Herstellungskosten aktivierte Positionen werden als eigenes Wirtschaftsgut mit dem Gebäude-AfA-Satz abgeschrieben (siehe Tabelle „Bewegliche Wirtschaftsgüter“) und erhöhen die Bemessungsgrundlage erst ab dem genannten Wirksamkeitsjahr – frühere Jahre bleiben unverändert."],
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

        let secondaryFraction: Double? = thresholdCase.possibleAdditionalAmount > 0 && thresholdCase.thresholdAmount > 0
            ? (thresholdCase.includedNetTotal + thresholdCase.possibleAdditionalAmount) / thresholdCase.thresholdAmount
            : nil
        chapters.append(Chapter(
            title: "15-%-Grenze – Ergebnisübersicht",
            introLines: [],
            summaryLines: resultLines,
            columnHeaders: [],
            rows: [],
            progressFraction: thresholdCase.utilizationPercent.map { $0 / 100 },
            progressTone: toneForThresholdCaseStatus(thresholdCase.status),
            secondaryProgressFraction: secondaryFraction,
            secondaryProgressLabel: secondaryFraction != nil ? "Inkl. ungeklärter Positionen (heller): bis zu \((thresholdCase.includedNetTotal + thresholdCase.possibleAdditionalAmount).asCurrency)" : nil
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

// MARK: - Seiten

/// Gedeckte Akzentfarbe für die Vorlage „Ergebnis zuerst" – bewusst nicht die App-Akzentfarbe
/// (`Theme.accent`), da PDFs fürs Finanzamt unabhängig vom App-weiten Erscheinungsbild eine eigene,
/// gleichbleibend seriöse Dokumentoptik behalten (siehe `TaxReportLayoutStyle`).
private let taxReportAccent = Color(red: 0.227, green: 0.353, blue: 0.420)

/// Grobe Heuristik, ob eine Zellen-Zeichenkette ein Betrag/Prozentwert ist (endet auf „€"/„%" oder
/// besteht nur aus Ziffern/Zahlformat-Zeichen) – steuert Rechtsbündigkeit/Zifferfont in beiden
/// Layout-Vorlagen, ohne sich auf Spaltenüberschriften verlassen zu müssen (die je Kapitel stark
/// variieren, von „Betrag" bis „Bemessungsgrdl." oder „Restbuchwert").
private func isNumericLikeCell(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return false }
    if trimmed.hasSuffix("€") || trimmed.hasSuffix("%") { return true }
    return trimmed.allSatisfy { $0.isNumber || ",.-".contains($0) }
}

/// Zerlegt eine Zelle in Anzeigetext + optionalen Farbton anhand des „§tone§…"-Präfixes (siehe
/// `TaxReportPDFBuilder.tonedCell`) – von beiden Kapitel-Layouts geteilt.
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

    private var layout: TaxReportLayoutStyle { TaxReportLayoutStore.shared.style }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 60)
            Text("Steuerliche Unterlagen")
                .font(.system(size: 26, weight: .bold))
            Text("Private Vermietung und Verpachtung · Anlage V · \(kind.documentTitle)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Rectangle().fill(layout == .ergebnisZuerst ? taxReportAccent : Color.black)
                .frame(height: layout == .formularraster ? 2 : 1)
                .padding(.top, 20)

            Group {
                if layout == .formularraster {
                    coverMetaGrid
                        .padding(14)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                } else {
                    coverMetaGrid
                }
            }
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

    @ViewBuilder
    private var coverMetaGrid: some View {
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
                    Text(String(taxYear)).font(.system(size: 12, design: layout == .formularraster ? .monospaced : .default))
                }
            }
            GridRow {
                Text("Erstellt am").fontWeight(.semibold)
                Text(generatedAt.asShortDate).font(.system(size: 12, design: layout == .formularraster ? .monospaced : .default))
            }
        }
        .font(.system(size: 12))
    }
}

private struct TaxPDFTOCPage: View {
    let propertyLabel: String
    let kind: TaxReportKind
    let entries: [(title: String, page: Int)]
    let pageNumber: Int
    let totalPages: Int

    private var layout: TaxReportLayoutStyle { TaxReportLayoutStore.shared.style }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaxPDFHeader(propertyLabel: propertyLabel, kind: kind)
            Text("Inhaltsverzeichnis")
                .font(.system(size: 19, weight: .bold))
                .padding(.top, 10)
            Rectangle().fill(layout == .ergebnisZuerst ? taxReportAccent : Color.black)
                .frame(height: layout == .formularraster ? 2 : 1)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text("\(index + 1). \(entry.title)")
                        Spacer()
                        Text(String(entry.page)).font(.system(size: 12, design: layout == .formularraster ? .monospaced : .default))
                    }
                    .padding(.vertical, layout == .formularraster ? 7 : 5)
                    .overlay(alignment: .bottom) {
                        if layout == .formularraster {
                            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.6)
                        }
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
    var secondaryProgressFraction: Double? = nil
    var secondaryProgressLabel: String? = nil
    let columnHeaders: [String]
    let rows: [[String]]
    var startingRowNumber: Int = 1
    let pageNumber: Int
    let totalPages: Int

    private var layout: TaxReportLayoutStyle { TaxReportLayoutStore.shared.style }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaxPDFHeader(propertyLabel: propertyLabel, kind: kind)
            switch layout {
            case .ergebnisZuerst:
                ergebnisZuerstContent
            case .formularraster:
                formularrasterContent
            }
            Spacer(minLength: 0)
            TaxPDFFooter(pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(44)
        .frame(width: TaxReportPDFBuilder.pageSize.width, height: TaxReportPDFBuilder.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    // MARK: Ergebnis zuerst

    /// Letzte „**"-markierte Zeile (der Abschluss-/Ergebniswert eines Kapitels) als (Label, Wert) –
    /// nil, wenn das Kapitel keine solche Zeile hat (reine Belegtabellen o.ä.).
    private var headline: (label: String, value: String)? {
        guard let lastTotal = rows.last(where: { $0.first?.hasPrefix("**") == true }) else { return nil }
        let label = String((lastTotal.first ?? "").dropFirst(2))
        var value = lastTotal.count > 1 ? (lastTotal.last ?? "") : ""
        if value.hasPrefix("**") { value = String(value.dropFirst(2)) }
        return (label, value)
    }

    /// Fallback-Kopfzeile für Kapitel ohne Tabelle (nur `summaryLines`, z.B. AfA-Satz-Herleitung):
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
        return copy
    }

    @ViewBuilder
    private func resultBox(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(taxReportAccent)
                .tracking(0.3)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(taxReportAccent.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(taxReportAccent, lineWidth: 1.1))
    }

    @ViewBuilder
    private func highlightedLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(taxReportAccent.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(taxReportAccent, lineWidth: 1.1))
    }

    @ViewBuilder
    private var ergebnisZuerstContent: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .padding(.top, 10)

        if !introLines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(introLines, id: \.self) { line in
                    Text(line).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }

        if let headline {
            resultBox(label: headline.label, value: headline.value).padding(.top, 16)
        } else if let fallbackHeadlineLine {
            highlightedLine(fallbackHeadlineLine).padding(.top, 16)
        }

        if !remainingSummaryLines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(remainingSummaryLines.enumerated()), id: \.offset) { _, line in
                    if line.isEmpty {
                        Color.clear.frame(height: 6)
                    } else {
                        Text(line).font(.system(size: 11))
                    }
                }
            }
            .padding(.top, 14)
        }

        if let progressFraction {
            UtilizationBar(fraction: progressFraction, tone: progressTone, height: 10)
                .padding(.top, 10)
        }
        if let secondaryProgressFraction {
            UtilizationBar(fraction: secondaryProgressFraction, tone: .neutral, height: 6)
                .padding(.top, 5)
            if let secondaryProgressLabel {
                Text(secondaryProgressLabel)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }

        if !columnHeaders.isEmpty {
            Text("HERLEITUNG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(taxReportAccent)
                .tracking(0.8)
                .padding(.top, 20)
            ergebnisZuerstTable
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var ergebnisZuerstTable: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(columnHeaders.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(taxReportAccent)
                }
            }
            GridRow {
                Rectangle().fill(taxReportAccent).frame(height: 1.4).gridCellColumns(max(columnHeaders.count, 1))
            }
            ForEach(Array(tableRowsExcludingHeadline.enumerated()), id: \.offset) { _, row in
                let isSection = row.first?.hasPrefix("##") == true
                let isEmphasized = row.first?.hasPrefix("**") == true
                let displayRow = row.map { cell -> String in
                    if cell.hasPrefix("##") { return String(cell.dropFirst(2)) }
                    if cell.hasPrefix("**") { return String(cell.dropFirst(2)) }
                    return cell
                }
                if isSection {
                    GridRow {
                        Text(displayRow.first ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(taxReportAccent)
                            .padding(.top, 6)
                            .gridCellColumns(max(columnHeaders.count, 1))
                    }
                } else {
                    GridRow {
                        ForEach(Array(displayRow.enumerated()), id: \.offset) { _, cell in
                            let parsed = parsedTaxCell(cell)
                            Text(parsed.text)
                                .font(.system(size: 10, weight: isEmphasized ? .bold : .regular, design: isNumericLikeCell(parsed.text) ? .monospaced : .default))
                                .foregroundStyle(parsed.tone?.color ?? .primary)
                        }
                    }
                }
            }
        }
        .font(.system(size: 10))
    }

    // MARK: Formular-Raster

    private enum FormularrasterRowKind { case normal, section, total }

    private var numberedRows: [(number: Int?, kind: FormularrasterRowKind, row: [String])] {
        var counter = startingRowNumber - 1
        var result: [(Int?, FormularrasterRowKind, [String])] = []
        for row in rows {
            let first = row.first ?? ""
            if first.hasPrefix("##") {
                result.append((nil, .section, row))
            } else if first.hasPrefix("**") {
                result.append((nil, .total, row))
            } else {
                counter += 1
                result.append((counter, .normal, row))
            }
        }
        return result
    }

    @ViewBuilder
    private func formularrasterCell(_ text: String, bold: Bool = false, fill: Bool = false, tone: Theme.StatusTone? = nil, isHeaderBar: Bool = false) -> some View {
        let numeric = isNumericLikeCell(text)
        Text(text)
            .font(.system(size: 9, weight: (bold || isHeaderBar) ? .bold : .regular, design: numeric ? .monospaced : .default))
            .foregroundStyle(isHeaderBar ? Color.white : (tone?.color ?? Color.black))
            .frame(maxWidth: .infinity, alignment: numeric ? .trailing : .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(isHeaderBar ? Color.black : (fill ? Color.black.opacity(0.08) : Color.clear))
            .overlay(alignment: .trailing) { Rectangle().fill(Color.black).frame(width: 0.6) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 0.6) }
    }

    @ViewBuilder
    private func formularrasterSectionBar(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Color.white)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(Color.black)
    }

    @ViewBuilder
    private var formularrasterSummaryBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(summaryLines.enumerated()), id: \.offset) { index, line in
                if line.isEmpty {
                    Color.clear.frame(height: 4)
                } else {
                    Text(line)
                        .font(.system(size: 9.5, design: isNumericLikeCell(line) ? .monospaced : .default))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            if index < summaryLines.count - 1 {
                                Rectangle().fill(Color.black.opacity(0.25)).frame(height: 0.75)
                            }
                        }
                }
            }
        }
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
    }

    @ViewBuilder
    private var formularrasterTable: some View {
        let colCount = columnHeaders.count + 1
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                formularrasterCell("Nr.", isHeaderBar: true)
                ForEach(Array(columnHeaders.enumerated()), id: \.offset) { _, header in
                    formularrasterCell(header, isHeaderBar: true)
                }
            }
            ForEach(Array(numberedRows.enumerated()), id: \.offset) { _, entry in
                switch entry.kind {
                case .section:
                    GridRow {
                        formularrasterSectionBar(entry.row.first.map { String($0.dropFirst(2)) } ?? "")
                            .gridCellColumns(colCount)
                    }
                case .total:
                    GridRow {
                        formularrasterCell("", fill: true)
                        ForEach(Array(entry.row.enumerated()), id: \.offset) { _, cell in
                            let display = cell.hasPrefix("**") ? String(cell.dropFirst(2)) : cell
                            formularrasterCell(display, bold: true, fill: true)
                        }
                    }
                case .normal:
                    GridRow {
                        formularrasterCell(entry.number.map(String.init) ?? "")
                        ForEach(Array(entry.row.enumerated()), id: \.offset) { _, cell in
                            let parsed = parsedTaxCell(cell)
                            formularrasterCell(parsed.text, tone: parsed.tone)
                        }
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
    }

    @ViewBuilder
    private var formularrasterContent: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            Spacer()
            Text(kind.taxYear.map { "STEUERJAHR \($0)" } ?? "ERSTANLAGE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
        }
        .padding(.top, 10)

        if !introLines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(introLines, id: \.self) { line in
                    Text(line).font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }

        if !summaryLines.isEmpty {
            formularrasterSummaryBox.padding(.top, 10)
        }

        if let progressFraction {
            UtilizationBar(fraction: progressFraction, tone: progressTone, height: 10)
                .padding(.top, 10)
        }
        if let secondaryProgressFraction {
            UtilizationBar(fraction: secondaryProgressFraction, tone: .neutral, height: 6)
                .padding(.top, 5)
            if let secondaryProgressLabel {
                Text(secondaryProgressLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }

        if !columnHeaders.isEmpty {
            formularrasterTable.padding(.top, 12)
        }
    }
}
