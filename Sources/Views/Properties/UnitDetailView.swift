import SwiftUI
import SwiftData

struct UnitDetailView: View {
    @Bindable var unit: Unit
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditSheet = false
    @State private var showingTenancySheet = false
    @State private var tenancyToEdit: Tenancy?
    @State private var showingAddAssetSheet = false
    @State private var assetToEdit: DepreciableAsset?

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var furnitureTotalCost: Double {
        (unit.depreciableAssets ?? []).reduce(0) { $0 + $1.cost }
    }

    private var furnitureAnnualDepreciation: Double {
        (unit.depreciableAssets ?? []).reduce(0) { $0 + $1.depreciation(forYear: currentYear) }
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Größe", value: unit.sizeSquareMeters > 0 ? "\(unit.sizeSquareMeters.formatted()) m²" : "–")
                LabeledContent("Zimmer", value: unit.rooms > 0 ? unit.rooms.formatted() : "–")
                if !unit.notes.isEmpty {
                    Text(unit.notes).foregroundStyle(.secondary)
                }
            }

            if !unit.features.isEmpty {
                Section("Ausstattung") {
                    FlowBadges(features: unit.features)
                }
            }

            Section("Mietverhältnis") {
                if let active = unit.activeTenancy {
                    tenancyRow(active)
                } else {
                    Text("Aktuell kein Mieter (Leerstand)")
                        .foregroundStyle(Theme.statusWarning)
                }
                Button {
                    tenancyToEdit = unit.activeTenancy
                    showingTenancySheet = true
                } label: {
                    Label(unit.activeTenancy == nil ? "Mietvertrag anlegen" : "Mietvertrag bearbeiten", systemImage: unit.activeTenancy == nil ? "plus" : "pencil")
                }
            }

            let pastTenancies = unit.sortedTenancies.filter { $0.id != unit.activeTenancy?.id }
            if !pastTenancies.isEmpty {
                Section("Frühere Mietverhältnisse") {
                    ForEach(pastTenancies) { tenancy in
                        tenancyRow(tenancy)
                    }
                }
            }

            Section {
                if (unit.depreciableAssets ?? []).isEmpty {
                    Text("Keine Möblierung erfasst.")
                        .foregroundStyle(.secondary)
                }
                let assets = unit.depreciableAssets ?? []
                ForEach(assets) { asset in
                    Button {
                        assetToEdit = asset
                    } label: {
                        HStack {
                            Image(systemName: asset.category.systemImage)
                            VStack(alignment: .leading) {
                                Text(asset.name).foregroundStyle(.primary)
                                Text("\(asset.cost.asCurrency) · \(asset.usefulLifeYears) Jahre · \(asset.annualDepreciation.asCurrency)/Jahr AfA")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in deleteAssets(assets, at: offsets) }

                Button {
                    showingAddAssetSheet = true
                } label: {
                    Label("Möbel/Einrichtung hinzufügen", systemImage: "plus")
                }

                if furnitureTotalCost > 0 {
                    LabeledContent("Gesamtsumme (Anschaffungskosten)", value: furnitureTotalCost.asCurrency)
                    LabeledContent("AfA gesamt \(String(currentYear))", value: furnitureAnnualDepreciation.asCurrency)
                        .font(.headline)
                }
            } header: {
                Text("Möblierung (AfA)")
            } footer: {
                Text("Z.B. Einbauküche, Möbel – jeweils mit eigener Nutzungsdauer, unabhängig von der Gebäude-AfA.")
            }

            Section("Ausgaben für diese Einheit") {
                let unitExpenses = (unit.expenses ?? []).sorted { $0.date > $1.date }
                if unitExpenses.isEmpty {
                    Text("Keine Ausgaben erfasst.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unitExpenses) { expense in
                        HStack {
                            Text(expense.title.isEmpty ? expense.category.label : expense.title)
                            Spacer()
                            Text(expense.amount.asCurrency)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(unit.name.isEmpty ? "Einheit" : unit.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            UnitEditView(property: unit.property ?? Property(), unit: unit)
        }
        .sheet(isPresented: $showingTenancySheet) {
            TenancyEditView(unit: unit, tenancy: tenancyToEdit)
        }
        .sheet(isPresented: $showingAddAssetSheet) {
            DepreciableAssetEditView(property: unit.property ?? Property(), unit: unit, asset: nil)
        }
        .sheet(item: $assetToEdit) { asset in
            DepreciableAssetEditView(property: unit.property ?? Property(), unit: unit, asset: asset)
        }
    }

    /// Nimmt die beim Rendern tatsächlich angezeigte Reihenfolge entgegen, statt
    /// `unit.depreciableAssets` ein zweites Mal selbst abzufragen – `ForEach` und dieser Aufruf
    /// teilen sich dieselbe, einmalig berechnete Liste.
    private func deleteAssets(_ assets: [DepreciableAsset], at offsets: IndexSet) {
        for index in offsets {
            DepreciableAsset.delete(assets[index], context: modelContext)
        }
    }

    @ViewBuilder
    private func tenancyRow(_ tenancy: Tenancy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tenancy.tenant?.fullName ?? "Unbekannter Mieter")
                .font(.headline)
            Text("\(tenancy.startDate.asShortDate) – \(tenancy.endDate?.asShortDate ?? "laufend")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Kaltmiete \(tenancy.coldRent(forMonthContaining: .now).asCurrency) + NK \(tenancy.utilityAdvance.asCurrency) = \(tenancy.totalMonthlyAmount(forMonthContaining: .now).asCurrency)")
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            tenancyToEdit = tenancy
            showingTenancySheet = true
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let unit = (try? context.fetch(FetchDescriptor<Unit>()))?.first ?? Unit()
    return NavigationStack {
        UnitDetailView(unit: unit)
    }
    .modelContainer(PreviewData.container)
}
