import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.receiptDate, order: .reverse) private var documents: [Document]
    @State private var previewURL: URL?

    /// Wenn gesetzt, zeigt diese Instanz nur die Dokumente eines einzelnen Objekts – für den
    /// Objekt-Unterreiter in der Seitenleiste. Ohne Vorgabe werden alle Dokumente, nach Objekt
    /// gruppiert, angezeigt.
    var property: Property? = nil

    /// Wenn gesetzt (zusammen mit `property`, ohne `folder`), zeigt diese Instanz nur Dokumente
    /// dieses Reiters, die KEINEM Ordner zugeordnet sind – die Ordner selbst werden darüber in
    /// `DocumentCategoryView` aufgelistet, ihre Dokumente über `folder` unten.
    var category: DocumentCategory? = nil

    /// Wenn gesetzt, zeigt diese Instanz nur die Dokumente dieses einen, vom Nutzer angelegten
    /// Ordners – unabhängig von `category` (der Ordner bestimmt dann den Reiter).
    var folder: DocumentFolder? = nil

    @State private var showingAddSheet = false
    @State private var selectedYear: Int?
    @State private var searchText = ""

    private var isScoped: Bool { property != nil || category != nil || folder != nil }

    private var scopedDocuments: [Document] {
        var result = documents
        if let property {
            result = result.filter { $0.resolvedProperty == property }
        }
        if let folder {
            result = result.filter { $0.folder == folder }
        } else if let category {
            result = result.filter { $0.category == category && $0.folder == nil }
        }
        return result
    }

    private var availableYears: [Int] {
        let years = Set(scopedDocuments.map { Calendar.current.component(.year, from: $0.receiptDate) })
        return years.sorted(by: >)
    }

    private var filteredDocuments: [Document] {
        var result = scopedDocuments
        if let selectedYear {
            result = result.filter { Calendar.current.component(.year, from: $0.receiptDate) == selectedYear }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.linkedToDescription.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var deductibleTotalForSelectedYear: Double {
        filteredDocuments.compactMap { $0.expense }
            .filter { $0.taxTreatment != .notDeductible }
            .reduce(0) { $0 + $1.amount }
    }

    private struct PropertyGroup: Identifiable {
        let propertyName: String
        let documents: [Document]
        var id: String { propertyName }
    }

    /// Die gefilterten Dokumente nach Immobilie gruppiert, alphabetisch sortiert; nicht
    /// zuordenbare Dokumente landen in einer eigenen Gruppe am Ende.
    private var groupedByProperty: [PropertyGroup] {
        Dictionary(grouping: filteredDocuments) { $0.resolvedProperty?.name ?? "Ohne Zuordnung" }
            .map { PropertyGroup(propertyName: $0.key, documents: $0.value) }
            .sorted { lhs, rhs in
                if lhs.propertyName == "Ohne Zuordnung" { return false }
                if rhs.propertyName == "Ohne Zuordnung" { return true }
                return lhs.propertyName < rhs.propertyName
            }
    }

    private var navigationTitleText: String {
        if let folder {
            return folder.name
        }
        if let category {
            return category.label
        }
        if let property {
            return property.name
        }
        return "Dokumente"
    }

    var body: some View {
        List {
            if !availableYears.isEmpty {
                Section {
                    Picker("Steuerjahr", selection: $selectedYear) {
                        Text("Alle Jahre").tag(Optional<Int>.none)
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(Optional(year))
                        }
                    }
                    .pickerStyle(.menu)
                    if selectedYear != nil {
                        LabeledContent("Steuerlich absetzbar \(selectedYear.map(String.init) ?? "")", value: deductibleTotalForSelectedYear.asCurrency)
                    }
                } footer: {
                    Text("Sortiert nach Belegdatum – für die Steuererklärung lässt sich so gezielt ein Jahr abrufen.")
                }
            }

            if isScoped {
                Section {
                    ForEach(filteredDocuments) { document in documentRow(document) }
                        .onDelete { offsets in deleteDocuments(in: filteredDocuments, at: offsets) }
                }
            } else {
                ForEach(groupedByProperty) { group in
                    Section {
                        ForEach(group.documents) { document in documentRow(document) }
                            .onDelete { offsets in deleteDocuments(in: group.documents, at: offsets) }
                    } header: {
                        Text(group.propertyName)
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Als Orientierung: Belege für die Steuererklärung mindestens bis zum Ablauf der Festsetzungsfrist aufbewahren – i.d.R. 4 Jahre nach Abgabe der jeweiligen Steuererklärung, bei grob fahrlässiger oder vorsätzlicher Steuerverkürzung deutlich länger. Keine Rechtsberatung, im Zweifel beim Steuerberater erfragen.")
            }
        }
        .themedScrollBackground()
        .navigationTitle(navigationTitleText)
        .searchable(text: $searchText, prompt: "Dokumente durchsuchen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Beleg erfassen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDocumentView(initialProperty: property ?? folder?.property, initialCategory: folder?.category ?? category, initialFolder: folder)
        }
        .quickLookPreview($previewURL)
        .overlay {
            if scopedDocuments.isEmpty {
                ContentUnavailableView(
                    "Keine Dokumente",
                    systemImage: "folder",
                    description: Text("Scanne Belege oder lege Verträge, Fotos und Rechnungen ab.")
                )
            }
        }
    }

    @ViewBuilder
    private func documentRow(_ document: Document) -> some View {
        HStack {
            Image(systemName: iconName(for: document.fileExtension))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title.isEmpty ? document.fileName : document.title)
                HStack(spacing: 4) {
                    Text(document.receiptDate.asShortDate)
                    Text("·")
                    Text(document.linkedToDescription)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let expense = document.expense {
                    Label(expense.taxTreatment.shortLabel, systemImage: expense.taxTreatment.systemImage)
                        .font(.caption2)
                        .foregroundStyle(expense.taxTreatment.color)
                }
            }
            Spacer()
            if let amount = document.expense?.amount, amount > 0 {
                Text(amount.asCurrency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let shareFile = ExportFile.document(document)
            ShareLink(item: shareFile, preview: shareFile.preview) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewURL = document.temporaryFileURL
        }
    }

    private func iconName(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic": return "photo"
        default: return "doc"
        }
    }

    private func deleteDocuments(in group: [Document], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(group[index])
        }
    }
}

#Preview {
    NavigationStack {
        DocumentListView()
    }
    .modelContainer(PreviewData.container)
}
