import SwiftUI
import SwiftData

struct TenantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tenant.lastName) private var tenants: [Tenant]
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var pendingDeletion: [Tenant] = []

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
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Mieter löschen?" : "\(pendingDeletion.count) Mieter löschen?",
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
        pendingDeletion = offsets.map { filteredTenants[$0] }
    }

    private var deletionWarning: String {
        let tenancies = pendingDeletion.flatMap { $0.tenancies ?? [] }
        guard !tenancies.isEmpty else { return "Dieser Schritt kann nicht rückgängig gemacht werden." }
        let places = tenancies.map { "• \($0.unit?.property?.name ?? "–") · \($0.unit?.name ?? "–") (ab \($0.startDate.asShortDate))" }
        return "Mit dem Mieter werden auch diese Mietverhältnisse samt Zahlungen, Mietstaffeln und Dokumenten gelöscht:\n" + places.joined(separator: "\n") + "\n\nDieser Schritt kann nicht rückgängig gemacht werden."
    }
}

#Preview {
    NavigationStack {
        TenantListView()
    }
    .modelContainer(PreviewData.container)
}
