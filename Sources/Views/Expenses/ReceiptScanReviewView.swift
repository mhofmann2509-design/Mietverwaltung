import SwiftUI
import SwiftData

/// Trägt einen frisch gescannten und per OCR ausgewerteten Beleg bis zur Anzeige von
/// `ReceiptScanReviewView` (als `sheet(item:)`) – wird von `ExpenseListView` und
/// `HerstellungskostenListView` gemeinsam genutzt.
struct PendingReceiptScan: Identifiable {
    let id = UUID()
    let data: Data
    let fileExtension: String
    let result: ReceiptScanResult
}

/// Review-Formular für einen gescannten Kassenbon/eine gescannte Rechnung: die OCR-Vorschläge für
/// Datum, Betrag und Bezeichnung lassen sich prüfen und korrigieren, bevor daraus eine Ausgabe
/// (Werbungskosten) oder ein Wirtschaftsgut (Möbel/Herstellungskosten) angelegt wird – der Scan
/// wird dabei als benannter, verknüpfter Beleg abgelegt (siehe `Document`).
struct ReceiptScanReviewView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case expense, asset

        var id: String { rawValue }

        var label: String {
            switch self {
            case .expense: return "Ausgabe (Werbungskosten)"
            case .asset: return "Wirtschaftsgut (Möbel/Herstellungskosten)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.name) private var properties: [Property]

    let scanData: Data
    let scanFileExtension: String
    let result: ReceiptScanResult
    /// Legt die Art bereits fest (z.B. beim Start aus der Herstellungskosten-Liste) – ohne
    /// Vorgabe kann der Nutzer frei wählen.
    var fixedKind: Kind? = nil

    @State private var kind: Kind = .expense
    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var selectedProperty: Property?
    @State private var selectedUnit: Unit?

    @State private var category: ExpenseCategory = .maintenance
    @State private var taxTreatment: TaxTreatment = .maintenanceExpense
    @State private var vatRateText = ""

    @State private var assetCategory: AssetCategory = .furniture
    @State private var usefulLifeYears = 10

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if fixedKind == nil {
                        Picker("Art", selection: $kind) {
                            ForEach(Kind.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }
                    TextField("Bezeichnung", text: $title)
                    TextField("Betrag (€)", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Beleg")
                } footer: {
                    Text("Aus dem Scan erkannte Werte – bitte vor dem Sichern prüfen.")
                }

                if kind == .expense {
                    Section("Steuerliche Einordnung") {
                        Picker("Kategorie", selection: $category) {
                            ForEach(ExpenseCategory.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                        .onChange(of: category) { _, newValue in
                            taxTreatment = newValue.defaultTaxTreatment
                        }
                        Picker("Steuerliche Behandlung", selection: $taxTreatment) {
                            ForEach(TaxTreatment.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                        if taxTreatment == .maintenanceExpense {
                            TextField("Umsatzsteuersatz (%)", text: $vatRateText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                    }
                } else {
                    Section("Wirtschaftsgut") {
                        Picker("Art", selection: $assetCategory) {
                            ForEach(AssetCategory.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                        .onChange(of: assetCategory) { _, newValue in
                            usefulLifeYears = newValue.defaultUsefulLifeYears
                        }
                        Stepper("Nutzungsdauer: \(usefulLifeYears) Jahre", value: $usefulLifeYears, in: 1...50)
                    }
                }

                Section("Zuordnung") {
                    Picker("Immobilie", selection: $selectedProperty) {
                        Text("Keine").tag(Optional<Property>.none)
                        ForEach(properties) { property in
                            Text(property.name).tag(Optional(property))
                        }
                    }
                    if let selectedProperty {
                        Picker("Einheit", selection: $selectedUnit) {
                            Text("Ganze Immobilie").tag(Optional<Unit>.none)
                            ForEach(selectedProperty.units ?? []) { unit in
                                Text(unit.name).tag(Optional(unit))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Beleg prüfen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { save() }
                        .disabled(amountText.isEmpty)
                }
            }
            .onAppear(perform: loadInitialValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 420, idealHeight: 560, maxHeight: 780)
            #endif
        }
    }

    private func loadInitialValues() {
        if let fixedKind { kind = fixedKind }
        title = result.vendor ?? ""
        amountText = result.amount.map { String($0) } ?? ""
        date = result.date ?? .now
        usefulLifeYears = assetCategory.defaultUsefulLifeYears
    }

    private func save() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let document = Document(
            title: documentTitle(amount: amount),
            fileName: documentFileName(amount: amount),
            fileExtension: scanFileExtension,
            data: scanData,
            receiptDate: date
        )

        switch kind {
        case .expense:
            let vatRate = taxTreatment == .maintenanceExpense ? Double(vatRateText.replacingOccurrences(of: ",", with: ".")) : nil
            let expense = Expense(date: date, amount: amount, category: category, title: title, taxTreatment: taxTreatment)
            expense.property = selectedProperty
            expense.unit = selectedUnit
            expense.vatRatePercent = vatRate
            modelContext.insert(expense)
            document.expense = expense
        case .asset:
            let asset = DepreciableAsset(name: title, category: assetCategory, cost: amount, usefulLifeYears: usefulLifeYears, placedInServiceDate: date)
            asset.property = selectedProperty
            asset.unit = selectedUnit
            modelContext.insert(asset)
            document.depreciableAsset = asset
        }

        modelContext.insert(document)
        dismiss()
    }

    /// Benennt den abgelegten Beleg sprechend nach Datum, Betrag und Bezeichnung, statt den
    /// generischen Dateinamen des Scans zu übernehmen.
    private func documentTitle(amount: Double) -> String {
        let titlePart = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Beleg" : title
        return "\(date.asShortDate) – \(amount.asCurrency) – \(titlePart)"
    }

    private func documentFileName(amount: Double) -> String {
        let isoDate = ISO8601DateFormatter().string(from: date).prefix(10)
        let safeTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Beleg" : title
        let sanitized = safeTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(isoDate)_\(sanitized).\(scanFileExtension)"
    }
}

#Preview {
    ReceiptScanReviewView(
        scanData: Data(),
        scanFileExtension: "jpg",
        result: ReceiptScanResult(date: .now, amount: 42.5, vendor: "Baumarkt Beispiel")
    )
    .modelContainer(PreviewData.container)
}
