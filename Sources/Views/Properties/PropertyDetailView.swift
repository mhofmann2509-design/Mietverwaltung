import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

/// Gemeinsame Oberfläche von `UtilityCostLineItem` (Abrechnung) und `WirtschaftsplanLineItem`
/// (Wirtschaftsplan), damit beide dieselbe Anzeige-Logik in `betriebskostenSection` nutzen können.
private protocol BetriebskostenLineItemDisplayable {
    var costType: String { get }
    var amount: Double { get }
}
extension UtilityCostLineItem: BetriebskostenLineItemDisplayable {}
extension WirtschaftsplanLineItem: BetriebskostenLineItemDisplayable {}

/// Ein Eintrag im Betriebskosten-Abschnitt der Immobilie – entweder die tatsächliche Abrechnung
/// der Hausverwaltung (Ist) oder der Wirtschaftsplan (Prognose/Soll) für ein Jahr. Beide werden
/// gemeinsam, nach Jahr sortiert (Ist vor Prognose im selben Jahr), angezeigt.
private enum BetriebskostenEntry: Identifiable {
    case actual(UtilityStatement)
    case forecast(WirtschaftsplanStatement)

    var id: ObjectIdentifier {
        switch self {
        case .actual(let statement): return ObjectIdentifier(statement)
        case .forecast(let plan): return ObjectIdentifier(plan)
        }
    }

    var year: Int {
        switch self {
        case .actual(let statement): return statement.year
        case .forecast(let plan): return plan.year
        }
    }

    var sortRank: Int {
        switch self {
        case .actual: return 0
        case .forecast: return 1
        }
    }
}

/// Die drei Bereiche, in die `PropertyDetailView` aufgeteilt ist – ersetzt die frühere, durchgehend
/// gescrollte Liste aus 17 Sections durch fokussierbare Reiter (gleiche `TabChipPicker`-Bausteine
/// wie im Steuer-Objekt-Cockpit).
private enum PropertyDetailTab: String, CaseIterable, Identifiable {
    case overview, finance, betriebskosten

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Übersicht"
        case .finance: return "Finanzen"
        case .betriebskosten: return "Betriebskosten"
        }
    }
}

struct PropertyDetailView: View {
    @Bindable var property: Property
    @Environment(\.modelContext) private var modelContext
    @Query private var landlords: [Landlord]
    @Query(sort: \Document.receiptDate, order: .reverse) private var allDocuments: [Document]
    @State private var selectedDetailTab: PropertyDetailTab = .overview
    @State private var showingEditSheet = false
    @State private var showingAddUnitSheet = false
    @State private var statementToEdit: UtilityStatement?
    @State private var planToEdit: WirtschaftsplanStatement?
    @State private var selectedTaxYear = Calendar.current.component(.year, from: .now)
    @State private var showingDocumentScanImporter = false
    @State private var documentScanResult: PropertyScanResult?
    @State private var showingPurchaseContractScanImporter = false
    @State private var purchaseContractScanResult: PurchaseContractScanResult?
    @State private var documentScanErrorMessage: String?
    @State private var pdfPreviewURL: URL?

    var body: some View {
        List {
            Section("Adresse") {
                Text(property.address)
                if !property.notes.isEmpty {
                    Text(property.notes)
                        .foregroundStyle(.secondary)
                }
            }

            if property.purchasePrice > 0 || !betriebskostenEntries.isEmpty {
                Section {
                    Picker("Betrachtungsjahr", selection: $selectedTaxYear) {
                        ForEach(availableOverviewYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } footer: {
                    Text("Gilt für die Reiter „Finanzen“ und „Betriebskosten“.")
                }
            }

            TabChipPicker(selection: $selectedDetailTab) { $0.label }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            switch selectedDetailTab {
            case .overview: overviewTabSections
            case .finance: financeTabSections
            case .betriebskosten: betriebskostenTabSections
            }
        }
        .navigationTitle(property.name.isEmpty ? "Immobilie" : property.name)
        // Unit/UtilityStatement: zentral in ContentView deklariert, siehe dortiger Kommentar.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        showingDocumentScanImporter = true
                    } label: {
                        Label("Teilungserklärung scannen", systemImage: "doc.text.viewfinder")
                    }
                    Button {
                        showingPurchaseContractScanImporter = true
                    } label: {
                        Label("Kaufvertrag scannen", systemImage: "doc.text.viewfinder")
                    }
                } label: {
                    Label("Dokument scannen", systemImage: "doc.text.viewfinder")
                }
            }
        }
        .fileImporter(isPresented: $showingDocumentScanImporter, allowedContentTypes: [.image]) { result in
            handleDocumentScan(result)
        }
        .fileImporter(isPresented: $showingPurchaseContractScanImporter, allowedContentTypes: [.image]) { result in
            handlePurchaseContractScan(result)
        }
        .sheet(item: $documentScanResult) { result in
            PropertyDocumentScanReviewView(property: property, result: result)
        }
        .sheet(item: $purchaseContractScanResult) { result in
            PropertyPurchaseContractScanReviewView(property: property, result: result)
        }
        .alert("Scan fehlgeschlagen", isPresented: Binding(get: { documentScanErrorMessage != nil }, set: { if !$0 { documentScanErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(documentScanErrorMessage ?? "")
        }
        .sheet(isPresented: $showingEditSheet) {
            PropertyEditView(property: property)
        }
        .sheet(isPresented: $showingAddUnitSheet) {
            UnitEditView(property: property, unit: nil)
        }
        .sheet(item: $statementToEdit) { statement in
            UtilityStatementEditView(property: property, statement: statement)
        }
        .sheet(item: $planToEdit) { plan in
            WirtschaftsplanEditView(property: property, plan: plan)
        }
        .quickLookPreview($pdfPreviewURL)
    }

    /// Reiter „Übersicht“: Dokumente-Kurzlink, Stammdaten, Kauf & Rendite, Wohnfläche/Ausstattung,
    /// Einheiten – alles, was unabhängig vom oben gewählten Betrachtungsjahr ist.
    @ViewBuilder
    private var overviewTabSections: some View {
        Section {
            NavigationLink {
                DocumentListView(property: property)
            } label: {
                LabeledContent("Dokumente dieser Immobilie", value: String(propertyDocumentCount))
            }
        }

        if property.constructionYear != nil || property.roomCount != nil || property.totalUnitCount != nil {
            Section("Allgemeine Daten") {
                if let constructionYear = property.constructionYear {
                    LabeledContent("Baujahr", value: String(constructionYear))
                }
                if let roomCount = property.roomCount {
                    LabeledContent("Anzahl der Zimmer", value: String(roomCount))
                }
                if let totalUnitCount = property.totalUnitCount {
                    LabeledContent("Einheiten insgesamt", value: String(totalUnitCount))
                }
            }
        }

        if property.purchasePrice > 0 {
            Section("Kauf & Rendite") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                    KPITile(title: "Kaufpreis", value: property.purchasePrice.asCurrency, systemImage: "building.columns")
                    if let gross = property.grossYieldPercent {
                        KPITile(title: "Bruttorendite", value: gross.asPercent, systemImage: "chart.line.uptrend.xyaxis")
                    }
                    if let net = property.netYieldPercent {
                        KPITile(title: "Nettorendite", value: net.asPercent, systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, Theme.spacingS)

                if property.purchaseAncillaryCosts > 0 {
                    LabeledContent("Kaufnebenkosten", value: property.purchaseAncillaryCosts.asCurrency)
                }
                if let purchaseDate = property.purchaseDate {
                    LabeledContent("Kaufdatum", value: purchaseDate.asShortDate)
                }
            }
        }

        if property.totalSizeSquareMeters > 0 || !property.aggregatedFeatures.isEmpty {
            Section("Wohnfläche & Ausstattung") {
                if property.totalSizeSquareMeters > 0 {
                    LabeledContent("Gesamtwohnfläche", value: "\(property.totalSizeSquareMeters.formatted()) m²")
                }
                if !property.aggregatedFeatures.isEmpty {
                    FlowBadges(features: property.aggregatedFeatures)
                }
            }
        }

        Section("Einheiten") {
            if (property.units ?? []).isEmpty {
                Text("Noch keine Einheiten angelegt.")
                    .foregroundStyle(.secondary)
            }
            ForEach(property.units ?? []) { unit in
                NavigationLink(value: unit) {
                    VStack(alignment: .leading) {
                        Text(unit.name.isEmpty ? "Einheit" : unit.name)
                        if let tenancy = unit.activeTenancy, let tenant = tenancy.tenant {
                            Text("Vermietet an \(tenant.fullName) · \(tenancy.totalMonthlyAmount.asCurrency)/Monat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Leerstand")
                                .font(.caption)
                                .foregroundStyle(Theme.statusWarning)
                        }
                    }
                }
            }
            .onDelete(perform: deleteUnits)

            Button {
                showingAddUnitSheet = true
            } label: {
                Label("Einheit hinzufügen", systemImage: "plus")
            }
        }
    }

    /// Reiter „Finanzen“: AfA, Ausgaben nach Steuerart, Finanzierung, Cashflow – alle abhängig vom
    /// oben gewählten Betrachtungsjahr. Ohne erfasste Kaufdaten gibt es hier nichts zu zeigen.
    @ViewBuilder
    private var financeTabSections: some View {
        if property.purchasePrice > 0 {
            let result = property.estimatedTaxableResult(forYear: selectedTaxYear)
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                    KPITile(title: "AfA gesamt \(String(selectedTaxYear))", value: property.totalAfa(forYear: selectedTaxYear).asCurrency, systemImage: "chart.line.downtrend.xyaxis")
                    KPITile(
                        title: result >= 0 ? "Steuerl. Überschuss \(String(selectedTaxYear))" : "Steuerl. Verlust \(String(selectedTaxYear))",
                        value: abs(result).asCurrency,
                        systemImage: result >= 0 ? "checkmark.circle" : "exclamationmark.circle",
                        valueColor: result >= 0 ? Theme.statusGood : Theme.statusWarning
                    )
                    if let cashFlowAfterTax = freeCashFlowAfterTax(forYear: selectedTaxYear) {
                        KPITile(
                            title: "Cashflow nach Steuer \(String(selectedTaxYear))",
                            value: cashFlowAfterTax.asCurrency,
                            systemImage: cashFlowAfterTax >= 0 ? "checkmark.circle" : "exclamationmark.circle",
                            valueColor: cashFlowAfterTax >= 0 ? Theme.statusGood : Theme.statusCritical
                        )
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, Theme.spacingS)
            } header: {
                Text("Finanzen \(String(selectedTaxYear)) im Überblick")
            }

            Section {
                    if let constructionYear = property.constructionYear {
                        LabeledContent("Baujahr", value: String(constructionYear))
                    }
                    LabeledContent(
                        property.afaRatePercentOverride != nil ? "AfA-Satz (manuell festgelegt)" : "AfA-Satz (typisiert nach Baujahr)",
                        value: property.afaRatePercent.asPercent
                    )
                    LabeledContent("Gebäudewert (abschreibbar)", value: property.buildingValue.asCurrency)
                    LabeledContent("Gebäude-AfA (\(String(selectedTaxYear)))", value: property.buildingAfA(forYear: selectedTaxYear).asCurrency)

                    let depreciableAssetsForYear = (property.depreciableAssets ?? []).filter { $0.depreciation(forYear: selectedTaxYear) > 0 }
                    let assetDepreciation = property.assetDepreciation(forYear: selectedTaxYear)
                    if assetDepreciation > 0 {
                        DisclosureGroup {
                            ForEach(depreciableAssetsForYear) { asset in
                                HStack {
                                    Text(asset.name.isEmpty ? asset.category.label : asset.name)
                                    Spacer()
                                    Text(asset.depreciation(forYear: selectedTaxYear).asCurrency)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        } label: {
                            LabeledContent("+ Möbel/Herstellungskosten", value: assetDepreciation.asCurrency)
                        }
                    }
                    LabeledContent("AfA gesamt \(String(selectedTaxYear))", value: property.totalAfa(forYear: selectedTaxYear).asCurrency)
                        .font(.headline)

                    HStack {
                        Button {
                            pdfPreviewURL = gebaeudeAfaReportURL()
                        } label: {
                            Label("Als PDF anzeigen", systemImage: "doc.text.magnifyingglass")
                        }
                        Spacer()
                        Button {
                            if let url = gebaeudeAfaReportURL() {
                                saveGebaeudeAfaPDFAsDocument(url: url)
                            }
                        } label: {
                            Label("Herunterladen", systemImage: "tray.and.arrow.down")
                        }
                    }

                    NavigationLink {
                        MoeblierungListView(property: property)
                    } label: {
                        Label("Möblierung bearbeiten", systemImage: "pencil")
                    }
                    NavigationLink {
                        HerstellungskostenListView()
                    } label: {
                        Label("Herstellungskosten bearbeiten", systemImage: "pencil")
                    }
                    NavigationLink {
                        RemainingUsefulLifeAppraisalListView(property: property)
                    } label: {
                        if let latest = (property.remainingUsefulLifeAppraisals ?? []).sorted(by: { $0.createdAt > $1.createdAt }).first {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Restnutzungsdauergutachten")
                                Text("\((property.remainingUsefulLifeAppraisals ?? []).count) Gutachten · zuletzt \(Int(latest.remainingUsefulLifeYears.rounded())) Jahre RND")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Restnutzungsdauergutachten")
                        }
                    }
                } header: {
                    Text("Abschreibung (AfA)")
                } footer: {
                    Text("Gesetzlich typisierter Satz nach Baujahr (§7 Abs. 4 EStG), manuell überschreibbar in „Immobilie bearbeiten“. Möblierung und Herstellungskosten fließen zusätzlich in die Gesamt-AfA ein und lassen sich über die jeweilige Bearbeiten-Ansicht anpassen. Ersetzt keine Steuerberatung.")
                }

                Section {
                    LabeledContent("Erhaltungsaufwand", value: property.maintenanceExpenses(forYear: selectedTaxYear).asCurrency)
                    LabeledContent("Sonstige Werbungskosten", value: property.otherDeductibleExpenses(forYear: selectedTaxYear).asCurrency)
                    let capitalized = property.capitalizedExpenses(forYear: selectedTaxYear)
                    if capitalized > 0 {
                        LabeledContent("Herstellungskosten (werden abgeschrieben)", value: capitalized.asCurrency)
                            .foregroundStyle(Theme.statusWarning)
                    }
                    let result = property.estimatedTaxableResult(forYear: selectedTaxYear)
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(result >= 0 ? "Steuerl. Überschuss \(String(selectedTaxYear))" : "Steuerl. Verlust \(String(selectedTaxYear))", value: abs(result).asCurrency)
                            .font(.headline)
                            .foregroundStyle(result >= 0 ? Theme.statusGood : Theme.statusWarning)
                        yearOverYearCaption(current: result, previous: property.estimatedTaxableResult(forYear: selectedTaxYear - 1))
                    }
                    DisclosureGroup("Herleitung anzeigen") {
                        VStack(alignment: .leading, spacing: 8) {
                            derivationRow("Kaltmiete \(String(selectedTaxYear))", property.annualColdRent(forYear: selectedTaxYear).asCurrency)
                            derivationRow("− Werbungskosten gesamt", property.werbungskosten(forYear: selectedTaxYear).asCurrency)
                            derivationRow("− AfA gesamt", property.totalAfa(forYear: selectedTaxYear).asCurrency)
                            derivationRow(result >= 0 ? "= Steuerl. Überschuss" : "= Steuerl. Verlust", abs(result).asCurrency, emphasized: true)
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                    }
                    NavigationLink("Steuerreport fürs Finanzamt") {
                        TaxReportView(property: property, initialYear: selectedTaxYear)
                    }
                } header: {
                    Text("Ausgaben nach Steuerart \(String(selectedTaxYear))")
                } footer: {
                    Text("Erhaltungsaufwand und sonstige Werbungskosten sind sofort abziehbar, Herstellungskosten werden über die Nutzungsdauer abgeschrieben (siehe AfA).")
                }

                if property.loanAmount > 0 {
                    Section {
                        LabeledContent("Darlehenssumme", value: property.loanAmount.asCurrency)
                        LabeledContent("Zinssatz", value: property.interestRatePercent.asPercent)
                        LabeledContent("Anfänglicher Tilgungssatz", value: property.initialRepaymentRatePercent.asPercent)
                        LabeledContent("Rate/Jahr (Annuität)", value: property.annualAnnuity.asCurrency)
                            .font(.headline)
                        if let breakdown = property.loanBreakdown(forYear: selectedTaxYear) {
                            LabeledContent("davon Zinsanteil \(String(selectedTaxYear))", value: breakdown.interest.asCurrency)
                            LabeledContent("davon Tilgungsanteil \(String(selectedTaxYear))", value: breakdown.principal.asCurrency)
                            LabeledContent("Restschuld Ende \(String(selectedTaxYear))", value: breakdown.remainingBalance.asCurrency)
                        }
                        if !amortizationSchedule.isEmpty {
                            DisclosureGroup("Tilgungsplan bis Volltilgung anzeigen") {
                                ForEach(amortizationSchedule, id: \.year) { row in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(row.year)).font(.subheadline.weight(.semibold))
                                        Text("Zins \(row.interest.asCurrency) · Tilgung \(row.principal.asCurrency) · Restschuld \(row.remaining.asCurrency)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if !monthlyAmortizationSchedule.isEmpty {
                            Button {
                                pdfPreviewURL = tilgungsplanPdfURL()
                            } label: {
                                Label("Tilgungsplan \(String(selectedTaxYear)) monatsweise als PDF", systemImage: "doc.text.magnifyingglass")
                            }
                            if let url = tilgungsplanXLSXURL() {
                                ShareLink("Tilgungsplan \(String(selectedTaxYear)) als Excel-Tabelle exportieren (.xlsx)", item: url)
                            }
                        }
                    } header: {
                        Text("Finanzierung")
                    } footer: {
                        Text("Vereinfachtes Annuitätendarlehen ohne Sondertilgungen oder Zinsanpassung. Der monatsweise Tilgungsplan verteilt Jahreszins/-tilgung gleichmäßig auf die Monate des gewählten Betrachtungsjahres.")
                    }
                }

                Section {
                    let operativeCashFlow = property.operativeCashFlow(forYear: selectedTaxYear)
                    LabeledContent("Operativer Cashflow \(String(selectedTaxYear))", value: operativeCashFlow.asCurrency)
                        .font(.headline)
                        .foregroundStyle(operativeCashFlow >= 0 ? Theme.statusGood : Theme.statusCritical)
                    let cashFlow = property.freeCashFlow(forYear: selectedTaxYear)
                    LabeledContent("Freier Cashflow \(String(selectedTaxYear))", value: cashFlow.asCurrency)
                        .foregroundStyle(cashFlow >= 0 ? Theme.statusGood : Theme.statusCritical)
                    if let landlord = landlords.first, let cashFlowAfterTax = freeCashFlowAfterTax(forYear: selectedTaxYear) {
                        let taxBurden = max(0, property.estimatedTaxableResult(forYear: selectedTaxYear)) * landlord.marginalTaxRatePercent / 100
                        LabeledContent("Geschätzte Steuerlast \(String(selectedTaxYear))", value: taxBurden.asCurrency)
                            .foregroundStyle(Theme.statusWarning)
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent("Cashflow nach Steuer \(String(selectedTaxYear))", value: cashFlowAfterTax.asCurrency)
                                .font(.headline)
                                .foregroundStyle(cashFlowAfterTax >= 0 ? Theme.statusGood : Theme.statusCritical)
                            if let previousCashFlowAfterTax = freeCashFlowAfterTax(forYear: selectedTaxYear - 1) {
                                yearOverYearCaption(current: cashFlowAfterTax, previous: previousCashFlowAfterTax)
                            }
                        }
                    }
                    let monthlyCashFlow = property.freeCashFlow(forMonth: .now)
                    LabeledContent("Freier Cashflow \(Date.now.asMonthYear)", value: monthlyCashFlow.asCurrency)
                        .foregroundStyle(monthlyCashFlow >= 0 ? Theme.statusGood : Theme.statusCritical)
                } footer: {
                    Text("Operativer Cashflow: Kaltmiete abzüglich Barausgaben, aller Betriebskosten (umlagefähig + nicht umlagefähig) und Annuität. Freier Cashflow: wie operativ, aber ohne Abzug der umlagefähigen Betriebskosten (geht davon aus, dass sich Vorauszahlung und umlagefähige Kosten etwa ausgleichen). AfA ist nicht cash-wirksam und daher nicht enthalten. Steuerlast grob geschätzt aus dem Grenzsteuersatz im Vermieterprofil.")
                }
            }
        else {
            Section {
                Text("Keine Kaufdaten erfasst. AfA, Steuer, Finanzierung und Cashflow benötigen Kaufpreis und -datum – unter „Bearbeiten“ ergänzen.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Die tatsächliche Abrechnung (Ist) des oben gewählten Betrachtungsjahres, falls vorhanden.
    private var actualStatementForSelectedYear: UtilityStatement? {
        betriebskostenEntriesForSelectedYear.compactMap {
            if case .actual(let statement) = $0 { return statement }
            return nil
        }.first
    }

    /// Der Wirtschaftsplan (Soll/Prognose) des oben gewählten Betrachtungsjahres, falls vorhanden.
    private var forecastPlanForSelectedYear: WirtschaftsplanStatement? {
        betriebskostenEntriesForSelectedYear.compactMap {
            if case .forecast(let plan) = $0 { return plan }
            return nil
        }.first
    }

    /// Umlagefähige Betriebskosten des gewählten Jahres – Ist, falls vorhanden, sonst Soll.
    private var betriebskostenApportionableTotal: Double {
        actualStatementForSelectedYear?.totalApportionableCosts ?? forecastPlanForSelectedYear?.totalApportionableCosts ?? 0
    }

    /// Nicht umlagefähige Betriebskosten des gewählten Jahres – Ist, falls vorhanden, sonst Soll.
    private var betriebskostenNonApportionableTotal: Double {
        actualStatementForSelectedYear?.nonApportionableLineItemsTotal ?? forecastPlanForSelectedYear?.nonApportionableLineItemsTotal ?? 0
    }

    /// Differenz Ist − Soll (Gesamtkosten) für das gewählte Jahr, nur wenn beide vorliegen – positiv
    /// heißt höhere tatsächliche Kosten als geplant (gleiche Lesart wie in `UtilityStatementListView`).
    private var betriebskostenIstSollDifference: Double? {
        guard let actual = actualStatementForSelectedYear, let forecast = forecastPlanForSelectedYear else { return nil }
        let actualTotal = actual.totalApportionableCosts + actual.nonApportionableLineItemsTotal
        let forecastTotal = forecast.totalApportionableCosts + forecast.nonApportionableLineItemsTotal
        return actualTotal - forecastTotal
    }

    /// Reiter „Betriebskosten“: Abrechnung/Wirtschaftsplan des oben gewählten Betrachtungsjahres.
    @ViewBuilder
    private var betriebskostenTabSections: some View {
        if betriebskostenEntriesForSelectedYear.isEmpty {
            Section("Betriebskosten \(String(selectedTaxYear))") {
                Text("Noch keine Betriebskosten für \(String(selectedTaxYear)) erfasst. Unter Mietverwaltung → Nebenkostenabrechnung lässt sich die Abrechnung der Hausverwaltung oder der Wirtschaftsplan hochladen.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                    KPITile(title: "Umlagefähig \(String(selectedTaxYear))", value: betriebskostenApportionableTotal.asCurrency, systemImage: "eurosign.circle")
                    KPITile(title: "Nicht umlagefähig \(String(selectedTaxYear))", value: betriebskostenNonApportionableTotal.asCurrency, systemImage: "minus.circle", valueColor: Theme.statusWarning)
                    if let difference = betriebskostenIstSollDifference {
                        KPITile(
                            title: "Differenz (Ist − Soll)",
                            value: (difference >= 0 ? "+" : "") + difference.asCurrency,
                            systemImage: difference > 0.5 ? "arrow.up.circle" : (difference < -0.5 ? "arrow.down.circle" : "checkmark.circle"),
                            valueColor: difference > 0.5 ? Theme.statusCritical : (difference < -0.5 ? Theme.statusGood : .secondary)
                        )
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, Theme.spacingS)
            } header: {
                Text("Betriebskosten \(String(selectedTaxYear)) im Überblick")
            }
        }

        ForEach(betriebskostenEntriesForSelectedYear) { entry in
            switch entry {
            case .actual(let statement):
                betriebskostenSection(
                    headerText: "Betriebskosten",
                    apportionableItems: (statement.lineItems ?? []).filter { $0.isApportionable }.sorted { $0.costType < $1.costType },
                    nonApportionableItems: (statement.lineItems ?? []).filter { !$0.isApportionable }.sorted { $0.costType < $1.costType },
                    propertyTaxAmount: statement.propertyTaxAmount,
                    totalApportionableCosts: statement.totalApportionableCosts,
                    nonApportionableTotal: statement.nonApportionableLineItemsTotal,
                    onDeleteApportionable: { offsets in deleteUtilityLineItems((statement.lineItems ?? []).filter { $0.isApportionable }.sorted { $0.costType < $1.costType }, at: offsets) },
                    onDeleteNonApportionable: { offsets in deleteUtilityLineItems((statement.lineItems ?? []).filter { !$0.isApportionable }.sorted { $0.costType < $1.costType }, at: offsets) },
                    onEdit: { statementToEdit = statement },
                    tenantDistributionTarget: statement
                )
            case .forecast(let plan):
                betriebskostenSection(
                    headerText: "Betriebskosten (Wirtschaftsplan/Prognose)",
                    apportionableItems: (plan.lineItems ?? []).filter { $0.isApportionable }.sorted { $0.costType < $1.costType },
                    nonApportionableItems: (plan.lineItems ?? []).filter { !$0.isApportionable }.sorted { $0.costType < $1.costType },
                    propertyTaxAmount: plan.propertyTaxAmount,
                    totalApportionableCosts: plan.totalApportionableCosts,
                    nonApportionableTotal: plan.nonApportionableLineItemsTotal,
                    onDeleteApportionable: { offsets in deleteWirtschaftsplanLineItems((plan.lineItems ?? []).filter { $0.isApportionable }.sorted { $0.costType < $1.costType }, at: offsets) },
                    onDeleteNonApportionable: { offsets in deleteWirtschaftsplanLineItems((plan.lineItems ?? []).filter { !$0.isApportionable }.sorted { $0.costType < $1.costType }, at: offsets) },
                    onEdit: { planToEdit = plan },
                    tenantDistributionTarget: nil
                )
            }
        }

        if !betriebskostenEntries.isEmpty {
            Section {
                if let url = betriebskostenXLSXURL() {
                    ShareLink("Betriebskosten als Excel-Tabelle exportieren (.xlsx)", item: url)
                }
            } footer: {
                Text("Abrechnung = tatsächliche Kosten der Hausverwaltung (Ist). Wirtschaftsplan = Kostenprognose für das laufende/kommende Jahr (Soll). Neue Abrechnungen/Wirtschaftspläne hochladen: unter Mietverwaltung → Nebenkostenabrechnung. Nicht umlagefähige Betriebskosten (z.B. Instandhaltungsrücklage, Verwaltergebühr) verbleiben beim Vermieter und mindern den freien Cashflow. Umlagefähige Betriebskosten werden über die Nebenkostenabrechnung auf die Mieter verteilt.")
            }
        }
    }

    /// Alle Dokumente, die dieser Immobilie zuzuordnen sind (direkt oder über Einheit,
    /// Mietverhältnis, Ausgabe oder Nebenkostenabrechnung) – wie in `DocumentListView` gefiltert.
    private var propertyDocumentCount: Int {
        allDocuments.filter { $0.resolvedProperty == property }.count
    }

    /// Freier Cashflow nach grob geschätzter Steuerlast (Grenzsteuersatz × steuerl. Ergebnis,
    /// bei Verlust 0) für ein beliebiges Jahr – `nil` ohne Vermieterprofil. Gemeinsame Basis für
    /// die Kennzahlenkachel, den Vorjahresvergleich und den Cashflow-Abschnitt weiter unten.
    private func freeCashFlowAfterTax(forYear year: Int) -> Double? {
        guard let landlord = landlords.first else { return nil }
        let taxBurden = max(0, property.estimatedTaxableResult(forYear: year)) * landlord.marginalTaxRatePercent / 100
        return property.freeCashFlow(forYear: year) - taxBurden
    }

    /// Einzeiliger Vorjahresvergleich („▲ 1.234 € ggü. 2025“) für eine Kennzahl, bei der ein
    /// höherer Wert besser ist (Ergebnis, Cashflow) – grün bei Verbesserung, rot bei Verschlechterung.
    @ViewBuilder
    private func yearOverYearCaption(current: Double, previous: Double) -> some View {
        let delta = current - previous
        if abs(delta) >= 0.5 {
            HStack(spacing: 4) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(delta).asCurrency) ggü. \(String(selectedTaxYear - 1))")
            }
            .font(.caption2)
            .foregroundStyle(delta >= 0 ? Theme.statusGood : Theme.statusCritical)
        }
    }

    /// Eine Zeile einer Berechnungsherleitung (z.B. „Kaltmiete − Werbungskosten − AfA = Ergebnis“),
    /// gleiches Muster wie die AfA-Herleitung im Steuer-Objekt-Cockpit.
    @ViewBuilder
    private func derivationRow(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .fontWeight(emphasized ? .semibold : .regular)
    }

    /// Vollständiger Tilgungsverlauf ab Finanzierungsbeginn bis zur Volltilgung (oder maximal 60
    /// Jahre als Sicherheitsgrenze), jahresweise Zins/Tilgung/Restschuld.
    private var amortizationSchedule: [(year: Int, interest: Double, principal: Double, remaining: Double)] {
        guard let loanStartDate = property.loanStartDate, property.loanAmount > 0 else { return [] }
        var rows: [(year: Int, interest: Double, principal: Double, remaining: Double)] = []
        var year = Calendar.current.component(.year, from: loanStartDate)
        while rows.count < 60 {
            guard let breakdown = property.loanBreakdown(forYear: year) else { break }
            rows.append((year, breakdown.interest, breakdown.principal, breakdown.remainingBalance))
            if breakdown.remainingBalance <= 0.5 { break }
            year += 1
        }
        return rows
    }

    /// Monatsweiser Tilgungsplan für das oben gewählte Betrachtungsjahr: die Jahreswerte aus
    /// `loanBreakdown(forYear:)` gleichmäßig auf die 12 Monate verteilt (vereinfachtes
    /// Annuitätendarlehen, keine echte monatliche Verzinsung) – die letzte Restschuld entspricht
    /// exakt der jahresweisen Berechnung, Zwischenmonate sind linear interpoliert.
    private var monthlyAmortizationSchedule: [TilgungsplanReportDocument.MonthRow] {
        guard let yearBreakdown = property.loanBreakdown(forYear: selectedTaxYear) else { return [] }
        let calendar = Calendar.current
        let startYear = property.loanStartDate.map { calendar.component(.year, from: $0) } ?? selectedTaxYear
        let startOfYearBalance: Double = selectedTaxYear <= startYear
            ? property.loanAmount
            : (property.loanBreakdown(forYear: selectedTaxYear - 1)?.remainingBalance ?? property.loanAmount)

        let monthlyInterest = yearBreakdown.interest / 12
        let monthlyPrincipal = yearBreakdown.principal / 12
        var rows: [TilgungsplanReportDocument.MonthRow] = []
        var balance = startOfYearBalance
        for month in 1...12 {
            let isLastMonth = month == 12
            balance = isLastMonth ? yearBreakdown.remainingBalance : max(0, balance - monthlyPrincipal)
            rows.append(.init(month: month, interest: monthlyInterest, principal: monthlyPrincipal, remainingBalance: balance))
        }
        return rows
    }

    private var betriebskostenEntries: [BetriebskostenEntry] {
        let actuals = (property.utilityStatements ?? []).map { BetriebskostenEntry.actual($0) }
        let forecasts = (property.wirtschaftsplaene ?? []).map { BetriebskostenEntry.forecast($0) }
        return (actuals + forecasts).sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.sortRank < $1.sortRank
        }
    }

    /// Nur die Betriebskosten-Einträge (Abrechnung/Wirtschaftsplan) des oben gewählten
    /// Betrachtungsjahres – ersetzt die frühere Anzeige aller Jahre auf einmal, damit das Jahr
    /// überall auf dieser Seite einheitlich ist.
    private var betriebskostenEntriesForSelectedYear: [BetriebskostenEntry] {
        betriebskostenEntries.filter { $0.year == selectedTaxYear }
    }

    /// Alle Jahre, für die auf dieser Seite sinnvoll etwas angezeigt werden kann (Steuer/AfA/
    /// Finanzierung/Cashflow sowie Betriebskosten-Abrechnungen und -Wirtschaftspläne) – Basis für
    /// den einen gemeinsamen Jahres-Picker oben.
    private var availableOverviewYears: [Int] {
        var years = Set(property.availableTaxYears)
        for plan in property.wirtschaftsplaene ?? [] { years.insert(plan.year) }
        return years.sorted(by: >)
    }

    /// Einheitliche Darstellung eines Betriebskosten-Eintrags (Abrechnung oder Wirtschaftsplan) als
    /// zwei eigenständige, klar getrennte Karten: eine für die umlagefähigen, eine für die nicht
    /// umlagefähigen Betriebskosten – statt einer gemischten Liste mit kleinem Label.
    @ViewBuilder
    private func betriebskostenSection<Item: Identifiable & BetriebskostenLineItemDisplayable>(
        headerText: String,
        apportionableItems: [Item],
        nonApportionableItems: [Item],
        propertyTaxAmount: Double,
        totalApportionableCosts: Double,
        nonApportionableTotal: Double,
        onDeleteApportionable: @escaping (IndexSet) -> Void,
        onDeleteNonApportionable: @escaping (IndexSet) -> Void,
        onEdit: @escaping () -> Void,
        tenantDistributionTarget: UtilityStatement?
    ) -> some View {
        // Überschrift + Kurzüberblick: beide Monatsbeträge auf einen Blick.
        Section {
            LabeledContent("Umlagefähig (monatlich)", value: (totalApportionableCosts / 12).asCurrency)
                .font(.headline)
            if nonApportionableTotal > 0 {
                LabeledContent("Nicht umlagefähig (monatlich)", value: (nonApportionableTotal / 12).asCurrency)
                    .foregroundStyle(Theme.statusWarning)
            }
        } header: {
            Text(headerText).font(.title3.weight(.bold))
        }

        // Detailaufstellung der umlagefähigen Betriebskosten.
        Section {
            ForEach(apportionableItems) { item in
                HStack {
                    Text(item.costType)
                    Spacer()
                    Text(item.amount.asCurrency)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: onDeleteApportionable)
            if propertyTaxAmount > 0 {
                HStack {
                    Text("Grundsteuer")
                    Spacer()
                    Text(propertyTaxAmount.asCurrency)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Monatliche Belastung", value: (totalApportionableCosts / 12).asCurrency)
                .font(.headline)
            LabeledContent("Jährliche Belastung", value: totalApportionableCosts.asCurrency)
                .font(.headline)
        } header: {
            Text("Umlagefähige Betriebskosten")
        }

        if !nonApportionableItems.isEmpty {
            Section {
                ForEach(nonApportionableItems) { item in
                    HStack {
                        Text(item.costType)
                        Spacer()
                        Text(item.amount.asCurrency)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: onDeleteNonApportionable)
                LabeledContent("Monatliche Belastung", value: (nonApportionableTotal / 12).asCurrency)
                    .font(.headline)
                    .foregroundStyle(Theme.statusWarning)
                LabeledContent("Jährliche Belastung", value: nonApportionableTotal.asCurrency)
                    .font(.headline)
                    .foregroundStyle(Theme.statusWarning)
            } header: {
                Text("Nicht umlagefähige Betriebskosten")
                    .foregroundStyle(Theme.statusWarning)
            }
        }

        Section {
            if let tenantDistributionTarget {
                NavigationLink(value: tenantDistributionTarget) {
                    Label("Nebenkosten des jeweiligen Mieters anzeigen", systemImage: "person.2.circle")
                }
            }
            Button {
                onEdit()
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
        }
    }

    /// Alle Betriebskosten-Einträge (Abrechnungen und Wirtschaftspläne) als eine `.xlsx`-Tabelle,
    /// mit Jahr, Typ (Ist/Prognose), Kostenart, Umlagefähigkeit und Betrag je Zeile.
    @MainActor
    private func betriebskostenXLSXURL() -> URL? {
        var rows: [[XLSXExporter.CellValue]] = []
        for entry in betriebskostenEntries {
            switch entry {
            case .actual(let statement):
                for item in (statement.lineItems ?? []).sorted(by: { $0.costType < $1.costType }) {
                    rows.append([.number(Double(statement.year)), .string("Abrechnung"), .string(item.costType), .string(item.isApportionable ? "Ja" : "Nein"), .currency(item.amount)])
                }
                if statement.propertyTaxAmount > 0 {
                    rows.append([.number(Double(statement.year)), .string("Abrechnung"), .string("Grundsteuer"), .string("Ja"), .currency(statement.propertyTaxAmount)])
                }
            case .forecast(let plan):
                for item in (plan.lineItems ?? []).sorted(by: { $0.costType < $1.costType }) {
                    rows.append([.number(Double(plan.year)), .string("Wirtschaftsplan"), .string(item.costType), .string(item.isApportionable ? "Ja" : "Nein"), .currency(item.amount)])
                }
                if plan.propertyTaxAmount > 0 {
                    rows.append([.number(Double(plan.year)), .string("Wirtschaftsplan"), .string("Grundsteuer"), .string("Ja"), .currency(plan.propertyTaxAmount)])
                }
            }
        }
        let sheet = XLSXExporter.Sheet(
            name: "Betriebskosten",
            headers: ["Jahr", "Typ", "Kostenart", "Umlagefähig", "Betrag"],
            rows: rows
        )
        guard let data = XLSXExporter.data(sheets: [sheet]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Betriebskosten \(property.name).xlsx")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Baut den mehrjährigen AfA-Verlauf (ab Anschaffung, max. 15 Jahre oder bis zum vollständigen
    /// Restbuchwert) und rendert daraus die Gebäudeabschreibungs-PDF.
    @MainActor
    private func gebaeudeAfaReportURL() -> URL? {
        let calendar = Calendar.current
        let startYear = property.purchaseDate.map { calendar.component(.year, from: $0) }
            ?? property.constructionYear
            ?? calendar.component(.year, from: .now)

        var rows: [GebaeudeAfaReportDocument.YearRow] = []
        var cumulative = 0.0
        for offset in 0..<15 {
            let year = startYear + offset
            let afaForYear = min(property.buildingAfA(forYear: year), max(0, property.buildingValue - cumulative))
            guard afaForYear > 0 else { break }
            cumulative += afaForYear
            rows.append(.init(year: year, afaAmount: afaForYear, cumulativeAfa: cumulative, remainingBookValue: max(0, property.buildingValue - cumulative)))
        }

        let document = GebaeudeAfaReportDocument(
            propertyName: property.name,
            propertyAddress: property.address,
            generatedAt: .now,
            purchasePrice: property.purchasePrice,
            landValue: property.landValue,
            buildingValue: property.buildingValue,
            constructionYear: property.constructionYear,
            purchaseDate: property.purchaseDate,
            afaRatePercent: property.afaRatePercent,
            isManualRate: property.afaRatePercentOverride != nil,
            annualAfa: property.annualBuildingAfA,
            rows: rows
        )
        guard let data = PDFExporter.renderPDF(size: GebaeudeAfaReportDocument.pageSize, content: { document }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Gebäudeabschreibung \(property.name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Legt die Gebäudeabschreibungs-PDF zusätzlich zum reinen Anzeigen als Dokument dieser
    /// Immobilie ab, damit sie auch ohne erneutes Erzeugen wieder auffindbar ist.
    private func saveGebaeudeAfaPDFAsDocument(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let title = "Gebäudeabschreibung \(property.name)"
        let document = Document(title: title, fileName: "\(title).pdf", fileExtension: "pdf", data: data, receiptDate: .now)
        document.property = property
        modelContext.insert(document)
    }

    /// Monatsweiser Tilgungsplan-PDF für das gewählte Betrachtungsjahr.
    @MainActor
    private func tilgungsplanPdfURL() -> URL? {
        let document = TilgungsplanReportDocument(
            propertyName: property.name,
            propertyAddress: property.address,
            generatedAt: .now,
            year: selectedTaxYear,
            purchasePrice: property.purchasePrice,
            loanAmount: property.loanAmount,
            annualAnnuity: property.annualAnnuity,
            rows: monthlyAmortizationSchedule
        )
        guard let data = PDFExporter.renderPDF(size: TilgungsplanReportDocument.pageSize, content: { document }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tilgungsplan \(String(selectedTaxYear)) \(property.name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Monatsweiser Tilgungsplan für das gewählte Betrachtungsjahr als `.xlsx`-Tabelle.
    private func tilgungsplanXLSXURL() -> URL? {
        let rows: [[XLSXExporter.CellValue]] = monthlyAmortizationSchedule.map { row in
            [.number(Double(row.month)), .currency(row.interest), .currency(row.principal), .currency(row.remainingBalance)]
        }
        let sheet = XLSXExporter.Sheet(
            name: "Tilgungsplan \(String(selectedTaxYear))",
            headers: ["Monat", "Zins", "Tilgung", "Restschuld"],
            rows: rows
        )
        guard let data = XLSXExporter.data(sheets: [sheet]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tilgungsplan \(String(selectedTaxYear)) \(property.name).xlsx")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func handleDocumentScan(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            documentScanErrorMessage = "Die Bilddatei konnte nicht gelesen werden."
            return
        }
        documentScanResult = PropertyDocumentOCR.recognize(from: data)
    }

    private func handlePurchaseContractScan(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            documentScanErrorMessage = "Die Bilddatei konnte nicht gelesen werden."
            return
        }
        purchaseContractScanResult = PurchaseContractOCR.recognize(from: data)
    }

    private func deleteUtilityLineItems(_ items: [UtilityCostLineItem], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func deleteWirtschaftsplanLineItems(_ items: [WirtschaftsplanLineItem], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func deleteUnits(at offsets: IndexSet) {
        guard let units = property.units else { return }
        for index in offsets {
            modelContext.delete(units[index])
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    return NavigationStack {
        PropertyDetailView(property: property)
    }
    .modelContainer(PreviewData.container)
}
