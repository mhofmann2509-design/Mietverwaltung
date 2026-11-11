import SwiftUI
import SwiftData

/// Erfassung/Bearbeitung einer einzelnen Fahrt zum Vermietungsobjekt, siehe `TravelExpense`.
struct TravelExpenseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let entry: TravelExpense?

    @State private var date = Date.now
    @State private var purpose = ""
    @State private var kilometersText = ""
    @State private var rateText = "0,30"

    private var isNew: Bool { entry == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("Anlass / Zweck", text: $purpose)
                    TextField("Kilometer (Hin- und Rückfahrt)", text: $kilometersText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("€ / km", text: $rateText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Fahrt")
                } footer: {
                    Text("Tatsächlich gefahrene Strecke (Hin- und Rückfahrt), nicht nur die einfache Entfernung – bei nur gelegentlichen Besuchen zur Besichtigung, Verwaltung oder Instandhaltung, nicht bei dauerhafter Präsenz vor Ort.")
                }

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle(isNew ? "Fahrt hinzufügen" : "Fahrt bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!validationMessages.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 480, minHeight: 320, idealHeight: 380)
            #endif
        }
    }

    private func loadExistingValues() {
        guard let entry else { return }
        date = entry.date
        purpose = entry.purpose
        kilometersText = String(entry.kilometers)
        rateText = String(entry.ratePerKilometer)
    }

    private var validationMessages: [String] {
        [
            FormValidation.number(kilometersText, "Kilometer", .positive, required: true),
            FormValidation.number(rateText, "€ / km", .range(0...10))
        ].compactMap { $0 }
    }

    private func save() {
        let kilometers = kilometersText.parsedDecimal ?? 0
        let rate = rateText.parsedDecimal ?? 0.30

        if let entry {
            entry.date = date
            entry.purpose = purpose
            entry.kilometers = kilometers
            entry.ratePerKilometer = rate
        } else {
            let newEntry = TravelExpense(date: date, purpose: purpose, kilometers: kilometers, ratePerKilometer: rate)
            newEntry.property = property
            modelContext.insert(newEntry)
        }
        dismiss()
    }
}

#Preview {
    TravelExpenseEditView(property: Property(), entry: nil)
        .modelContainer(PreviewData.container)
}
