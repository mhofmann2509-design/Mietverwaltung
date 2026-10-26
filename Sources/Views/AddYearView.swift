import SwiftUI
import SwiftData

/// Kleines Formular, um ein Jahr ohne vorhandene Datensätze vorab in der Seitenleiste anzulegen
/// (z.B. ein kommendes Jahr für Zahlungen, Ausgaben oder Herstellungskosten), statt darauf zu
/// warten, dass automatisch ein erster Datensatz dafür erfasst wird.
struct AddYearView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Schlüssel der Liste, z.B. "payments", "expenses", "improvements".
    let category: String
    let existingYears: [Int]

    @State private var year = Calendar.current.component(.year, from: .now) + 1

    private var alreadyExists: Bool { existingYears.contains(year) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Jahr: \(String(year))", value: $year, in: 1990...2100)
                } footer: {
                    if alreadyExists {
                        Text("Dieses Jahr ist bereits vorhanden.")
                    } else {
                        Text("Legt das Jahr leer in der Seitenleiste an, auch ohne vorhandene Datensätze.")
                    }
                }
            }
            .navigationTitle("Jahr hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { addYear() }
                        .disabled(alreadyExists)
                }
            }
            #if os(macOS)
            .frame(minWidth: 380, idealWidth: 420, maxWidth: 480, minHeight: 180, idealHeight: 200, maxHeight: 260)
            #endif
        }
    }

    private func addYear() {
        modelContext.insert(TrackedYear(category: category, year: year))
        dismiss()
    }
}

#Preview {
    AddYearView(category: "payments", existingYears: [2026, 2025])
        .modelContainer(PreviewData.container)
}
