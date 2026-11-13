import SwiftUI
import SwiftData

/// Erfasst den Wirtschaftsplan der Hausverwaltung – die Kosten-**Prognose** für ein Jahr, in
/// derselben Struktur (Kostenarten, umlagefähig/nicht) wie die tatsächliche Abrechnung
/// (`UtilityStatementEditView`), aber als eigenständiges Dokument ohne Zeitraum/Umlageschlüssel,
/// da daraus keine Mieterschreiben erzeugt werden.
struct WirtschaftsplanEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let plan: WirtschaftsplanStatement?

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var propertyTaxText = ""
    @State private var reserveFundAccountInfo = ""
    @State private var notes = ""
    @State private var lineItems: [LineItemDraft] = [LineItemDraft(costType: "", amountText: "")]
    @State private var showingReceiptImporter = false
    @State private var showingFileImporter = false

    private var isNew: Bool { plan == nil }

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
                    Stepper("Jahr: \(String(year))", value: $year, in: 2000...2100)
                } header: {
                    Text("Planjahr")
                } footer: {
                    Text("Das Jahr, für das der Wirtschaftsplan der Hausverwaltung die Kosten prognostiziert.")
                }

                Section {
                    TextField("Grundsteuer (€)", text: $propertyTaxText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Grundsteuer")
                } footer: {
                    Text("Steht meist nicht im Wirtschaftsplan, ist aber nach §2 Nr. 1 BetrKV auf die Mieter umlagefähig – hier selbst eingeben.")
                }

                Section {
                    LineItemsEditor(lineItems: $lineItems, totalLabel: "lt. Wirtschaftsplan")
                    LabeledContent("Umlagefähig gesamt (inkl. Grundsteuer)", value: (apportionableTotal + propertyTax).asCurrency)
                        .font(.headline)
                } header: {
                    Text("Geplante Kostenarten")
                } footer: {
                    Text("Nicht umlagefähige Posten (z.B. Verwaltergebühr, Instandhaltungsrücklage) verbleiben beim Vermieter.")
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
                    TextField("Konto/IBAN und/oder geplante Zuführung", text: $reserveFundAccountInfo, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Instandhaltungsrücklagenkonto bei der Hausverwaltung")
                } footer: {
                    Text("Wie auf dem eingescannten Wirtschaftsplan vermerkt – rein informativ, fließt nicht in die Berechnung ein.")
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isNew ? "Wirtschaftsplan erfassen" : "Wirtschaftsplan bearbeiten")
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
            .frame(minWidth: 520, idealWidth: 600, maxWidth: 720, minHeight: 500, idealHeight: 660, maxHeight: 820)
            #endif
        }
    }

    private func loadExistingValues() {
        if let plan {
            year = plan.year
            propertyTaxText = plan.propertyTaxAmount == 0 ? "" : String(plan.propertyTaxAmount)
            reserveFundAccountInfo = plan.reserveFundAccountInfo
            notes = plan.notes
        }
        guard let plan else { return }
        let existing = (plan.lineItems ?? []).map {
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
        let target: WirtschaftsplanStatement
        if let plan {
            target = plan
            target.year = year
            target.propertyTaxAmount = propertyTax
            target.reserveFundAccountInfo = reserveFundAccountInfo
            target.notes = notes
            for existing in plan.lineItems ?? [] {
                modelContext.delete(existing)
            }
        } else {
            target = WirtschaftsplanStatement(year: year, propertyTaxAmount: propertyTax, notes: notes)
            target.reserveFundAccountInfo = reserveFundAccountInfo
            target.property = property
            modelContext.insert(target)
        }

        for item in LineItemDraft.persistable(lineItems) {
            let lineItem = WirtschaftsplanLineItem(costType: item.costType, amount: item.amount, isApportionable: item.isApportionable, allocationKeyLabel: item.allocationKeyLabel)
            lineItem.statement = target
            modelContext.insert(lineItem)
        }

        dismiss()
    }
}

#Preview {
    WirtschaftsplanEditView(property: Property(name: "Musterstraße 1"), plan: nil)
        .modelContainer(PreviewData.container)
}
