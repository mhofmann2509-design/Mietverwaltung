import SwiftUI
import SwiftData
import QuickLook

/// Übersicht aller Möblierungs-/Einrichtungsgegenstände (AssetCategory `.furniture`/`.other`),
/// optional auf ein Objekt eingeschränkt (Objekt-Unterreiter in der Seitenleiste). Innerhalb
/// jedes Objekts getrennt nach sofort abgezogenen GWG und über AfA abgeschriebenen Posten.
/// Herstellungskosten (`.improvement`) werden getrennt in `HerstellungskostenListView` gepflegt,
/// da sie steuerlich anders behandelt werden (AfA zum Gebäudesatz statt freier Nutzungsdauer).
struct MoeblierungListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DepreciableAsset.placedInServiceDate, order: .reverse) private var allAssets: [DepreciableAsset]

    /// Wenn gesetzt, zeigt diese Instanz nur die Möblierung eines einzelnen Objekts – für den
    /// Objekt-Unterreiter in der Seitenleiste. Ohne Vorgabe werden alle Objekte gezeigt.
    var property: Property? = nil

    /// Wenn gesetzt, zeigt diese Instanz nur mitvermietete Wirtschaftsgüter – für den
    /// „Mitvermietet"-Unterreiter in der Seitenleiste.
    var onlyCoRented: Bool = false

    @State private var showingAddSheet = false
    @State private var assetToEdit: DepreciableAsset?
    @State private var searchText = ""
    @State private var reportYear = Calendar.current.component(.year, from: .now)
    @State private var pdfPreviewURL: URL?

    /// Alle Möblierungsgegenstände, eingeschränkt auf `property` bzw. `onlyCoRented`, falls
    /// gesetzt – Basis für alle zusammenfassenden Statistiken.
    private var assets: [DepreciableAsset] {
        var furniture = allAssets.filter { $0.category != .improvement }
        if let property {
            furniture = furniture.filter { $0.property == property }
        }
        if onlyCoRented {
            furniture = furniture.filter { $0.isCoRented }
        }
        return furniture
    }

    private var filteredAssets: [DepreciableAsset] {
        guard !searchText.isEmpty else { return assets }
        return assets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.property?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.unit?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private struct PropertyGroup: Identifiable {
        let propertyName: String
        let assets: [DepreciableAsset]
        var id: String { propertyName }
        var annualDepreciation: Double { assets.reduce(0) { $0 + $1.annualDepreciation } }
        var immediateAssets: [DepreciableAsset] { assets.filter { $0.isImmediatelyDeductible } }
        var afaAssets: [DepreciableAsset] { assets.filter { !$0.isImmediatelyDeductible } }
    }

    /// Die gefilterten Möblierungsgegenstände nach Objekt gruppiert (degeneriert zu genau einer
    /// Gruppe, wenn `property` gesetzt ist), darin getrennt nach Sofortabzug und AfA.
    private var groupedByProperty: [PropertyGroup] {
        Dictionary(grouping: filteredAssets) { $0.property?.name ?? "Ohne Immobilie" }
            .map { PropertyGroup(propertyName: $0.key, assets: $0.value.sorted { $0.placedInServiceDate > $1.placedInServiceDate }) }
            .sorted { $0.annualDepreciation != $1.annualDepreciation ? $0.annualDepreciation > $1.annualDepreciation : $0.propertyName < $1.propertyName }
    }

    /// Jährliche AfA je Objekt über **alle** Möblierungsgegenstände (unabhängig von der Suche).
    private var allGroupedByProperty: [PropertyGroup] {
        Dictionary(grouping: assets) { $0.property?.name ?? "Ohne Immobilie" }
            .map { PropertyGroup(propertyName: $0.key, assets: $0.value) }
            .sorted { $0.annualDepreciation != $1.annualDepreciation ? $0.annualDepreciation > $1.annualDepreciation : $0.propertyName < $1.propertyName }
    }

    /// Gesamt-Bemessungsgrundlage (Anschaffungskosten bzw. Zeitwert bei gebrauchten Stücken).
    private var totalValue: Double {
        assets.reduce(0) { $0 + $1.depreciationBasis }
    }

    private var totalAnnualDepreciation: Double {
        assets.reduce(0) { $0 + $1.annualDepreciation }
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: .now)
    }

    /// Summe der GWG-Sofortabzüge, die ins laufende Jahr fallen.
    private var totalImmediateDeductionThisYear: Double {
        assets.filter { $0.immediateDeductionYear == currentYear }.reduce(0) { $0 + $1.depreciationBasis }
    }

    /// Summe der Möbel, die zusammen mit einer Einheit vermietet werden (Möblierungszuschlag).
    private var totalMitvermietet: Double {
        assets.filter { $0.isCoRented }.reduce(0) { $0 + $1.depreciationBasis }
    }

    private var immediateTotal: Double {
        assets.filter { $0.isImmediatelyDeductible }.reduce(0) { $0 + $1.depreciationBasis }
    }

    private var afaTotal: Double {
        assets.filter { !$0.isImmediatelyDeductible }.reduce(0) { $0 + $1.depreciationBasis }
    }

    /// Baut die PDF-Zeilen für ein bestimmtes Steuerjahr – AfA monatsgenau anteilig, Sofortabzug
    /// nur in dem Jahr markiert, in dem er tatsächlich greift. Objekte/Posten ohne jegliche
    /// steuerliche Relevanz in diesem Jahr (AfA 0 und kein Sofortabzug) werden nicht aufgeführt.
    private func reportGroups(year: Int) -> [AssetReportDocument.PropertyGroup] {
        Dictionary(grouping: assets) { $0.property?.name ?? "Ohne Immobilie" }
            .compactMap { propertyName, items -> AssetReportDocument.PropertyGroup? in
                let rows = items
                    .map { asset -> AssetReportDocument.Row in
                        let isSofortabzug = asset.immediateDeductionYear == year
                        return AssetReportDocument.Row(
                            name: asset.name,
                            placedInServiceDate: asset.placedInServiceDate,
                            cost: asset.depreciationBasis,
                            afaForYear: asset.depreciation(forYear: year),
                            isSofortabzugThisYear: isSofortabzug
                        )
                    }
                    .filter { $0.afaForYear > 0 || $0.isSofortabzugThisYear }
                    .sorted { $0.placedInServiceDate < $1.placedInServiceDate }
                guard !rows.isEmpty else { return nil }
                return AssetReportDocument.PropertyGroup(propertyName: propertyName, rows: rows)
            }
            .sorted { $0.propertyName < $1.propertyName }
    }

    private var reportTitle: String {
        if let property {
            return "Möblierungsliste – \(property.name)"
        }
        if onlyCoRented {
            return "Möblierungsliste – Mitvermietet"
        }
        return "Möblierungsliste"
    }

    @MainActor
    private func reportURL() -> URL? {
        let document = AssetReportDocument(
            title: reportTitle,
            taxYear: reportYear,
            generatedAt: .now,
            groups: reportGroups(year: reportYear),
            showCostColumn: false
        )
        guard let data = PDFExporter.renderPDF(size: AssetReportDocument.pageSize, content: { document }) else { return nil }
        let fileName = property?.name ?? (onlyCoRented ? "Mitvermietet" : "Möblierungsliste")
        return try? ExportFileStore.write(data, fileName: "Möblierungsliste \(fileName) \(reportYear).pdf")
    }

    /// Excel-Export aller angezeigten Wirtschaftsgüter als echte `.xlsx`-Datei.
    private var xlsxExportURL: URL? {
        let rows: [[XLSXExporter.CellValue]] = assets.sorted(by: { $0.placedInServiceDate < $1.placedInServiceDate }).map { asset in
            [
                .string(asset.name),
                .string(asset.category.label),
                .string(asset.placedInServiceDate.asShortDate),
                .currency(asset.cost),
                .string(asset.isUsed ? "Ja" : "Nein"),
                asset.isUsed ? .currency(asset.estimatedValueAtAcquisition) : .string(""),
                .string(asset.isCoRented ? "Ja" : "Nein"),
                .string(asset.isImmediatelyDeductible ? "Sofortabzug (GWG)" : "AfA über \(asset.usefulLifeYears) Jahre"),
                .string(asset.property?.name ?? ""),
                .string(asset.unit?.name ?? "")
            ]
        }
        let sheet = XLSXExporter.Sheet(
            name: "Möblierung",
            headers: ["Bezeichnung", "Art", "Anschaffung", "Betrag", "Gebraucht", "Zeitwert", "Mitvermietet", "Steuerliche Behandlung", "Immobilie", "Einheit"],
            rows: rows
        )
        guard let data = XLSXExporter.data(sheets: [sheet]) else { return nil }
        let fileName = property?.name ?? (onlyCoRented ? "Mitvermietet" : "Möblierungsliste")
        return try? ExportFileStore.write(data, fileName: "Möblierungsliste \(fileName).xlsx")
    }

    var body: some View {
        List {
            Section {
                Stepper("Steuerjahr für PDF-Export: \(String(reportYear))", value: $reportYear, in: 2000...2100)
            } footer: {
                Text("Gilt für den PDF-Export unten – AfA und Sofortabzug werden für dieses Jahr berechnet.")
            }

            if property == nil {
                Section {
                    ForEach(allGroupedByProperty) { group in
                        LabeledContent(group.propertyName, value: group.annualDepreciation.asCurrency)
                    }
                    LabeledContent("Gesamt (alle Objekte)", value: totalAnnualDepreciation.asCurrency)
                        .font(.headline)
                } header: {
                    Text("Jährliche AfA nach Objekt")
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                    KPITile(title: "Anschaffungs-/Zeitwert", value: totalValue.asCurrency, systemImage: "sofa")
                    KPITile(title: "Davon mitvermietet", value: totalMitvermietet.asCurrency, systemImage: "key.horizontal")
                    KPITile(title: "Sofort abgezogen (GWG)", value: immediateTotal.asCurrency, systemImage: "bolt", valueColor: Theme.statusWarning)
                    KPITile(title: "Über AfA abgeschrieben", value: afaTotal.asCurrency, systemImage: "chart.line.downtrend.xyaxis")
                    if totalImmediateDeductionThisYear > 0 {
                        KPITile(
                            title: "Sofortabzug (GWG) \(String(currentYear))",
                            value: totalImmediateDeductionThisYear.asCurrency,
                            systemImage: "exclamationmark.circle",
                            valueColor: Theme.statusWarning
                        )
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, Theme.spacingS)
            } header: {
                Text("Gesamtübersicht")
            }

            ForEach(groupedByProperty) { group in
                if !group.immediateAssets.isEmpty {
                    Section {
                        ForEach(group.immediateAssets) { asset in assetRow(asset) }
                            .onDelete { offsets in deleteAssets(in: group.immediateAssets, at: offsets) }
                    } header: {
                        categoryHeader(propertyName: group.propertyName, suffix: "Sofortabzug (GWG)", items: group.immediateAssets)
                    }
                }
                if !group.afaAssets.isEmpty {
                    Section {
                        ForEach(group.afaAssets) { asset in assetRow(asset) }
                            .onDelete { offsets in deleteAssets(in: group.afaAssets, at: offsets) }
                    } header: {
                        categoryHeader(propertyName: group.propertyName, suffix: "AfA", items: group.afaAssets)
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(property?.name ?? (onlyCoRented ? "Mitvermietet" : "Möblierung"))
        .searchable(text: $searchText, prompt: "Möblierung durchsuchen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Wirtschaftsgut hinzufügen", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    pdfPreviewURL = reportURL()
                } label: {
                    Label("Möblierungsliste anzeigen (Steuerjahr \(String(reportYear)))", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(assets.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                if !assets.isEmpty {
                    ExportShareLink("Möblierungsliste teilen (Steuerjahr \(String(reportYear)))", pdf: { reportURL() })
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                ExportShareLink("Als Excel-Tabelle exportieren (.xlsx)", spreadsheet: { xlsxExportURL })
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            DepreciableAssetEditView(property: property, asset: nil)
        }
        .sheet(item: $assetToEdit) { asset in
            DepreciableAssetEditView(asset: asset)
        }
        .quickLookPreview($pdfPreviewURL)
        .overlay {
            if assets.isEmpty {
                ContentUnavailableView(
                    "Keine Möblierung erfasst",
                    systemImage: "sofa",
                    description: Text("Erfasse Einbauküche, Möbel oder andere Wirtschaftsgüter zur Abschreibung (AfA).")
                )
            } else if filteredAssets.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private func categoryHeader(propertyName: String, suffix: String, items: [DepreciableAsset]) -> some View {
        let subtotal = items.reduce(0) { $0 + $1.annualDepreciation }
        HStack {
            Text(property == nil ? "\(propertyName) – \(suffix)" : suffix)
            Spacer()
            if subtotal > 0 {
                Text("AfA \(subtotal.asCurrency)/Jahr")
            }
        }
    }

    @ViewBuilder
    private func assetRow(_ asset: DepreciableAsset) -> some View {
        Button {
            assetToEdit = asset
        } label: {
            HStack {
                Image(systemName: asset.category.systemImage)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .foregroundStyle(.primary)
                    Text("\(asset.category.label)\(asset.unit != nil ? " · " + (asset.unit?.name ?? "") : "")\(asset.isCoRented ? " · mitvermietet" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if asset.isUsed {
                        Text("Gebraucht · Zeitwert bei Anschaffung angesetzt")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if asset.isImmediatelyDeductible {
                        Text("Sofortabzug (GWG) · abgezogen \(String(asset.immediateDeductionYear ?? 0))")
                            .font(.caption2)
                            .foregroundStyle(Theme.statusWarning)
                    } else {
                        Text("Seit \(asset.placedInServiceDate.asShortDate) · \(asset.usefulLifeYears) Jahre")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(asset.depreciationBasis.asCurrency)
                    if asset.isImmediatelyDeductible {
                        Text("Sofortabzug")
                            .font(.caption2)
                            .foregroundStyle(Theme.statusWarning)
                    } else {
                        Text("\(asset.annualDepreciation.asCurrency)/Jahr")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func deleteAssets(in group: [DepreciableAsset], at offsets: IndexSet) {
        for index in offsets {
            DepreciableAsset.delete(group[index], context: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        MoeblierungListView()
    }
    .modelContainer(PreviewData.container)
}
