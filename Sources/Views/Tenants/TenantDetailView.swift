import SwiftUI
import SwiftData

struct TenantDetailView: View {
    @Bindable var tenant: Tenant
    @State private var showingEditSheet = false

    var body: some View {
        List {
            Section("Kontakt") {
                if tenant.salutation != .unspecified {
                    LabeledContent("Anrede", value: tenant.salutation.label)
                }
                if !tenant.email.isEmpty {
                    LabeledContent("E-Mail", value: tenant.email)
                }
                if !tenant.phone.isEmpty {
                    LabeledContent("Telefon", value: tenant.phone)
                }
                if !tenant.notes.isEmpty {
                    Text(tenant.notes).foregroundStyle(.secondary)
                }
            }

            if !tenant.previousAddress.isEmpty {
                Section("Frühere Anschrift") {
                    Text(tenant.previousAddress)
                }
            }

            if !tenant.bankAccountHolder.isEmpty || !tenant.iban.isEmpty {
                Section("Bankverbindung") {
                    if !tenant.bankAccountHolder.isEmpty {
                        LabeledContent("Kontoinhaber", value: tenant.bankAccountHolder)
                    }
                    if !tenant.iban.isEmpty {
                        LabeledContent("IBAN", value: tenant.iban)
                    }
                    if !tenant.bic.isEmpty {
                        LabeledContent("BIC", value: tenant.bic)
                    }
                }
            }

            Section("Mietverhältnisse") {
                let tenancies = (tenant.tenancies ?? []).sorted { $0.startDate > $1.startDate }
                if tenancies.isEmpty {
                    Text("Keine Mietverhältnisse.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tenancies) { tenancy in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(tenancy.unit?.property?.name ?? "") · \(tenancy.unit?.name ?? "")")
                                    .font(.headline)
                                Text("\(tenancy.startDate.asShortDate) – \(tenancy.endDate?.asShortDate ?? "laufend")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(tenancy.totalMonthlyAmount(forMonthContaining: .now).asCurrency + "/Monat")
                                    .font(.caption)
                            }
                            Spacer()
                            if tenancy.isActive {
                                Text("Aktueller Mieter")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.statusGood)
                            } else {
                                Text("Ausgezogen \(tenancy.endDate?.asShortDate ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(tenant.fullName)
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
            TenantEditView(tenant: tenant)
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let tenant = (try? context.fetch(FetchDescriptor<Tenant>()))?.first ?? Tenant()
    return NavigationStack {
        TenantDetailView(tenant: tenant)
    }
    .modelContainer(PreviewData.container)
}
