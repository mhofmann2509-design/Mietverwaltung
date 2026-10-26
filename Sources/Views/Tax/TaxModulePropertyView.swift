import SwiftUI
import SwiftData
import Charts
import QuickLook

/// Detailbereiche der Objekt-Steueransicht – als Chip-Leiste statt einer langen, gleichrangigen
/// Abschnittsliste, siehe Design-Analyse Abschnitt 6.2.
private enum TaxDetailTab: String, CaseIterable, Identifiable {
    case afa, threshold, werbungskosten, einnahmen, checkliste, belege

    var id: String { rawValue }

    var label: String {
        switch self {
        case .afa: return "AfA"
        case .threshold: return "15-%-Grenze"
        case .werbungskosten: return "Werbungskosten"
        case .einnahmen: return "Einnahmen"
        case .checkliste: return "Checkliste"
        case .belege: return "Belege"
        }
    }
}

/// Steuer-Cockpit einer einzelnen Immobilie: Ergebniskachel mit Diagramm, offene Punkte mit
/// Direktverknüpfung, und die Detailbereiche (AfA, 15-%-Grenze, Werbungskosten, Einnahmen,
/// Checkliste, Belege) als fokussierbare Tabs statt einer langen Section-Liste.
struct TaxModulePropertyView: View {
    @Bindable var property: Property
    @Environment(\.modelContext) private var context

    @State private var selectedYear: Int
    @State private var selectedTab: TaxDetailTab = .afa
    @State private var pdfPreviewURL: URL?
    @State private var pdfWarnings: [String] = []
    @State private var afaHerleitungExpanded = false
    @State private var ongoingChecklistExpanded = true
    @State private var homeOfficeEntry: HomeOfficeEntry?

    init(property: Property, initialYear: Int? = nil) {
        self.property = property
        _selectedYear = State(initialValue: initialYear ?? Calendar.current.component(.year, from: .now))
    }

    private var availableYears: [Int] { property.availableTaxYears }

    // MARK: - Abgeleitete Werte für Kopf-/Ergebnisbereich

    private var coldRent: Double { property.annualColdRent(forYear: selectedYear) }
    private var werbungskosten: Double { property.werbungskosten(forYear: selectedYear) }
    private var afa: Double { property.totalAfa(forYear: selectedYear) }
    private var result: Double { property.estimatedTaxableResult(forYear: selectedYear) }

    private var checklistOpenItems: [TaxChecklistItem] {
        (property.taxChecklistItems ?? []).filter {
            ($0.mode == .initialSetup || $0.taxYear == selectedYear) && $0.status != .done && $0.status != .notApplicable
        }
    }

    private var expensesWithoutDocument: [Expense] {
        property.allExpenses(forYear: selectedYear).filter { ($0.documents ?? []).isEmpty }
    }

    private var thresholdOpenCount: Int {
        guard let thresholdCase = property.thresholdCase else { return 0 }
        return thresholdCase.unclassifiedCount + thresholdCase.missingNetAmountExpenses.count
    }

    private var totalOpenCount: Int {
        checklistOpenItems.count + thresholdOpenCount + expensesWithoutDocument.count + (property.thresholdCase == nil && property.thresholdPeriodStartDate != nil ? 1 : 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                headerSection
                resultHeroSection
                if totalOpenCount > 0 {
                    openItemsSection
                }
                TabChipPicker(selection: $selectedTab) { $0.label }
                tabContent
                pdfSection
            }
            .padding()
        }
        .navigationTitle(property.name.isEmpty ? property.address : property.name)
        .onAppear {
            TaxChecklistSeeder.ensureSeeded(for: property, taxYear: selectedYear, context: context)
            ensureHomeOfficeEntry()
        }
        .onChange(of: selectedYear) { _, newYear in
            TaxChecklistSeeder.ensureSeeded(for: property, taxYear: newYear, context: context)
            ensureHomeOfficeEntry()
        }
        .quickLookPreview($pdfPreviewURL)
    }

    // MARK: - Kopfbereich

    private var headerSection: some View {
        HStack {
            Picker("Steuerjahr", selection: $selectedYear) {
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Spacer()

            if totalOpenCount == 0 {
                StatusBadge(label: "Keine offenen Punkte erkannt", tone: .good)
            } else {
                StatusBadge(label: "\(totalOpenCount) offene\(totalOpenCount == 1 ? "r" : "") Punkt\(totalOpenCount == 1 ? "" : "e")", tone: .warning)
            }
        }
    }

    // MARK: - Ergebniskachel

    private var resultHeroSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Steuerübersicht \(String(selectedYear))")
                .font(Theme.sectionTitleFont)

            HeroResultTile(
                title: result >= 0 ? "Einkünfte aus Vermietung und Verpachtung (Überschuss)" : "Einkünfte aus Vermietung und Verpachtung (Verlust)",
                value: abs(result).asCurrency,
                tone: result >= 0 ? .good : .warning
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                KPITile(title: "Mieteinnahmen", value: coldRent.asCurrency, systemImage: "eurosign.circle")
                KPITile(title: "Werbungskosten", value: werbungskosten.asCurrency, systemImage: "minus.circle")
                KPITile(title: "AfA gesamt", value: afa.asCurrency, systemImage: "chart.line.downtrend.xyaxis")
            }

            if coldRent != 0 || werbungskosten != 0 || afa != 0 {
                Theme.card {
                    Chart {
                        BarMark(x: .value("Position", "Einnahmen"), y: .value("Betrag", coldRent))
                            .foregroundStyle(Theme.statusGood)
                        BarMark(x: .value("Position", "Werbungskosten"), y: .value("Betrag", werbungskosten))
                            .foregroundStyle(Theme.statusWarning)
                        BarMark(x: .value("Position", "AfA"), y: .value("Betrag", afa))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    // MARK: - Offene Punkte

    private var openItemsSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Offene Punkte")
                .font(Theme.sectionTitleFont)
            Theme.card {
                VStack(spacing: 0) {
                    if property.thresholdCase == nil, property.thresholdPeriodStartDate != nil {
                        openItemButton(title: "15-%-Grenze", detail: "Dreijahresüberwachung noch nicht angelegt", tab: .threshold)
                    } else if thresholdOpenCount > 0 {
                        openItemButton(title: "15-%-Grenze", detail: "\(thresholdOpenCount) Position(en) noch nicht klassifiziert oder ohne Netto-Betrag", tab: .threshold)
                    }
                    if !checklistOpenItems.isEmpty {
                        if property.thresholdCase != nil || thresholdOpenCount > 0 { Divider() }
                        openItemButton(title: "Checkliste", detail: "\(checklistOpenItems.count) von \((property.taxChecklistItems ?? []).filter { $0.mode == .initialSetup || $0.taxYear == selectedYear }.count) Punkten offen", tab: .checkliste)
                    }
                    if !expensesWithoutDocument.isEmpty {
                        if !checklistOpenItems.isEmpty || property.thresholdCase != nil || thresholdOpenCount > 0 { Divider() }
                        openItemButton(title: "Belege", detail: "\(expensesWithoutDocument.count) Ausgabe(n) ohne zugeordneten Beleg", tab: .belege)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func openItemButton(title: String, detail: String, tab: TaxDetailTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            OpenItemRow(title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Tab-Inhalte

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .afa: afaTabContent
        case .threshold: thresholdTabContent
        case .werbungskosten: werbungskostenTabContent
        case .einnahmen: einnahmenTabContent
        case .checkliste: checklisteTabContent
        case .belege: belegeTabContent
        }
    }

    private var afaTabContent: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                LabeledContent("Gebäude-AfA \(String(selectedYear))", value: property.buildingAfA(forYear: selectedYear).asCurrency)
                    .fontWeight(.semibold)
                LabeledContent("AfA-Bemessungsgrundlage Gebäude", value: property.buildingValue.asCurrency)
                LabeledContent("Maßgeblicher AfA-Satz", value: "\(property.afaRatePercent.asPercent) (\(property.afaRateSource.label))")
                LabeledContent("Bisherige AfA (seit Anschaffung)", value: property.cumulativeBuildingAfA(uptoYear: selectedYear).asCurrency)
                LabeledContent("Restbuchwert Gebäude", value: property.remainingBuildingBookValue(afterYear: selectedYear).asCurrency)

                DisclosureGroup("Herleitung anzeigen", isExpanded: $afaHerleitungExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        afaHerleitungRow("Kaufpreis gesamt", property.purchasePrice.asCurrency)
                        if property.purchaseAncillaryCosts > 0 {
                            afaHerleitungRow("+ Anschaffungsnebenkosten", property.purchaseAncillaryCosts.asCurrency)
                        }
                        afaHerleitungRow("= Anschaffungskosten gesamt", property.totalAcquisitionCost.asCurrency, emphasized: true)
                        afaHerleitungRow("Grund-und-Boden-Anteil", (property.landValuePercentage * 100).asPercent)
                        afaHerleitungRow("− Grund und Boden (anteilig inkl. Nebenkosten)", property.apportionedLandValue.asCurrency)
                        afaHerleitungRow("= AfA-Bemessungsgrundlage Gebäude", property.buildingValue.asCurrency, emphasized: true)
                        afaHerleitungRow("× AfA-Satz (\(property.afaRateSource.label))", property.afaRatePercent.asPercent)
                        afaHerleitungRow("= Jährliche Gebäude-AfA (volles Jahr)", property.annualBuildingAfA.asCurrency, emphasized: true)
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }

                if let purchaseDate = property.purchaseDate {
                    LabeledContent("Anschaffung", value: purchaseDate.asShortDate)
                }
                LabeledContent("Wirtschaftsgüter (Möbel etc.) \(String(selectedYear))", value: property.assetDepreciation(forYear: selectedYear).asCurrency)
                if !(property.depreciableAssets ?? []).isEmpty {
                    NavigationLink("Möbelverzeichnis") {
                        MoeblierungListView(property: property)
                    }
                }
                NavigationLink("Restnutzungsdauergutachten verwalten") {
                    RemainingUsefulLifeAppraisalListView(property: property)
                }
                Button("AfA-Bericht öffnen") {
                    generateStandaloneAfaReport()
                }
            }
        }
    }

    @ViewBuilder
    private func afaHerleitungRow(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .fontWeight(emphasized ? .semibold : .regular)
        .foregroundStyle(emphasized ? .primary : .secondary)
    }

    private var thresholdTabContent: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if let thresholdCase = property.thresholdCase {
                    if let percent = thresholdCase.utilizationPercent {
                        UtilizationBar(fraction: percent / 100, tone: thresholdStatusTone(thresholdCase.status))
                        Text("\(thresholdCase.includedNetTotal.asCurrency) von \(thresholdCase.thresholdAmount.asCurrency) (\(percent.asPercent))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        ThresholdCaseDetailView(thresholdCase: thresholdCase)
                    } label: {
                        StatusBadge(label: thresholdCase.status.label, tone: thresholdStatusTone(thresholdCase.status))
                    }
                    Button("15-%-Bericht öffnen") {
                        generateStandaloneThresholdReport()
                    }
                } else if let start = property.thresholdPeriodStartDate {
                    Button("Dreijahresüberwachung anlegen") {
                        createThresholdCase(start: start)
                    }
                    Text("Zeitraum: \(start.asShortDate) – \(threeYearsLater(start).asShortDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kaufdatum oder wirtschaftlicher Übergang fehlt – die Dreijahresüberwachung kann noch nicht angelegt werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var werbungskostenTabContent: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                LabeledContent("Erhaltungsaufwand", value: property.maintenanceExpenses(forYear: selectedYear).asCurrency)
                LabeledContent("Sonstige Werbungskosten", value: property.otherDeductibleExpenses(forYear: selectedYear).asCurrency)
                LabeledContent("Herstellungskosten (aktiviert)", value: property.capitalizedExpenses(forYear: selectedYear).asCurrency)
                if let breakdown = property.loanBreakdown(forYear: selectedYear) {
                    LabeledContent("Schuldzinsen", value: breakdown.interest.asCurrency)
                    LabeledContent("Tilgung (nicht abziehbar)", value: breakdown.principal.asCurrency)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Fahrtkosten", value: property.travelExpenseTotal(forYear: selectedYear).asCurrency)
                NavigationLink("Fahrtkosten verwalten") {
                    TravelExpenseListView(property: property)
                }

                if let homeOfficeEntry {
                    HomeOfficeStepperRow(entry: homeOfficeEntry)
                }
                LabeledContent("Homeoffice-Pauschale (anteilig)", value: property.homeOfficeAllowance(forYear: selectedYear).asCurrency)
                if HomeOfficeAllocation.isCapExceeded(for: property, taxYear: selectedYear) {
                    Text("210-Tage-/1.260-€-Grenze über alle Immobilien hinweg erreicht – Pauschale bereits anteilig gedeckelt.")
                        .font(.caption)
                        .foregroundStyle(Theme.statusWarning)
                }
            }
        }
    }

    private var einnahmenTabContent: some View {
        Theme.card {
            LabeledContent("Kaltmiete", value: coldRent.asCurrency)
        }
    }

    private var checklisteTabContent: some View {
        let initialItems = (property.taxChecklistItems ?? []).filter { $0.mode == .initialSetup }.sorted { $0.createdAt < $1.createdAt }
        let ongoingItems = (property.taxChecklistItems ?? []).filter { $0.mode == .ongoing && $0.taxYear == selectedYear }.sorted { $0.createdAt < $1.createdAt }

        return Theme.card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if !initialItems.isEmpty {
                    DisclosureGroup("Erstanlage") {
                        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                            ForEach(initialItems) { item in
                                TaxChecklistRow(item: item)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                if !ongoingItems.isEmpty {
                    DisclosureGroup("Laufender Betrieb \(String(selectedYear))", isExpanded: $ongoingChecklistExpanded) {
                        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                            ForEach(ongoingItems) { item in
                                TaxChecklistRow(item: item)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                if initialItems.isEmpty && ongoingItems.isEmpty {
                    Text("Keine Checklisten-Einträge vorhanden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var belegeTabContent: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                NavigationLink("Belegübersicht") {
                    DocumentListView(property: property)
                }
                if !expensesWithoutDocument.isEmpty {
                    Text("Ausgaben ohne Beleg (\(String(selectedYear)))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(expensesWithoutDocument) { expense in
                        HStack {
                            Text(expense.title.isEmpty ? expense.category.label : expense.title)
                            Spacer()
                            Text(expense.amount.asCurrency)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - K. PDF

    private var pdfSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Steuerreports")
                .font(Theme.sectionTitleFont)
            Theme.card {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    Button("Erstanlage-PDF erstellen") {
                        generatePDF(kind: .initialSetup)
                    }
                    Button("Laufender-Betrieb-PDF erstellen (\(String(selectedYear)))") {
                        generatePDF(kind: .ongoing(taxYear: selectedYear))
                    }
                    if !pdfWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hinweise zum zuletzt erstellten PDF:")
                                .font(.caption.weight(.semibold))
                            ForEach(pdfWarnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(Theme.statusWarning)
                            }
                        }
                    }
                    if let pdfPreviewURL {
                        ShareLink("Zuletzt erstelltes PDF teilen", item: pdfPreviewURL)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func thresholdStatusTone(_ status: ThresholdCaseStatus) -> Theme.StatusTone {
        switch status {
        case .belowThreshold, .completed: return .good
        case .thresholdReached: return .warning
        case .exceeded: return .critical
        case .notConclusivelyCheckable: return .neutral
        }
    }

    private func threeYearsLater(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .year, value: 3, to: date) ?? date
    }

    private func createThresholdCase(start: Date) {
        let thresholdCase = ThreeYearThresholdCase(periodStart: start, periodEnd: threeYearsLater(start))
        thresholdCase.property = property
        context.insert(thresholdCase)
        thresholdCase.ensureAssessments(context: context)
    }

    private func generatePDF(kind: TaxReportKind) {
        let (url, warnings) = TaxReportPDFBuilder.build(property: property, kind: kind)
        pdfPreviewURL = url
        pdfWarnings = warnings
    }

    private func generateStandaloneThresholdReport() {
        let (url, warnings) = TaxReportPDFBuilder.buildStandaloneThresholdReport(property: property)
        pdfPreviewURL = url
        pdfWarnings = warnings
    }

    private func generateStandaloneAfaReport() {
        let (url, warnings) = TaxReportPDFBuilder.buildStandaloneAfaReport(property: property, taxYear: selectedYear)
        pdfPreviewURL = url
        pdfWarnings = warnings
    }

    /// Stellt sicher, dass für die aktuelle Immobilie und das ausgewählte Steuerjahr ein
    /// `HomeOfficeEntry` existiert (ein Eintrag je Immobilie/Jahr), ohne vorhandene Tage zu
    /// verändern.
    private func ensureHomeOfficeEntry() {
        if let existing = (property.homeOfficeEntries ?? []).first(where: { $0.taxYear == selectedYear }) {
            homeOfficeEntry = existing
        } else {
            let entry = HomeOfficeEntry(taxYear: selectedYear)
            entry.property = property
            context.insert(entry)
            homeOfficeEntry = entry
        }
    }
}

private struct TaxChecklistRow: View {
    @Bindable var item: TaxChecklistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Status", selection: Binding(
                    get: { item.status },
                    set: { item.status = $0 }
                )) {
                    ForEach(TaxChecklistStatus.allCases) { status in
                        Label(status.label, systemImage: status.systemImage).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text(item.title)
                    .font(.subheadline)
            }
            if !item.itemDescription.isEmpty {
                Text(item.itemDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Kommentar / offene Rückfrage", text: $item.comment, axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 2)
    }
}

private struct HomeOfficeStepperRow: View {
    @Bindable var entry: HomeOfficeEntry

    var body: some View {
        Stepper(value: Binding(
            get: { entry.days },
            set: { entry.days = max(0, $0) }
        ), in: 0...366) {
            LabeledContent("Homeoffice-Tage (dieses Objekt)", value: String(entry.days))
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    return NavigationStack {
        TaxModulePropertyView(property: property)
    }
    .modelContainer(PreviewData.container)
}
