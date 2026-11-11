import SwiftUI
import SwiftData

struct PropertyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Property.name) private var properties: [Property]
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var pendingDeletion: [Property] = []

    private var filteredProperties: [Property] {
        guard !searchText.isEmpty else { return properties }
        return properties.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.city.localizedCaseInsensitiveContains(searchText) ||
            $0.street.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Aktuelle Darlehensrate (monatlich) und Restschuld zum laufenden Jahr – wird bei jedem
    /// Aufruf neu aus Darlehenssumme/Zins/Tilgung berechnet, zeigt also immer den aktuellen Stand.
    private func loanStatus(for property: Property) -> (monthlyRate: Double, remainingBalance: Double)? {
        guard property.loanAmount > 0 else { return nil }
        let year = Calendar.current.component(.year, from: .now)
        guard let breakdown = property.loanBreakdown(forYear: year) else { return nil }
        return (property.annualAnnuity / 12, breakdown.remainingBalance)
    }

    @ViewBuilder
    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }
    private var totalUnits: Int { properties.reduce(0) { $0 + $1.unitCount } }
    private var totalOccupiedUnits: Int { properties.reduce(0) { $0 + $1.occupiedUnitCount } }
    private var totalMonthlyColdRent: Double { properties.reduce(0) { $0 + $1.annualColdRentFromActiveTenancies } / 12 }
    private var totalMonthlyRate: Double { properties.compactMap { loanStatus(for: $0)?.monthlyRate }.reduce(0, +) }
    private var totalRemainingBalance: Double { properties.compactMap { loanStatus(for: $0)?.remainingBalance }.reduce(0, +) }
    private var totalAfaThisYear: Double { properties.reduce(0) { $0 + $1.totalAfaThisYear } }
    private var totalFreeCashFlowThisYear: Double { properties.reduce(0) { $0 + $1.freeCashFlow(forYear: currentYear) } }

    var body: some View {
        List {
            if !properties.isEmpty {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                        KPITile(title: "Immobilien", value: String(properties.count), systemImage: "building.2")
                        KPITile(title: "Einheiten", value: "\(totalOccupiedUnits)/\(totalUnits) vermietet", systemImage: "door.left.hand.open")
                        KPITile(title: "Kaltmiete/Monat", value: totalMonthlyColdRent.asCurrency, systemImage: "eurosign.circle")
                        if totalMonthlyRate > 0 {
                            KPITile(title: "Rate/Monat", value: totalMonthlyRate.asCurrency, systemImage: "banknote")
                            KPITile(title: "Restschuld", value: totalRemainingBalance.asCurrency, systemImage: "banknote")
                        }
                        KPITile(title: "AfA \(String(currentYear))", value: totalAfaThisYear.asCurrency, systemImage: "chart.line.downtrend.xyaxis")
                        KPITile(
                            title: "Freier Cashflow \(String(currentYear))",
                            value: totalFreeCashFlowThisYear.asCurrency,
                            systemImage: totalFreeCashFlowThisYear >= 0 ? "checkmark.circle" : "exclamationmark.circle",
                            valueColor: totalFreeCashFlowThisYear >= 0 ? Theme.statusGood : Theme.statusCritical
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Theme.spacingS)
                } header: {
                    Text("Gesamtübersicht")
                }
            }

            ForEach(filteredProperties) { property in
                NavigationLink(value: property) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(property.name.isEmpty ? property.address : property.name)
                                    .font(.headline)
                                Text(property.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            statBlock(
                                label: "Einheiten",
                                value: "\(property.occupiedUnitCount)/\(property.unitCount) vermietet"
                            )
                            if let loan = loanStatus(for: property) {
                                Spacer()
                                statBlock(label: "Rate/Monat", value: loan.monthlyRate.asCurrency)
                                Spacer()
                                statBlock(label: "Restschuld", value: loan.remainingBalance.asCurrency)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .onDelete(perform: deleteProperties)
        }
        .themedScrollBackground()
        .navigationTitle("Immobilien")
        .searchable(text: $searchText, prompt: "Immobilien durchsuchen")
        // Zentral in ContentView deklariert, siehe dortiger Kommentar.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Immobilie hinzufügen", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "„\(pendingDeletion[0].name)“ löschen?" : "\(pendingDeletion.count) Immobilien löschen?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            titleVisibility: .visible
        ) {
            Button("Endgültig löschen", role: .destructive) {
                pendingDeletion.forEach { modelContext.delete($0) }
                pendingDeletion = []
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text(deletionWarning)
        }
        .sheet(isPresented: $showingAddSheet) {
            PropertyEditView(property: nil)
        }
        .overlay {
            if properties.isEmpty {
                ContentUnavailableView(
                    "Keine Immobilien",
                    systemImage: "building.2",
                    description: Text("Füge deine erste Immobilie hinzu.")
                )
            } else if filteredProperties.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func deleteProperties(at offsets: IndexSet) {
        pendingDeletion = offsets.map { filteredProperties[$0] }
    }

    private var deletionWarning: String {
        let units = pendingDeletion.flatMap { $0.units ?? [] }
        let tenancyCount = units.reduce(0) { $0 + ($1.tenancies?.count ?? 0) }
        let expenseCount = pendingDeletion.reduce(0) { $0 + ($1.expenses?.count ?? 0) }
        let documentCount = pendingDeletion.reduce(0) { $0 + ($1.documents?.count ?? 0) }
        return "Dabei werden auch \(units.count) Einheit(en), \(tenancyCount) Mietverhältnis(se) samt Zahlungen, \(expenseCount) Ausgabe(n), \(documentCount) Dokument(e) sowie alle Abrechnungen, Wirtschaftsgüter und Steuerdaten dieser Immobilie gelöscht. Dieser Schritt kann nicht rückgängig gemacht werden."
    }
}

#Preview {
    NavigationStack {
        PropertyListView()
    }
    .modelContainer(PreviewData.container)
}
