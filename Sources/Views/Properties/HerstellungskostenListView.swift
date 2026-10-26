import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

/// Übersicht aller Herstellungskosten (AssetCategory `.improvement`, z.B. Modernisierung/Umbau)
/// über alle Immobilien hinweg, nach Anschaffungsjahr organisiert. Getrennt von der Möblierung
/// (`MoeblierungListView`), da die AfA hier an den Gebäude-Abschreibungssatz gekoppelt ist statt
/// an eine frei wählbare Nutzungsdauer.
struct HerstellungskostenListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DepreciableAsset.placedInServiceDate, order: .reverse) private var allAssets: [DepreciableAsset]
    @State private var showingAddSheet = false
    @State private var assetToEdit: DepreciableAsset?
    @State private var searchText = ""
    @State private var reportYear: Int
    @State private var pdfPreviewURL: URL?
    @State private var showingAddYearSheet = false
    @State private var showingReceiptScanImporter = false
    @State private var receiptScanPending: PendingReceiptScan?

    /// Wenn gesetzt, zeigt diese Instanz nur dieses eine Anschaffungsjahr – für den
    /// Jahres-Unterreiter in der Seitenleiste. Ohne Vorgabe werden alle Jahre angezeigt.
    var fixedYear: Int? = nil

    init(fixedYear: Int? = nil) {
        self.fixedYear = fixedYear
        _reportYear = State(initialValue: fixedYear ?? Calendar.current.component(.year, from: .now))
    }

    /// Alle Herstellungskosten, eingeschränkt auf `fixedYear`, falls gesetzt – Basis für alle
    /// zusammenfassenden Statistiken.
    private var scopedAssets: [DepreciableAsset] {
        let improvements = allAssets.filter { $0.category == .improvement }
        guard let fixedYear else { return improvements }
        return improvements.filter { Calendar.current.component(.year, from: $0.placedInServiceDate) == fixedYear }
    }

    private var assets: [DepreciableAsset] {
        allAssets.filter { $0.category == .improvement }
    }

    private var filteredAssets: [DepreciableAsset] {
        guard !searchText.isEmpty else { return scopedAssets }
        return scopedAssets.filter {
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
    }

    private struct YearGroup: Identifiable {
        let year: Int
        let properties: [PropertyGroup]
        let assets: [DepreciableAsset]
        var id: Int { year }
    }

    /// Die gefilterten Herstellungskosten nach Anschaffungsjahr gruppiert, darin nach Objekt –
    /// neuestes Jahr zuerst.
    private var groupedByYear: [YearGroup] {
        let calendar = Calendar.current
        let byYear = Dictionary(grouping: filteredAssets) { calendar.component(.year, from: $0.placedInServiceDate) }
        return byYear.map { year, yearAssets in
            let properties = Dictionary(grouping: yearAssets) { $0.property?.name ?? "Ohne Immobilie" }
                .map { PropertyGroup(propertyName: $0.key, assets: $0.value.sorted { $0.placedInServiceDate > $1.placedInServiceDate }) }
                .sorted { $0.propertyName < $1.propertyName }
            return YearGroup(year: year, properties: properties, assets: yearAssets)
        }
        .sorted { $0.year > $1.year }
    }

    private var totalCost: Double {
        scopedAssets.reduce(0) { $0 + $1.cost }
    }

    private var totalAnnualDepreciation: Double {
        scopedAssets.reduce(0) { $0 + $1.annualDepreciation }
    }

    /// Jährliche AfA je Objekt über **alle** Herstellungskosten im betrachteten Zeitraum
    /// (unabhängig von der Suche).
    private var allGroupedByProperty: [PropertyGroup] {
        Dictionary(grouping: scopedAssets) { $0.property?.name ?? "Ohne Immobilie" }
            .map { PropertyGroup(propertyName: $0.key, assets: $0.value) }
            .sorted { $0.annualDepreciation != $1.annualDepreciation ? $0.annualDepreciation > $1.annualDepreciation : $0.propertyName < $1.propertyName }
    }

    private func reportGroups(year: Int) -> [AssetReportDocument.PropertyGroup] {
        Dictionary(grouping: assets) { $0.property?.name ?? "Ohne Immobilie" }
            .compactMap { propertyName, items -> AssetReportDocument.PropertyGroup? in
                let rows = items
                    .map { asset -> AssetReportDocument.Row in
                        AssetReportDocument.Row(
                            name: asset.name,
                            placedInServiceDate: asset.placedInServiceDate,
                            cost: asset.cost,
                            afaForYear: asset.depreciation(forYear: year),
                            isSofortabzugThisYear: false
                        )
                    }
                    .filter { $0.afaForYear > 0 }
                    .sorted { $0.placedInServiceDate < $1.placedInServiceDate }
                guard !rows.isEmpty else { return nil }
                return AssetReportDocument.PropertyGroup(propertyName: propertyName, rows: rows)
            }
            .sorted { $0.propertyName < $1.propertyName }
    }

    @MainActor
    private func reportURL() -> URL? {
        let document = AssetReportDocument(
            title: "Herstellungskosten",
            taxYear: reportYear,
            generatedAt: .now,
            groups: reportGroups(year: reportYear),
            showCostColumn: true
        )
        guard let data = PDFExporter.renderPDF(size: AssetReportDocument.pageSize, content: { document }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Herstellungskosten \(reportYear).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    var body: some View {
        List {
            if fixedYear == nil {
                Section {
                    Stepper("Steuerjahr für PDF-Export: \(String(reportYear))", value: $reportYear, in: 2000...2100)
                } footer: {
                    Text("Gilt für den PDF-Export unten – die AfA wird für dieses Jahr berechnet.")
                }
            }

            Section {
                ForEach(allGroupedByProperty) { group in
                    LabeledContent(group.propertyName, value: group.annualDepreciation.asCurrency)
                }
                LabeledContent("Gesamt (alle Objekte)", value: totalAnnualDepreciation.asCurrency)
                    .font(.headline)
            } header: {
                Text("Jährliche AfA nach Objekt")
            }

            Section {
                LabeledContent("Gesamt-Herstellungskosten", value: totalCost.asCurrency)
            }

            if groupedByYear.isEmpty {
                ContentUnavailableView(
                    "Keine Herstellungskosten erfasst",
                    systemImage: "hammer",
                    description: Text("Erfasse Modernisierungs- oder Umbaukosten zur Abschreibung (AfA).")
                )
            } else {
                ForEach(groupedByYear) { yearGroup in
                    Section {
                        ForEach(yearGroup.properties) { propertyGroup in
                            Text(propertyGroup.propertyName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(propertyGroup.assets) { asset in assetRow(asset) }
                                .onDelete { offsets in deleteAssets(in: propertyGroup.assets, at: offsets) }
                        }
                    } header: {
                        Text(String(yearGroup.year)).font(.title3.weight(.bold))
                    } footer: {
                        let subtotal = yearGroup.assets.reduce(0) { $0 + $1.annualDepreciation }
                        Text("AfA \(String(yearGroup.year)): \(subtotal.asCurrency)/Jahr")
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(fixedYear.map { "Herstellungskosten \(String($0))" } ?? "Herstellungskosten")
        .searchable(text: $searchText, prompt: "Herstellungskosten durchsuchen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Herstellungskosten hinzufügen", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingReceiptScanImporter = true
                } label: {
                    Label("Beleg scannen", systemImage: "doc.text.viewfinder")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    pdfPreviewURL = reportURL()
                } label: {
                    Label("Herstellungskosten anzeigen (Steuerjahr \(String(reportYear)))", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(assets.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                if !assets.isEmpty, let url = reportURL() {
                    ShareLink("Herstellungskosten als PDF (Steuerjahr \(String(reportYear)))", item: url)
                }
            }
            if fixedYear == nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingAddYearSheet = true
                    } label: {
                        Label("Jahr hinzufügen", systemImage: "calendar.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            DepreciableAssetEditView(asset: nil)
        }
        .sheet(isPresented: $showingAddYearSheet) {
            AddYearView(category: "improvements", existingYears: Array(Set(allAssets.filter { $0.category == .improvement }.map { Calendar.current.component(.year, from: $0.placedInServiceDate) })))
        }
        .sheet(item: $assetToEdit) { asset in
            DepreciableAssetEditView(asset: asset)
        }
        .fileImporter(isPresented: $showingReceiptScanImporter, allowedContentTypes: [.pdf, .image, .data]) { result in
            handleReceiptScan(result)
        }
        .sheet(item: $receiptScanPending) { pending in
            ReceiptScanReviewView(scanData: pending.data, scanFileExtension: pending.fileExtension, result: pending.result, fixedKind: .asset)
        }
        .quickLookPreview($pdfPreviewURL)
        .overlay {
            if filteredAssets.isEmpty && !assets.isEmpty {
                ContentUnavailableView.search(text: searchText)
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
                    Text(asset.unit != nil ? (asset.unit?.name ?? "") : "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Seit \(asset.placedInServiceDate.asShortDate) · AfA-Satz lt. Gebäude\(asset.property.map { " (\($0.afaRatePercent.asPercent))" } ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(asset.cost.asCurrency)
                    Text("\(asset.annualDepreciation.asCurrency)/Jahr")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deleteAssets(in group: [DepreciableAsset], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(group[index])
        }
    }

    private func handleReceiptScan(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else { return }
        receiptScanPending = PendingReceiptScan(data: data, fileExtension: url.pathExtension, result: ReceiptOCR.recognize(from: data))
    }
}

#Preview {
    NavigationStack {
        HerstellungskostenListView()
    }
    .modelContainer(PreviewData.container)
}
