import SwiftUI
import SwiftData

/// Liste der Fahrten zum Vermietungsobjekt (Besichtigung, Verwaltung, Instandhaltung) mit
/// Kilometerpauschale – siehe `TravelExpense`.
struct TravelExpenseListView: View {
    @Bindable var property: Property
    @Environment(\.modelContext) private var context
    @State private var showingAddSheet = false
    @State private var entryToEdit: TravelExpense?

    private var entries: [TravelExpense] {
        (property.travelExpenses ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Keine Fahrten erfasst",
                    systemImage: "car",
                    description: Text("Erfasse Fahrten zur Besichtigung, Verwaltung oder Instandhaltung – abziehbar mit der tatsächlich gefahrenen Strecke (Hin- und Rückfahrt).")
                )
            } else {
                ForEach(entries) { entry in
                    Button {
                        entryToEdit = entry
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.purpose.isEmpty ? "Fahrt" : entry.purpose)
                                    .foregroundStyle(.primary)
                                Text("\(entry.date.asShortDate) · \(Int(entry.kilometers)) km × \(entry.ratePerKilometer.asCurrency)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.amount.asCurrency)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(entries[index]) }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle("Fahrtkosten")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Fahrt hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            TravelExpenseEditView(property: property, entry: nil)
        }
        .sheet(item: $entryToEdit) { entry in
            TravelExpenseEditView(property: property, entry: entry)
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    return NavigationStack {
        TravelExpenseListView(property: property)
    }
    .modelContainer(PreviewData.container)
}
