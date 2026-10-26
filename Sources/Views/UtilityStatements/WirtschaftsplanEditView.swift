import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Erfasst den Wirtschaftsplan der Hausverwaltung – die Kosten-**Prognose** für ein Jahr, in
/// derselben Struktur (Kostenarten, umlagefähig/nicht) wie die tatsächliche Abrechnung
/// (`UtilityStatementEditView`), aber als eigenständiges Dokument ohne Zeitraum/Umlageschlüssel,
/// da daraus keine Mieterschreiben erzeugt werden.
struct WirtschaftsplanEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let plan: WirtschaftsplanStatement?

    private struct PendingImport: Identifiable {
        let id = UUID()
        let candidates: [LineItemDraft]
        let sourceDescription: String
    }

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var propertyTaxText = ""
    @State private var reserveFundAccountInfo = ""
    @State private var notes = ""
    @State private var lineItems: [LineItemDraft] = [LineItemDraft(costType: "", amountText: "")]
    @State private var showingReceiptImporter = false
    @State private var showingFileImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importErrorMessage: String?

    private var isNew: Bool { plan == nil }

    private var apportionableTotal: Double {
        lineItems.filter { $0.isApportionable }.reduce(0) { $0 + (Double($1.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) }
    }

    private var propertyTax: Double {
        Double(propertyTaxText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool {
        LineItemDraft.invalidEntries(in: lineItems).isEmpty
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
                    Text("Beleg-Foto: Kostenart und Betrag werden per Texterkennung direkt auf dem Gerät erkannt (keine Cloud). Excel-Liste: bitte zuvor als CSV exportieren (Spalten: Kostenart;Betrag;Umlagefähig). Erkannte Positionen werden vor der Übernahme zur Kontrolle angezeigt.")
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
            .fileImporter(isPresented: $showingReceiptImporter, allowedContentTypes: [.image]) { result in
                handleReceiptImport(result)
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                handleFileImport(result)
            }
            .sheet(item: $pendingImport) { pending in
                LineItemImportReviewView(candidates: pending.candidates, sourceDescription: pending.sourceDescription) { confirmed in
                    lineItems.removeAll { $0.costType.isEmpty && $0.amountText.isEmpty }
                    lineItems.append(contentsOf: confirmed)
                }
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
            #if os(macOS)
            .frame(minWidth: 520, idealWidth: 600, maxWidth: 720, minHeight: 500, idealHeight: 660, maxHeight: 820)
            #endif
        }
    }

    private func handleReceiptImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importErrorMessage = "Die Bilddatei konnte nicht gelesen werden."
            return
        }
        let candidates = ReceiptOCR.recognizeLineItems(from: data)
        pendingImport = PendingImport(candidates: candidates, sourceDescription: "aus dem gescannten Beleg")
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            importErrorMessage = "Die Datei konnte nicht gelesen werden. Bitte als CSV exportieren (eine echte .xlsx-Datei kann nicht direkt gelesen werden)."
            return
        }
        let candidates = CSVImporter.parseLineItems(from: text)
        pendingImport = PendingImport(candidates: candidates, sourceDescription: "aus der importierten Datei")
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

        for draft in lineItems {
            let costType = draft.costType.trimmingCharacters(in: .whitespaces)
            guard let amount = Double(draft.amountText.replacingOccurrences(of: ",", with: ".")), amount > 0, !costType.isEmpty else { continue }
            let lineItem = WirtschaftsplanLineItem(costType: costType, amount: amount, isApportionable: draft.isApportionable, allocationKeyLabel: draft.allocationKeyLabel ?? "")
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
