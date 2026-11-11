import SwiftUI

extension LineItemDraft {
    /// Zeilen mit ausgefüllter Kostenart, aber ungültigem oder nicht-positivem Betrag – würden
    /// beim Sichern sonst stillschweigend auf 0 gesetzt und verworfen, ohne Hinweis an den Nutzer.
    /// Negative oder Null-Beträge sind für eine Kostenart fachlich nicht vorgesehen.
    static func invalidEntries(in items: [LineItemDraft]) -> [LineItemDraft] {
        items.filter { item in
            let trimmedType = item.costType.trimmingCharacters(in: .whitespaces)
            guard !trimmedType.isEmpty else { return false }
            guard let amount = item.amountText.parsedDecimal else { return true }
            return amount <= 0
        }
    }

    static func total(of items: [LineItemDraft], apportionableOnly: Bool = false) -> Double {
        items.filter { !apportionableOnly || $0.isApportionable }.reduce(0) { $0 + ($1.amountText.parsedDecimal ?? 0) }
    }
}

/// Wiederverwendbare Eingabe der Kostenarten-Liste – von der Nebenkostenabrechnung
/// (`UtilityStatementEditView`) und dem Wirtschaftsplan (`WirtschaftsplanEditView`) identisch
/// genutzt: Zeilen bearbeiten/löschen/hinzufügen, Summen und ein Hinweis auf Zeilen mit
/// ungültigem oder nicht-positivem Betrag. Wird innerhalb einer `Form`-`Section` des jeweiligen
/// Formulars eingebettet, das Kopf-/Fußzeilentext bleibt dort (leicht unterschiedlicher Wortlaut).
struct LineItemsEditor: View {
    @Binding var lineItems: [LineItemDraft]
    /// z.B. „lt. Hausverwaltung“ oder „lt. Wirtschaftsplan“, für die Summenzeile.
    let totalLabel: String

    private var lineItemsTotal: Double { LineItemDraft.total(of: lineItems) }

    private var apportionableTotal: Double { LineItemDraft.total(of: lineItems, apportionableOnly: true) }

    private var invalidEntries: [LineItemDraft] {
        LineItemDraft.invalidEntries(in: lineItems)
    }

    var body: some View {
        ForEach($lineItems) { $item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Kostenart (z.B. Heizung)", text: $item.costType)
                    TextField("Betrag (€)", text: $item.amountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(maxWidth: 110)
                        .multilineTextAlignment(.trailing)
                }
                if let key = item.allocationKeyLabel, !key.isEmpty {
                    Text("Umlageschlüssel lt. Hausverwaltung: \(key)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Toggle("Umlagefähig", isOn: $item.isApportionable)
                    .font(.caption)
            }
        }
        .onDelete { offsets in
            lineItems.remove(atOffsets: offsets)
        }

        Button {
            lineItems.append(LineItemDraft(costType: "", amountText: ""))
        } label: {
            Label("Kostenart hinzufügen", systemImage: "plus")
        }

        if !invalidEntries.isEmpty {
            Text("Ungültiger oder nicht positiver Betrag bei: \(invalidEntries.map { $0.costType }.joined(separator: ", ")). Bitte korrigieren oder entfernen, bevor gesichert werden kann.")
                .font(.caption)
                .foregroundStyle(Theme.statusCritical)
        }

        LabeledContent("Summe \(totalLabel)", value: lineItemsTotal.asCurrency)
        LabeledContent("Davon umlagefähig", value: apportionableTotal.asCurrency)
    }
}
