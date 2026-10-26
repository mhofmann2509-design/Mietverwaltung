import SwiftUI
import SwiftData

/// Eine schön formatierte, nach Jahren unterteilte Aufstellung aller Ausgaben (Erhaltungsaufwand,
/// sonstige Werbungskosten, Herstellungskosten) sowie AfA und Mieteinnahmen – zum Teilen/Ablegen
/// für die Steuererklärung (Anlage V). Vereinfachte Näherung, ersetzt keine Steuerberatung.
struct TaxReportView: View {
    let property: Property
    let initialYear: Int
    @Environment(\.modelContext) private var modelContext

    @State private var showAllYears = false
    @State private var selectedYear: Int

    init(property: Property, initialYear: Int) {
        self.property = property
        self.initialYear = initialYear
        _selectedYear = State(initialValue: initialYear)
    }

    private var years: [Int] {
        showAllYears ? property.availableTaxYears : [selectedYear]
    }

    private func expenses(forYear year: Int, treatment: TaxTreatment) -> [Expense] {
        property.allExpenses(forYear: year)
            .filter { $0.taxTreatment == treatment }
            .sorted { $0.date < $1.date }
    }

    private func reportText(forYear year: Int) -> String {
        var lines: [String] = []
        lines.append("── \(property.name) – Steuerjahr \(year) ──")
        lines.append("")
        lines.append("Mieteinnahmen (Kaltmiete): \(property.annualColdRent(forYear: year).asCurrency)")
        lines.append("")

        func section(_ title: String, _ treatment: TaxTreatment) {
            let items = expenses(forYear: year, treatment: treatment)
            lines.append("\(title):")
            if items.isEmpty {
                lines.append("  (keine)")
            } else {
                for expense in items {
                    let location = [expense.property?.name, expense.unit?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    lines.append("  • \(expense.date.asShortDate)  \(expense.title.isEmpty ? expense.category.label : expense.title)\(location.isEmpty ? "" : " (\(location))"): \(expense.amount.asCurrency)")
                }
            }
            let total = items.reduce(0) { $0 + $1.amount }
            lines.append("  Summe \(title): \(total.asCurrency)")
            lines.append("")
        }

        section("Erhaltungsaufwand", .maintenanceExpense)
        section("Sonstige Werbungskosten", .otherDeductible)
        section("Herstellungskosten (AfA über Nutzungsdauer)", .capitalized)

        lines.append("Abschreibungen (AfA):")
        lines.append("  Gebäude-AfA (\(property.afaRatePercent.asPercent)): \(property.buildingAfA(forYear: year).asCurrency)")
        for asset in property.depreciableAssets ?? [] where asset.depreciation(forYear: year) > 0 {
            let location = asset.unit?.name ?? "Immobilie"
            lines.append("  • \(asset.name) (\(location)): \(asset.depreciation(forYear: year).asCurrency)")
        }
        lines.append("  Summe AfA: \(property.totalAfa(forYear: year).asCurrency)")
        lines.append("")

        let result = property.estimatedTaxableResult(forYear: year)
        lines.append(result >= 0 ? "Steuerlicher Überschuss: \(result.asCurrency)" : "Steuerlicher Verlust: \(abs(result).asCurrency)")
        return lines.joined(separator: "\n")
    }

    private var fullReportText: String {
        years.sorted(by: >).map { reportText(forYear: $0) }.joined(separator: "\n\n")
    }

    var body: some View {
        List {
            Section {
                Toggle("Alle Jahre", isOn: $showAllYears)
                if !showAllYears {
                    Picker("Jahr", selection: $selectedYear) {
                        ForEach(property.availableTaxYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                }
            }

            ForEach(years.sorted(by: >), id: \.self) { year in
                Section(String(year)) {
                    LabeledContent("Mieteinnahmen", value: property.annualColdRent(forYear: year).asCurrency)
                    yearBreakdownRow(title: "Erhaltungsaufwand", treatment: .maintenanceExpense, year: year)
                    yearBreakdownRow(title: "Sonstige Werbungskosten", treatment: .otherDeductible, year: year)
                    yearBreakdownRow(title: "Herstellungskosten", treatment: .capitalized, year: year)
                    LabeledContent("AfA gesamt", value: property.totalAfa(forYear: year).asCurrency)
                    let result = property.estimatedTaxableResult(forYear: year)
                    LabeledContent(result >= 0 ? "Überschuss" : "Verlust", value: abs(result).asCurrency)
                        .font(.headline)
                        .foregroundStyle(result >= 0 ? Theme.statusGood : Theme.statusWarning)
                }
            }

            Section {
                ShareLink(item: fullReportText) {
                    Label("Steuerreport als Text teilen", systemImage: "square.and.arrow.up")
                }
                if let url = xlsxReportURL() {
                    ShareLink("Steuerreport als Excel-Tabelle exportieren (.xlsx)", item: url)
                    Button {
                        saveXLSXAsDocument(url: url)
                    } label: {
                        Label("Steuerreport als Excel-Dokument ablegen", systemImage: "tray.and.arrow.down")
                    }
                }
            } footer: {
                Text("Vereinfachte Näherung zur Vorbereitung der Steuererklärung (Anlage V), ersetzt keine Steuerberatung.")
            }
        }
        .navigationTitle("Steuerreport")
    }

    @ViewBuilder
    private func yearBreakdownRow(title: String, treatment: TaxTreatment, year: Int) -> some View {
        let items = expenses(forYear: year, treatment: treatment)
        let total = items.reduce(0) { $0 + $1.amount }
        DisclosureGroup {
            if items.isEmpty {
                Text("Keine Einträge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { expense in
                    HStack {
                        Text(expense.title.isEmpty ? expense.category.label : expense.title)
                            .font(.caption)
                        Spacer()
                        Text(expense.amount.asCurrency)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            LabeledContent(title, value: total.asCurrency)
        }
    }

    /// Steuerreport als echte `.xlsx`-Tabelle: ein Blatt mit allen Einzelausgaben, ein zweites
    /// mit der Jahres-Zusammenfassung (Mieteinnahmen, AfA, Überschuss/Verlust).
    private func xlsxReportURL() -> URL? {
        var expenseRows: [[XLSXExporter.CellValue]] = []
        var summaryRows: [[XLSXExporter.CellValue]] = []

        for year in years.sorted(by: >) {
            for treatment in [TaxTreatment.maintenanceExpense, .otherDeductible, .capitalized] {
                for expense in expenses(forYear: year, treatment: treatment) {
                    let location = [expense.property?.name, expense.unit?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    expenseRows.append([
                        .number(Double(year)),
                        .string(expense.date.asShortDate),
                        .string(expense.title.isEmpty ? expense.category.label : expense.title),
                        .string(treatment.shortLabel),
                        .currency(expense.amount),
                        .string(location)
                    ])
                }
            }
            let result = property.estimatedTaxableResult(forYear: year)
            summaryRows.append([
                .number(Double(year)),
                .currency(property.annualColdRent(forYear: year)),
                .currency(property.maintenanceExpenses(forYear: year)),
                .currency(property.otherDeductibleExpenses(forYear: year)),
                .currency(property.capitalizedExpenses(forYear: year)),
                .currency(property.totalAfa(forYear: year)),
                .currency(result)
            ])
        }

        let expenseSheet = XLSXExporter.Sheet(
            name: "Ausgaben",
            headers: ["Jahr", "Datum", "Bezeichnung", "Steuerart", "Betrag", "Immobilie/Einheit"],
            rows: expenseRows
        )
        let summarySheet = XLSXExporter.Sheet(
            name: "Zusammenfassung",
            headers: ["Jahr", "Mieteinnahmen", "Erhaltungsaufwand", "Sonstige Werbungskosten", "Herstellungskosten", "AfA gesamt", "Überschuss/Verlust"],
            rows: summaryRows
        )
        guard let data = XLSXExporter.data(sheets: [expenseSheet, summarySheet]) else { return nil }
        let yearLabel = showAllYears ? "alle Jahre" : String(selectedYear)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Steuerreport \(property.name) – \(yearLabel).xlsx")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func saveXLSXAsDocument(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let yearLabel = showAllYears ? "alle Jahre" : String(selectedYear)
        let title = "Steuerreport \(property.name) – \(yearLabel)"
        let document = Document(title: title, fileName: "\(title).xlsx", fileExtension: "xlsx", data: data, receiptDate: .now)
        document.property = property
        modelContext.insert(document)
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    return NavigationStack {
        TaxReportView(property: property, initialYear: Calendar.current.component(.year, from: .now))
    }
    .modelContainer(PreviewData.container)
}
