import SwiftUI

/// Zeigt importierte/erkannte Kostenart-Kandidaten (aus OCR-Beleg-Scan oder Excel/CSV-Import)
/// zur Kontrolle an, bevor sie in die Nebenkostenabrechnung übernommen werden – OCR und
/// Dateiimporte können Fehler enthalten, daher keine ungeprüfte automatische Übernahme.
struct LineItemImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State var candidates: [LineItemDraft]
    let sourceDescription: String
    var skippedRowNumbers: [Int] = []
    let onConfirm: ([LineItemDraft]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if !skippedRowNumbers.isEmpty {
                    Section {
                        Label(
                            "\(skippedRowNumbers.count) Zeile(n) ohne lesbare Kostenart oder lesbaren Betrag wurden übersprungen: Zeile \(skippedRowNumbers.map(String.init).joined(separator: ", ")).",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    } footer: {
                        Text("Diese Zeilen bitte in der Datei prüfen oder unten von Hand ergänzen.")
                    }
                }
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Nichts erkannt",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Es konnten keine Kostenarten/Beträge \(sourceDescription) erkannt werden.")
                    )
                } else {
                    Section {
                        ForEach($candidates) { $item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    TextField("Kostenart", text: $item.costType)
                                    TextField("Betrag (€)", text: $item.amountText)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                        .frame(maxWidth: 110)
                                        .multilineTextAlignment(.trailing)
                                }
                                TextField("Umlageschlüssel (optional), z.B. MEA (4)", text: allocationKeyBinding(for: $item))
                                    .font(.caption)
                                Toggle("Umlagefähig", isOn: $item.isApportionable)
                                    .font(.caption)
                            }
                        }
                        .onDelete { offsets in
                            candidates.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text("Erkannte Positionen")
                    } footer: {
                        Text("Bitte prüfen und bei Bedarf korrigieren, bevor du sie übernimmst (\(sourceDescription)).")
                    }
                }
            }
            .navigationTitle("Positionen prüfen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\(candidates.count) übernehmen") {
                        onConfirm(candidates)
                        dismiss()
                    }
                    .disabled(candidates.isEmpty)
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 420, idealHeight: 560, maxHeight: 780)
            #endif
        }
    }

    private func allocationKeyBinding(for item: Binding<LineItemDraft>) -> Binding<String> {
        Binding(
            get: { item.wrappedValue.allocationKeyLabel ?? "" },
            set: { item.wrappedValue.allocationKeyLabel = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview {
    LineItemImportReviewView(
        candidates: [
            LineItemDraft(costType: "Heizung", amountText: "1450,00", allocationKeyLabel: "lt.An (11)"),
            LineItemDraft(costType: "Wasser/Abwasser", amountText: "620,00", allocationKeyLabel: "MEA (4)")
        ],
        sourceDescription: "aus dem gescannten Beleg",
        onConfirm: { _ in }
    )
}
