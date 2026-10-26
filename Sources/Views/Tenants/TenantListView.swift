import SwiftUI
import SwiftData

struct TenantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tenant.lastName) private var tenants: [Tenant]
    @State private var showingAddSheet = false
    @State private var searchText = ""

    private var filteredTenants: [Tenant] {
        guard !searchText.isEmpty else { return tenants }
        return tenants.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filteredTenants) { tenant in
                NavigationLink(value: tenant) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tenant.fullName).font(.headline)
                            if let tenancy = tenant.activeTenancy, let unit = tenancy.unit {
                                Text("\(unit.property?.name ?? "") · \(unit.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Seit \(tenancy.startDate.asShortDate)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if let lastTenancy = (tenant.tenancies ?? []).sorted(by: { $0.startDate > $1.startDate }).first {
                                Text("\(lastTenancy.unit?.property?.name ?? "") · \(lastTenancy.unit?.name ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(lastTenancy.startDate.asShortDate) – \(lastTenancy.endDate?.asShortDate ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Kein Mietverhältnis")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if tenant.activeTenancy != nil {
                            StatusBadge(label: "Aktueller Mieter", tone: .good)
                        }
                    }
                }
            }
            .onDelete(perform: deleteTenants)
        }
        .themedScrollBackground()
        .navigationTitle("Mieter")
        .searchable(text: $searchText, prompt: "Mieter durchsuchen")
        .navigationDestination(for: Tenant.self) { tenant in
            TenantDetailView(tenant: tenant)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Mieter hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            TenantEditView(tenant: nil)
        }
        .overlay {
            if tenants.isEmpty {
                ContentUnavailableView(
                    "Keine Mieter",
                    systemImage: "person.2",
                    description: Text("Füge deinen ersten Mieter hinzu.")
                )
            } else if filteredTenants.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func deleteTenants(at offsets: IndexSet) {
        for index in offsets {
            guard let originalIndex = tenants.firstIndex(where: { $0.id == filteredTenants[index].id }) else { continue }
            modelContext.delete(tenants[originalIndex])
        }
    }
}

#Preview {
    NavigationStack {
        TenantListView()
    }
    .modelContainer(PreviewData.container)
}
