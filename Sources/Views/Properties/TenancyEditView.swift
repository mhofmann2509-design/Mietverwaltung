import SwiftUI
import SwiftData

/// Eine in Bearbeitung befindliche Staffelmiet-Stufe – vor dem Speichern nur als Entwurf
/// gehalten, analog zu `LineItemDraft` bei den Nebenkosten-Positionen.
private struct RentStepDraft: Identifiable {
    let id = UUID()
    var effectiveDate: Date
    var coldRentText: String
}

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
    @State private var hasDepositReturnedAt = false
    @State private var depositReturnedAt = Date.now
    @State private var noticePeriodMonths = 3
    @State private var occupantCount = 1
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    @State private var contractType: TenancyContractType = .standard
    @State private var hasLastRentIncreaseDate = false
    @State private var lastRentIncreaseDate = Date.now
    @State private var hasLastIndexAdjustmentDate = false
    @State private var lastIndexAdjustmentDate = Date.now
    @State private var rentStepDrafts: [RentStepDraft] = []

    @State private var hasModernizationAnnouncedAt = false
    @State private var modernizationAnnouncedAt = Date.now
    @State private var hasModernizationIncreaseDeclaredAt = false
    @State private var modernizationIncreaseDeclaredAt = Date.now

    private var isNew: Bool { tenancy == nil }

    /// Live-Vorschau der Mieterhöhungs-Frist/-Möglichkeit anhand der aktuellen Formular-Eingabe
    /// (noch bevor gespeichert wird) – nutzt dieselbe Berechnung wie `RemindersEngine`.
    private var rentIncreaseAdvice: RentIncreaseAdvisor.Advice {
        RentIncreaseAdvisor.advice(
            contractType: contractType,
            startDate: startDate,
            lastRentIncreaseDate: hasLastRentIncreaseDate ? lastRentIncreaseDate : nil,
            lastIndexAdjustmentDate: hasLastIndexAdjustmentDate ? lastIndexAdjustmentDate : nil,
            upcomingStaffelDates: rentStepDrafts.map(\.effectiveDate)
        )
    }

    /// Kombiniert die beiden Modernisierungs-Hinweise (§ 555c/§ 559b BGB) zu einem Fließtext –
    /// zeigt nur das, was anhand der aktuell gesetzten Daten berechnet werden kann.
    private var modernizationFooterText: String {
        var parts: [String] = []
        if hasModernizationAnnouncedAt, let earliestStart = RentIncreaseAdvisor.modernizationEarliestStartDate(announcedAt: modernizationAnnouncedAt) {
            parts.append("Frühester Beginn der Maßnahme (§ 555c BGB, 3 Monate nach Ankündigung): \(earliestStart.asShortDate).")
        }
        if hasModernizationIncreaseDeclaredAt, let effectiveDate = RentIncreaseAdvisor.modernizationIncreaseEffectiveDate(declaredAt: modernizationIncreaseDeclaredAt) {
            parts.append("Erhöhte Miete zu entrichten ab (§ 559b Abs. 2 BGB, Beginn des 3. Monats nach Zugang): \(effectiveDate.asShortDate).")
        }
        if parts.isEmpty {
            parts.append("Nur bei einer Modernisierungsmieterhöhung relevant (§ 555c/§ 559b BGB), zusätzlich zur regulären Mieterhöhung oben möglich.")
        }
        return parts.joined(separator: " ")
    }

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

                Section {
                    Picker("Vertragsart", selection: $contractType) {
                        ForEach(TenancyContractType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }

                    switch contractType {
                    case .standard:
                        Toggle("Letzte Mieterhöhung erfasst", isOn: $hasLastRentIncreaseDate)
                        if hasLastRentIncreaseDate {
                            DatePicker("Letzte Mieterhöhung", selection: $lastRentIncreaseDate, displayedComponents: .date)
                        }
                    case .index:
                        Toggle("Letzte Indexanpassung erfasst", isOn: $hasLastIndexAdjustmentDate)
                        if hasLastIndexAdjustmentDate {
                            DatePicker("Letzte Indexanpassung", selection: $lastIndexAdjustmentDate, displayedComponents: .date)
                        }
                    case .staffel:
                        ForEach($rentStepDrafts) { $draft in
                            HStack {
                                DatePicker("Stufe ab", selection: $draft.effectiveDate, displayedComponents: .date)
                                    .labelsHidden()
                                TextField("Kaltmiete (€)", text: $draft.coldRentText)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                            }
                        }
                        .onDelete { rentStepDrafts.remove(atOffsets: $0) }
                        Button("Stufe hinzufügen") {
                            rentStepDrafts.append(RentStepDraft(effectiveDate: .now, coldRentText: ""))
                        }
                    }
                } header: {
                    Text("Mietvertragsart")
                } footer: {
                    Text(rentIncreaseAdvice.nextPossibleDate.map { "\(rentIncreaseAdvice.hint) Nächstmöglicher Termin: \($0.asShortDate)." } ?? rentIncreaseAdvice.hint)
                }

                Section {
                    TextField("Kaution (€)", text: $depositText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Kaution erhalten", isOn: $depositReceived)
                    if hasEndDate {
                        Toggle("Kaution zurückgezahlt", isOn: $hasDepositReturnedAt)
                        if hasDepositReturnedAt {
                            DatePicker("Rückzahlung am", selection: $depositReturnedAt, displayedComponents: .date)
                        }
                    }
                } header: {
                    Text("Kaution")
                } footer: {
                    if hasEndDate && !hasDepositReturnedAt {
                        Text("Keine feste gesetzliche Frist – die Rechtsprechung sieht i.d.R. bis zu sechs Monate nach Mietende als übliche Obergrenze für die Abrechnung an.")
                    }
                }

                Section {
                    Toggle("Modernisierung angekündigt", isOn: $hasModernizationAnnouncedAt)
                    if hasModernizationAnnouncedAt {
                        DatePicker("Ankündigung vom", selection: $modernizationAnnouncedAt, displayedComponents: .date)
                    }
                    Toggle("Mieterhöhungserklärung nach Modernisierung zugegangen", isOn: $hasModernizationIncreaseDeclaredAt)
                    if hasModernizationIncreaseDeclaredAt {
                        DatePicker("Zugegangen am", selection: $modernizationIncreaseDeclaredAt, displayedComponents: .date)
                    }
                } header: {
                    Text("Modernisierung")
                } footer: {
                    Text(modernizationFooterText)
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                ValidationMessagesSection(messages: validationMessages)

                if !isNew {
                    Section {
                        Button("Mietvertrag löschen", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .confirmationDialog("Mietvertrag löschen?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                            Button("Endgültig löschen", role: .destructive) { deleteTenancy() }
                            Button("Abbrechen", role: .cancel) {}
                        } message: {
                            Text("Alle erfassten Mietzahlungen (\(tenancy?.payments?.count ?? 0)), Mietstaffeln und zugeordneten Dokumente dieses Mietvertrags werden mitgelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.")
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

    private var validationMessages: [String] {
        var messages: [String?] = [
            FormValidation.dateOrder(start: startDate, end: hasEndDate ? endDate : nil, endLabel: "Ende des Mietverhältnisses"),
            FormValidation.number(coldRentText, "Kaltmiete"),
            FormValidation.number(utilityAdvanceText, "Nebenkostenvorauszahlung"),
            FormValidation.number(depositText, "Kaution")
        ]
        if contractType == .staffel {
            messages += rentStepDrafts.map { FormValidation.number($0.coldRentText, "Kaltmiete der Staffelstufe ab \($0.effectiveDate.asShortDate)", required: true) }
        }
        return messages.compactMap { $0 }
    }

    private var canSave: Bool {
        guard validationMessages.isEmpty else { return false }
        if creatingNewTenant {
            return !newTenantFirstName.trimmingCharacters(in: .whitespaces).isEmpty || !newTenantLastName.trimmingCharacters(in: .whitespaces).isEmpty
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
            if let date = tenancy.depositReturnedAt {
                hasDepositReturnedAt = true
                depositReturnedAt = date
            }
            noticePeriodMonths = tenancy.noticePeriodMonths
            occupantCount = tenancy.occupantCount
            notes = tenancy.notes
            contractType = tenancy.contractType
            if let date = tenancy.lastRentIncreaseDate {
                hasLastRentIncreaseDate = true
                lastRentIncreaseDate = date
            }
            if let date = tenancy.lastIndexAdjustmentDate {
                hasLastIndexAdjustmentDate = true
                lastIndexAdjustmentDate = date
            }
            rentStepDrafts = (tenancy.rentSteps ?? [])
                .sorted { $0.effectiveDate < $1.effectiveDate }
                .map { RentStepDraft(effectiveDate: $0.effectiveDate, coldRentText: String($0.coldRent)) }
            if let date = tenancy.modernizationAnnouncedAt {
                hasModernizationAnnouncedAt = true
                modernizationAnnouncedAt = date
            }
            if let date = tenancy.modernizationIncreaseDeclaredAt {
                hasModernizationIncreaseDeclaredAt = true
                modernizationIncreaseDeclaredAt = date
            }
        } else if allTenants.isEmpty {
            creatingNewTenant = true
        }
    }

    private func save() {
        let tenantChoice: FormSaving.TenancyFormValues.TenantChoice?
        if creatingNewTenant {
            tenantChoice = .new(firstName: newTenantFirstName, lastName: newTenantLastName)
        } else {
            tenantChoice = selectedTenant.map { .existing($0) }
        }
        let values = FormSaving.TenancyFormValues(
            tenant: tenantChoice,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            coldRentText: coldRentText,
            utilityAdvanceText: utilityAdvanceText,
            depositText: depositText,
            depositReceived: depositReceived,
            depositReturnedAt: hasDepositReturnedAt ? depositReturnedAt : nil,
            noticePeriodMonths: noticePeriodMonths,
            occupantCount: occupantCount,
            notes: notes,
            contractType: contractType,
            lastRentIncreaseDate: hasLastRentIncreaseDate ? lastRentIncreaseDate : nil,
            lastIndexAdjustmentDate: hasLastIndexAdjustmentDate ? lastIndexAdjustmentDate : nil,
            modernizationAnnouncedAt: hasModernizationAnnouncedAt ? modernizationAnnouncedAt : nil,
            modernizationIncreaseDeclaredAt: hasModernizationIncreaseDeclaredAt ? modernizationIncreaseDeclaredAt : nil,
            rentSteps: rentStepDrafts.map { ($0.effectiveDate, $0.coldRentText) }
        )
        guard FormSaving.saveTenancy(values, existing: tenancy, unit: unit, context: modelContext) != nil else { return }
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
