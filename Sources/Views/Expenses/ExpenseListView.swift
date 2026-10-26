import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showingAddSheet = false
    @State private var expenseToEdit: Expense?
    @State private var searchText = ""
    @State private var reportYear: Int
    @State private var pdfPreviewURL: URL?
    @State private var showingAddYearSheet = false
    @State private var showingReceiptScanImporter = false
    @State private var receiptScanPending: PendingReceiptScan?

    /// Wenn gesetzt, zeigt diese Instanz nur dieses eine Jahr – für den Jahres-Unterreiter in der
    /// Seitenleiste. Ohne Vorgabe werden alle Jahre angezeigt.
    var fixedYear: Int? = nil

    init(fixedYear: Int? = nil) {
        self.fixedYear = fixedYear
        _reportYear = State(initialValue: fixedYear ?? Calendar.current.component(.year, from: .now))
    }

    /// Alle Ausgaben, eingeschränkt auf `fixedYear`, falls gesetzt – Basis für alle
    /// zusammenfassenden Statistiken (Objekt, Art, Gesamt).
    private var scopedExpenses: [Expense] {
        guard let fixedYear else { return expenses }
        return expenses.filter { Calendar.current.component(.year, from: $0.date) == fixedYear }
    }

    private var filteredExpenses: [Expense] {
        guard !searchText.isEmpty else { return scopedExpenses }
        return scopedExpenses.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.category.label.localizedCaseInsensitiveContains(searchText) ||
            ($0.property?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private struct QuarterGroup: Identifiable {
        let label: String
        let quarterNumber: Int
        let expenses: [Expense]
        var id: Int { quarterNumber }
    }

    private struct YearGroup: Identifiable {
        let year: Int
        let quarters: [QuarterGroup]
        let expenses: [Expense]
        var id: Int { year }
    }

    /// Die gefilterten Ausgaben nach Kalenderjahr, darin nach Quartal gruppiert – neuestes Jahr
    /// und neuestes Quartal zuerst.
    private var groupedByYear: [YearGroup] {
        let calendar = Calendar.current
        let byYear = Dictionary(grouping: filteredExpenses) { calendar.component(.year, from: $0.date) }
        return byYear.map { year, yearExpenses in
            let byQuarter = Dictionary(grouping: yearExpenses) { expense -> Int in
                (calendar.component(.month, from: expense.date) - 1) / 3 + 1
            }
            let quarters = byQuarter.map { quarterNumber, items in
                QuarterGroup(label: "Q\(quarterNumber)", quarterNumber: quarterNumber, expenses: items.sorted { $0.date > $1.date })
            }.sorted { $0.quarterNumber > $1.quarterNumber }
            return YearGroup(year: year, quarters: quarters, expenses: yearExpenses)
        }
        .sorted { $0.year > $1.year }
    }

    private var totalAmount: Double {
        scopedExpenses.reduce(0) { $0 + $1.amount }
    }

    private func amount(for treatment: TaxTreatment, in group: [Expense]) -> Double {
        group.filter { $0.taxTreatment == treatment }.reduce(0) { $0 + $1.amount }
    }

    private struct PropertyTotal: Identifiable {
        let propertyName: String
        let total: Double
        var id: String { propertyName }
    }

    /// Ausgaben je Objekt zusammengerechnet – Objekte mit der höchsten Summe zuerst.
    private var totalsByProperty: [PropertyTotal] {
        Dictionary(grouping: scopedExpenses) { $0.property?.name ?? "Ohne Immobilie" }
            .map { PropertyTotal(propertyName: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.propertyName < $1.propertyName }
    }

    private var maintenanceTotal: Double { amount(for: .maintenanceExpense, in: scopedExpenses) }
    private var otherDeductibleTotal: Double { amount(for: .otherDeductible, in: scopedExpenses) }
    private var capitalizedTotal: Double { amount(for: .capitalized, in: scopedExpenses) }

    private var expensesInReportYear: [Expense] {
        expenses.filter { Calendar.current.component(.year, from: $0.date) == reportYear }
    }

    @MainActor
    private func reportTemporaryURL() -> URL? {
        let yearExpenses = expensesInReportYear
        let groups = Dictionary(grouping: yearExpenses) { $0.property?.name ?? "Ohne Immobilie" }
            .map { propertyName, items -> ExpenseReportDocument.PropertyGroup in
                let rows = items.sorted { $0.date < $1.date }.map {
                    ExpenseReportDocument.Row(date: $0.date, title: $0.title.isEmpty ? $0.category.label : $0.title, treatment: $0.taxTreatment, amount: $0.amount)
                }
                return ExpenseReportDocument.PropertyGroup(propertyName: propertyName, rows: rows)
            }
            .sorted { $0.propertyName < $1.propertyName }

        let document = ExpenseReportDocument(
            taxYear: reportYear,
            generatedAt: .now,
            groups: groups,
            maintenanceTotal: amount(for: .maintenanceExpense, in: yearExpenses),
            otherDeductibleTotal: amount(for: .otherDeductible, in: yearExpenses),
            capitalizedTotal: amount(for: .capitalized, in: yearExpenses),
            grandTotal: yearExpenses.reduce(0) { $0 + $1.amount }
        )
        guard let data = PDFExporter.renderPDF(size: ExpenseReportDocument.pageSize, content: { document }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ausgabenübersicht \(reportYear).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Excel-Export aller Ausgaben als echte `.xlsx`-Datei (für Excel/Steuerberater).
    private func xlsxExportURL() -> URL? {
        let rows: [[XLSXExporter.CellValue]] = expenses.sorted(by: { $0.date < $1.date }).map { expense in
            [
                .number(Double(Calendar.current.component(.year, from: expense.date))),
                .string(expense.date.asShortDate),
                .string(expense.title.isEmpty ? expense.category.label : expense.title),
                .string(expense.category.label),
                .string(expense.taxTreatment.shortLabel),
                .currency(expense.amount),
                .string(expense.property?.name ?? ""),
                .string(expense.unit?.name ?? "")
            ]
        }
        let sheet = XLSXExporter.Sheet(
            name: "Ausgaben",
            headers: ["Jahr", "Datum", "Bezeichnung", "Kategorie", "Steuerliche Behandlung", "Betrag", "Immobilie", "Einheit"],
            rows: rows
        )
        guard let data = XLSXExporter.data(sheets: [sheet]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ausgaben.xlsx")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    var body: some View {
        List {
            if let fixedYear {
                Section {
                    LabeledContent("Gesamtausgaben \(String(fixedYear))", value: totalAmount.asCurrency)
                        .font(.headline)
                } footer: {
                    Text("Gilt auch für den PDF-Export fürs Finanzamt unten.")
                }
            } else {
                Section {
                    Stepper("Steuerjahr für PDF-Export: \(String(reportYear))", value: $reportYear, in: 2000...2100)
                } footer: {
                    Text("Gilt für den PDF-Export fürs Finanzamt unten – nur Ausgaben aus diesem Jahr werden aufgeführt.")
                }
            }

            Section {
                ForEach(totalsByProperty) { propertyTotal in
                    LabeledContent(propertyTotal.propertyName, value: propertyTotal.total.asCurrency)
                }
                LabeledContent("Gesamt (alle Objekte)", value: totalAmount.asCurrency)
                    .font(.headline)
            } header: {
                Text("Ausgaben nach Objekt")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                    KPITile(title: "Erhaltungsaufwendungen", value: maintenanceTotal.asCurrency, systemImage: "wrench.and.screwdriver")
                    KPITile(title: "Sonstige Werbungskosten", value: otherDeductibleTotal.asCurrency, systemImage: "minus.circle")
                    if capitalizedTotal > 0 {
                        KPITile(title: "Herstellungskosten (AfA)", value: capitalizedTotal.asCurrency, systemImage: "chart.line.downtrend.xyaxis", valueColor: Theme.statusWarning)
                    }
                    KPITile(title: "Gesamtausgaben", value: totalAmount.asCurrency, systemImage: "eurosign.circle")
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, Theme.spacingS)
            } header: {
                Text("Ausgaben nach Art")
            }

            ForEach(groupedByYear) { yearGroup in
                Section {
                    ForEach(yearGroup.quarters) { quarterGroup in
                        Text(quarterGroup.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(quarterGroup.expenses) { expense in
                            Button {
                                expenseToEdit = expense
                            } label: {
                                HStack {
                                    Image(systemName: expense.category.systemImage)
                                        .foregroundStyle(expense.category.color)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(expense.title.isEmpty ? expense.category.label : expense.title)
                                            .foregroundStyle(.primary)
                                        Text("\(expense.date.asShortDate) · \(expense.property?.name ?? "")\(expense.unit != nil ? " · " + (expense.unit?.name ?? "") : "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Label(expense.taxTreatment.shortLabel, systemImage: expense.taxTreatment.systemImage)
                                            .font(.caption2)
                                            .foregroundStyle(expense.taxTreatment.color)
                                    }
                                    Spacer()
                                    Text(expense.amount.asCurrency)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            deleteExpenses(in: quarterGroup.expenses, at: offsets)
                        }
                    }
                } header: {
                    Text(String(yearGroup.year)).font(.title3.weight(.bold))
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erhaltungsaufwand: \(amount(for: .maintenanceExpense, in: yearGroup.expenses).asCurrency)")
                        Text("Sonstige Werbungskosten: \(amount(for: .otherDeductible, in: yearGroup.expenses).asCurrency)")
                        let capitalized = amount(for: .capitalized, in: yearGroup.expenses)
                        if capitalized > 0 {
                            Text("Herstellungskosten (AfA): \(capitalized.asCurrency)")
                        }
                        let total = yearGroup.expenses.reduce(0) { $0 + $1.amount }
                        Text("Gesamtausgaben \(String(yearGroup.year)): \(total.asCurrency)")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(fixedYear.map { "Ausgaben \(String($0))" } ?? "Ausgaben")
        .searchable(text: $searchText, prompt: "Ausgaben durchsuchen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Ausgabe hinzufügen", systemImage: "plus")
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
                    pdfPreviewURL = reportTemporaryURL()
                } label: {
                    Label("Für Finanzamt anzeigen (Steuerjahr \(String(reportYear)))", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(expensesInReportYear.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                if let url = reportTemporaryURL() {
                    ShareLink("Für Finanzamt als PDF exportieren (Steuerjahr \(String(reportYear)))", item: url)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                if let url = xlsxExportURL() {
                    ShareLink("Als Excel-Tabelle exportieren (.xlsx)", item: url)
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
            ExpenseEditView(expense: nil)
        }
        .sheet(isPresented: $showingAddYearSheet) {
            AddYearView(category: "expenses", existingYears: Array(Set(expenses.map { Calendar.current.component(.year, from: $0.date) })))
        }
        .sheet(item: $expenseToEdit) { expense in
            ExpenseEditView(expense: expense)
        }
        .fileImporter(isPresented: $showingReceiptScanImporter, allowedContentTypes: [.pdf, .image, .data]) { result in
            handleReceiptScan(result)
        }
        .sheet(item: $receiptScanPending) { pending in
            ReceiptScanReviewView(scanData: pending.data, scanFileExtension: pending.fileExtension, result: pending.result, fixedKind: .expense)
        }
        .quickLookPreview($pdfPreviewURL)
        .overlay {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "Keine Ausgaben",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Erfasse Reparaturen, Nebenkosten oder andere Ausgaben.")
                )
            } else if filteredExpenses.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func deleteExpenses(in group: [Expense], at offsets: IndexSet) {
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
        ExpenseListView()
    }
    .modelContainer(PreviewData.container)
}
