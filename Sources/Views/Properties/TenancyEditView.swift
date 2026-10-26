import SwiftUI
import SwiftData

struct TenancyEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tenant.lastName) private var allTenants: [Tenant]

    let unit: Unit
    let tenancy: Tenancy?

    @State private var selectedTenant: Tenant?
    @State private var creatingNewTenant = false
    @State private var newTenantFirstName = ""
    @State private var newTenantLastName = ""

    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var coldRentText = ""
    @State private var utilityAdvanceText = ""
    @State private var depositText = ""
    @State private var depositReceived = false
    @State private var noticePeriodMonths = 3
    @State private var occupantCount = 1
    @State private var notes = ""

    private var isNew: Bool { tenancy == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mieter") {
                    if creatingNewTenant {
                        TextField("Vorname", text: $newTenantFirstName)
                        TextField("Nachname", text: $newTenantLastName)
                        Button("Vorhandenen Mieter auswählen") {
                            creatingNewTenant = false
                        }
                    } else {
                        Picker("Mieter", selection: $selectedTenant) {
                            Text("Bitte wählen").tag(Optional<Tenant>.none)
                            ForEach(allTenants) { tenant in
                                Text(tenant.fullName).tag(Optional(tenant))
                            }
                        }
                        Button("Neuen Mieter anlegen") {
                            creatingNewTenant = true
                            selectedTenant = nil
                        }
                    }
                }

                Section {
                    DatePicker("Beginn", selection: $startDate, displayedComponents: .date)
                    Toggle("Befristet / beendet", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ende", selection: $endDate, displayedComponents: .date)
                    }
                    Stepper("Kündigungsfrist: \(noticePeriodMonths) Monat\(noticePeriodMonths == 1 ? "" : "e")", value: $noticePeriodMonths, in: 0...12)
                    Stepper("Personenzahl: \(occupantCount)", value: $occupantCount, in: 1...20)
                } header: {
                    Text("Laufzeit")
                } footer: {
                    if let overlapping = overlappingTenancy {
                        Text("Achtung: überschneidet sich mit dem Mietverhältnis von \(overlapping.tenant?.fullName ?? "einem anderen Mieter") (\(overlapping.startDate.asShortDate) – \(overlapping.endDate?.asShortDate ?? "laufend")) in derselben Einheit.")
                            .foregroundStyle(Theme.statusWarning)
                    }
                }

                Section("Miete") {
                    TextField("Kaltmiete (€)", text: $coldRentText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Nebenkostenvorauszahlung (€)", text: $utilityAdvanceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section("Kaution") {
                    TextField("Kaution (€)", text: $depositText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Kaution erhalten", isOn: $depositReceived)
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !isNew {
                    Section {
                        Button("Mietvertrag löschen", role: .destructive) {
                            deleteTenancy()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Mietvertrag anlegen" : "Mietvertrag bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 480, idealHeight: 640, maxHeight: 780)
            #endif
        }
    }

    /// Ein anderes Mietverhältnis derselben Einheit, dessen Laufzeit sich mit den aktuell
    /// eingegebenen Werten überschneidet – rein informativ, blockiert das Speichern nicht
    /// (z.B. für Korrekturbuchungen oder bewusst überlappende Übergaben).
    private var overlappingTenancy: Tenancy? {
        let candidateEnd = hasEndDate ? endDate : Date.distantFuture
        guard candidateEnd >= startDate else { return nil }
        return (unit.tenancies ?? []).first { other in
            guard other.persistentModelID != tenancy?.persistentModelID else { return false }
            let otherEnd = other.endDate ?? Date.distantFuture
            return max(startDate, other.startDate) <= min(candidateEnd, otherEnd)
        }
    }

    private var canSave: Bool {
        if creatingNewTenant {
            return !newTenantFirstName.isEmpty || !newTenantLastName.isEmpty
        }
        return selectedTenant != nil
    }

    private func loadExistingValues() {
        if let tenancy {
            selectedTenant = tenancy.tenant
            startDate = tenancy.startDate
            if let end = tenancy.endDate {
                hasEndDate = true
                endDate = end
            }
            coldRentText = tenancy.coldRent == 0 ? "" : String(tenancy.coldRent)
            utilityAdvanceText = tenancy.utilityAdvance == 0 ? "" : String(tenancy.utilityAdvance)
            depositText = tenancy.deposit == 0 ? "" : String(tenancy.deposit)
            depositReceived = tenancy.depositReceived
            noticePeriodMonths = tenancy.noticePeriodMonths
            occupantCount = tenancy.occupantCount
            notes = tenancy.notes
        } else if allTenants.isEmpty {
            creatingNewTenant = true
        }
    }

    private func save() {
        let coldRent = Double(coldRentText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let utilityAdvance = Double(utilityAdvanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let deposit = Double(depositText.replacingOccurrences(of: ",", with: ".")) ?? 0

        let tenant: Tenant
        if creatingNewTenant {
            tenant = Tenant(firstName: newTenantFirstName, lastName: newTenantLastName)
            modelContext.insert(tenant)
        } else if let selectedTenant {
            tenant = selectedTenant
        } else {
            return
        }

        if let tenancy {
            tenancy.tenant = tenant
            tenancy.startDate = startDate
            tenancy.endDate = hasEndDate ? endDate : nil
            tenancy.coldRent = coldRent
            tenancy.utilityAdvance = utilityAdvance
            tenancy.deposit = deposit
            tenancy.depositReceived = depositReceived
            tenancy.noticePeriodMonths = noticePeriodMonths
            tenancy.occupantCount = occupantCount
            tenancy.notes = notes
        } else {
            let newTenancy = Tenancy(
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                coldRent: coldRent,
                utilityAdvance: utilityAdvance,
                deposit: deposit,
                depositReceived: depositReceived,
                noticePeriodMonths: noticePeriodMonths,
                occupantCount: occupantCount,
                notes: notes
            )
            newTenancy.unit = unit
            newTenancy.tenant = tenant
            modelContext.insert(newTenancy)
        }
        dismiss()
    }

    private func deleteTenancy() {
        if let tenancy {
            modelContext.delete(tenancy)
        }
        dismiss()
    }
}

#Preview {
    TenancyEditView(unit: Unit(name: "1. OG"), tenancy: nil)
        .modelContainer(PreviewData.container)
}
