import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExpenseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.name) private var properties: [Property]

    let expense: Expense?

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var category: ExpenseCategory = .other
    @State private var taxTreatment: TaxTreatment = ExpenseCategory.other.defaultTaxTreatment
    @State private var selectedProperty: Property?
    @State private var selectedUnit: Unit?
    @State private var vatRateText = ""
    @State private var notes = ""
    @State private var showingFileImporter = false
    @State private var pendingDocumentTitle = ""

    private var isNew: Bool { expense == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ausgabe") {
                    TextField("Bezeichnung", text: $title)
                    TextField("Betrag (€)", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Picker("Kategorie", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .onChange(of: category) { _, newValue in
                        if isNew {
                            taxTreatment = newValue.defaultTaxTreatment
                        }
                    }
                }

                Section {
                    Picker("Steuerliche Behandlung", selection: $taxTreatment) {
                        ForEach(TaxTreatment.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                } footer: {
                    switch taxTreatment {
                    case .maintenanceExpense:
                        Text("Reparatur/Instandhaltung – sofort in voller Höhe abziehbar.")
                    case .otherDeductible:
                        Text("Sofort abziehbare Werbungskosten, z.B. Versicherung, Steuern, Finanzierungszinsen, Verwaltung.")
                    case .capitalized:
                        Text("Herstellungskosten werden nicht sofort abgezogen, sondern über die Nutzungsdauer abgeschrieben. Erfasse dafür unten bei der Immobilie bzw. Einheit ein Wirtschaftsgut (AfA).")
                    case .notDeductible:
                        Text("Wird bei der Steuerberechnung nicht berücksichtigt.")
                    }
                }

                if taxTreatment == .maintenanceExpense {
                    Section {
                        TextField("Umsatzsteuersatz (%)", text: $vatRateText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } footer: {
                        Text("Nur für die 15-%-Grenze relevant: Ohne Angabe gilt der Netto-Betrag dieser Position als nicht ermittelbar.")
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

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let expense {
                    Section("Belege") {
                        ForEach(expense.documents ?? []) { document in
                            Text(document.title.isEmpty ? document.fileName : document.title)
                        }
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Beleg hinzufügen", systemImage: "paperclip")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Neue Ausgabe" : "Ausgabe bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(amountText.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image, .data]) { result in
                handleFileImport(result)
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 420, idealHeight: 560, maxHeight: 780)
            #endif
        }
    }

    private func loadExistingValues() {
        guard let expense else { return }
        title = expense.title
        amountText = expense.amount == 0 ? "" : String(expense.amount)
        date = expense.date
        category = expense.category
        taxTreatment = expense.taxTreatment
        selectedProperty = expense.property
        selectedUnit = expense.unit
        vatRateText = expense.vatRatePercent.map { String($0) } ?? ""
        notes = expense.notes
    }

    private func save() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let vatRate = taxTreatment == .maintenanceExpense ? Double(vatRateText.replacingOccurrences(of: ",", with: ".")) : nil

        if let expense {
            expense.title = title
            expense.amount = amount
            expense.date = date
            expense.category = category
            expense.taxTreatment = taxTreatment
            expense.property = selectedProperty
            expense.unit = selectedUnit
            expense.vatRatePercent = vatRate
            expense.notes = notes
        } else {
            let newExpense = Expense(date: date, amount: amount, category: category, title: title, notes: notes, taxTreatment: taxTreatment)
            newExpense.property = selectedProperty
            newExpense.unit = selectedUnit
            newExpense.vatRatePercent = vatRate
            modelContext.insert(newExpense)
        }
        dismiss()
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard let expense, case .success(let url) = result else { return }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else { return }
        let document = Document(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            data: data
        )
        document.expense = expense
        modelContext.insert(document)
    }
}

#Preview {
    ExpenseEditView(expense: nil)
        .modelContainer(PreviewData.container)
}
