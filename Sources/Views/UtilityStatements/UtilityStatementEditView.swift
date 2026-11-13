import SwiftUI
import SwiftData

struct UtilityStatementEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let statement: UtilityStatement?
    /// Überschreibt den Standardtitel „Nebenkostenabrechnung erfassen/bearbeiten“ – z.B. wenn das
    /// Formular aus dem Betriebskosten-Reiter der Immobilie heraus geöffnet wird.
    var titleOverride: String? = nil

    /// Nur für eine neue Abrechnung: schnelle Vorbelegung von Beginn/Ende auf Jan–Dez des
    /// gewählten Jahres. Das Jahr selbst ist kein eigenes, speicherbares Feld mehr – es ergibt
    /// sich immer aus `periodEnd` (siehe `UtilityStatement.year`), damit beide nie auseinanderlaufen.
    @State private var quickFillYear = Calendar.current.component(.year, from: .now)
    @State private var periodStart = Date.now
    @State private var periodEnd = Date.now
    @State private var allocationMethod: AllocationMethod = .livingSpace
    @State private var propertyTaxText = ""
    @State private var reserveFundAccountInfo = ""
    @State private var notes = ""
    @State private var lineItems: [LineItemDraft] = [LineItemDraft(costType: "", amountText: "")]
    @State private var showingReceiptImporter = false
    @State private var showingFileImporter = false

    private var isNew: Bool { statement == nil }

    private var apportionableTotal: Double { LineItemDraft.total(of: lineItems, apportionableOnly: true) }

    private var propertyTax: Double {
        propertyTaxText.parsedDecimal ?? 0
    }

    private var canSave: Bool {
        LineItemDraft.invalidEntries(in: lineItems).isEmpty && FormValidation.number(propertyTaxText, "Grundsteuer") == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isNew {
                        Stepper("Jahr: \(String(quickFillYear))", value: $quickFillYear, in: 2000...2100)
                            .onChange(of: quickFillYear) { _, newValue in
                                let calendar = Calendar.current
                                periodStart = calendar.date(from: DateComponents(year: newValue, month: 1, day: 1)) ?? periodStart
                                periodEnd = calendar.date(from: DateComponents(year: newValue, month: 12, day: 31)) ?? periodEnd
                            }
                    } else {
                        LabeledContent("Jahr", value: String(Calendar.current.component(.year, from: periodEnd)))
                    }
                    DatePicker("Beginn", selection: $periodStart, displayedComponents: .date)
                    DatePicker("Ende", selection: $periodEnd, displayedComponents: .date)
                    Picker("Umlageschlüssel", selection: $allocationMethod) {
                        ForEach(AllocationMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                } header: {
                    Text("Abrechnungszeitraum")
                } footer: {
                    Text("Der Zeitraum ist frei wählbar (muss nicht das Kalenderjahr sein) und bestimmt die anteilige Verteilung bei unterjährigem Ein-/Auszug.")
                }

                Section {
                    TextField("Grundsteuer (€)", text: $propertyTaxText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Grundsteuer")
                } footer: {
                    Text("Steht meist nicht im Schreiben der Hausverwaltung, ist aber nach §2 Nr. 1 BetrKV auf die Mieter umlagefähig – hier selbst eingeben.")
                }

                Section {
                    LineItemsEditor(lineItems: $lineItems, totalLabel: "lt. Hausverwaltung")
                    LabeledContent("Umlagefähig gesamt (inkl. Grundsteuer)", value: (apportionableTotal + propertyTax).asCurrency)
                        .font(.headline)
                } header: {
                    Text("Kostenarten lt. Hausverwaltung")
                } footer: {
                    Text("Nicht umlagefähige Posten (z.B. Verwaltergebühr, Instandhaltungsrücklage) verbleiben beim Vermieter und fließen in den freien Cashflow ein, nicht in die Abrechnung der Mieter.")
                }

                Section {
                    Button {
                        showingReceiptImporter = true
                    } label: {
                        Label("Beleg scannen (OCR)", systemImage: "doc.text.viewfinder")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Aus Excel/CSV importieren", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Kostenarten importieren")
                } footer: {
                    Text("Beleg-Foto: Kostenart und Betrag werden per Texterkennung direkt auf dem Gerät erkannt (keine Cloud). Excel/CSV-Liste (Spalten: Kostenart;Betrag;Umlagefähig): echte .xlsx-Dateien werden direkt gelesen, alternativ als CSV exportieren. Erkannte Positionen werden vor der Übernahme zur Kontrolle angezeigt.")
                }

                Section {
                    TextField("Konto/IBAN und/oder Kontostand", text: $reserveFundAccountInfo, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Instandhaltungsrücklagenkonto bei der Hausverwaltung")
                } footer: {
                    Text("Wie auf der eingescannten Abrechnung der Hausverwaltung vermerkt – rein informativ, fließt nicht in die Berechnung ein.")
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(titleOverride ?? (isNew ? "Nebenkostenabrechnung erfassen" : "Nebenkostenabrechnung bearbeiten"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExistingValues)
            .lineItemImport(lineItems: $lineItems, showingReceiptImporter: $showingReceiptImporter, showingFileImporter: $showingFileImporter)
            #if os(macOS)
            .frame(minWidth: 520, idealWidth: 600, maxWidth: 720, minHeight: 540, idealHeight: 720, maxHeight: 860)
            #endif
        }
    }

    private func loadExistingValues() {
        if let statement {
            periodStart = statement.periodStart
            periodEnd = statement.periodEnd
            allocationMethod = statement.allocationMethod
            propertyTaxText = statement.propertyTaxAmount == 0 ? "" : String(statement.propertyTaxAmount)
            reserveFundAccountInfo = statement.reserveFundAccountInfo
            notes = statement.notes
        } else {
            let calendar = Calendar.current
            periodStart = calendar.date(from: DateComponents(year: quickFillYear, month: 1, day: 1)) ?? .now
            periodEnd = calendar.date(from: DateComponents(year: quickFillYear, month: 12, day: 31)) ?? .now
        }
        guard let statement else { return }
        let existing = (statement.lineItems ?? []).map {
            LineItemDraft(
                costType: $0.costType,
                amountText: String($0.amount),
                isApportionable: $0.isApportionable,
                allocationKeyLabel: $0.allocationKeyLabel.isEmpty ? nil : $0.allocationKeyLabel
            )
        }
        if !existing.isEmpty {
            lineItems = existing
        }
    }

    private func save() {
        let target: UtilityStatement
        if let statement {
            target = statement
            target.periodStart = periodStart
            target.periodEnd = periodEnd
            target.allocationMethod = allocationMethod
            target.propertyTaxAmount = propertyTax
            target.reserveFundAccountInfo = reserveFundAccountInfo
            target.notes = notes
            for existing in statement.lineItems ?? [] {
                modelContext.delete(existing)
            }
        } else {
            target = UtilityStatement(propertyTaxAmount: propertyTax, notes: notes, allocationMethod: allocationMethod)
            target.periodStart = periodStart
            target.periodEnd = periodEnd
            target.reserveFundAccountInfo = reserveFundAccountInfo
            target.property = property
            modelContext.insert(target)
        }

        for item in LineItemDraft.persistable(lineItems) {
            let lineItem = UtilityCostLineItem(costType: item.costType, amount: item.amount, isApportionable: item.isApportionable, allocationKeyLabel: item.allocationKeyLabel)
            lineItem.statement = target
            modelContext.insert(lineItem)
        }

        dismiss()
    }
}

#Preview {
    UtilityStatementEditView(property: Property(name: "Musterstraße 1"), statement: nil)
        .modelContainer(PreviewData.container)
}
