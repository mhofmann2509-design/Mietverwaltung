import SwiftUI
import SwiftData

/// WEG-Verwaltung einer Immobilie: Hausgeld je Einheit (Vorschlag aus dem Wirtschaftsplan,
/// anpassbar), Hausgeldkonto mit Abrechnungsspitze und Sonderumlagen.
struct WEGView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var property: Property

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var planEditRequest: PlanEditRequest?
    @State private var levyEditRequest: LevyEditRequest?

    private struct PlanEditRequest: Identifiable {
        let id = UUID()
        let unit: Unit
        let plan: HausgeldPlan?
        let proposal: HausgeldCalculator.Proposal?
        let sourceYear: Int?
    }

    private struct LevyEditRequest: Identifiable {
        let id = UUID()
        let levy: SpecialLevy?
    }

    private var units: [Unit] { (property.units ?? []).sorted { $0.name < $1.name } }

    private var wirtschaftsplan: WirtschaftsplanStatement? {
        (property.wirtschaftsplaene ?? []).first { $0.year == year }
    }

    private var jahresabrechnung: UtilityStatement? {
        (property.utilityStatements ?? []).first { $0.year == year }
    }

    private var levies: [SpecialLevy] {
        (property.specialLevies ?? []).sorted { $0.dueDate > $1.dueDate }
    }

    var body: some View {
        List {
            Section {
                Stepper("Jahr: \(String(year))", value: $year, in: 2000...2100)
            } footer: {
                Text("Das Hausgeld wird hier nur als Soll/Ist-Konto geführt. Steuerlich zählen wie bisher die Kosten laut WEG-Jahresabrechnung (Nebenkostenabrechnung) – sonst würden sie doppelt angesetzt.")
            }

            if units.isEmpty {
                Section("Hausgeld") {
                    Text("Für diese Immobilie sind noch keine Einheiten angelegt.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(units) { unit in
                unitSection(unit)
            }

            levySection
        }
        .navigationTitle("WEG: Hausgeld & Sonderumlagen")
        .sheet(item: $planEditRequest) { request in
            HausgeldPlanEditView(unit: request.unit, plan: request.plan, proposal: request.proposal, sourceYear: request.sourceYear, defaultValidFrom: Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now)
        }
        .sheet(item: $levyEditRequest) { request in
            SpecialLevyEditView(property: property, levy: request.levy)
        }
    }

    // MARK: - Hausgeld je Einheit

    @ViewBuilder
    private func unitSection(_ unit: Unit) -> some View {
        let calendar = Calendar.current
        let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? .now
        let account = HausgeldCalculator.account(for: unit, year: year, upTo: yearEnd)
        let currentPlan = HausgeldCalculator.plan(for: unit, on: yearEnd)

        Section {
            if let currentPlan {
                LabeledContent("Hausgeld monatlich", value: currentPlan.monthlyAmount.asCurrency)
                LabeledContent("davon umlagefähig", value: currentPlan.apportionableMonthly.asCurrency)
                LabeledContent("davon Erhaltungsrücklage", value: currentPlan.reserveFundMonthly.asCurrency)
                Text(planOriginText(currentPlan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Hausgeld anpassen") {
                    planEditRequest = PlanEditRequest(unit: unit, plan: currentPlan, proposal: nil, sourceYear: currentPlan.sourcePlanYear)
                }
            } else {
                Text("Noch kein Hausgeld hinterlegt.")
                    .foregroundStyle(.secondary)
            }

            if let wirtschaftsplan {
                let proposal = HausgeldCalculator.proposal(from: wirtschaftsplan, for: unit)
                Button {
                    planEditRequest = PlanEditRequest(unit: unit, plan: nil, proposal: proposal, sourceYear: wirtschaftsplan.year)
                } label: {
                    Label("Aus Wirtschaftsplan \(String(wirtschaftsplan.year)) übernehmen (\(proposal.monthlyAmount.asCurrency)/Monat)", systemImage: "arrow.down.doc")
                }
            } else if currentPlan == nil {
                Button("Hausgeld von Hand eintragen") {
                    planEditRequest = PlanEditRequest(unit: unit, plan: nil, proposal: nil, sourceYear: nil)
                }
            }

            if account.due > 0 {
                DisclosureGroup("Zahlungen \(String(year)): \(account.paid.asCurrency) von \(account.due.asCurrency)") {
                    ForEach(1...12, id: \.self) { month in
                        monthRow(unit: unit, month: month)
                    }
                }
                LabeledContent("Offen", value: max(0, account.balance).asCurrency)
                    .foregroundStyle(account.balance > 0.005 ? Theme.statusCritical : .secondary)
            }

            if let jahresabrechnung, account.paid > 0 {
                let settlement = HausgeldCalculator.settlement(for: unit, statement: jahresabrechnung)
                LabeledContent("Kostenanteil lt. Jahresabrechnung", value: settlement.actualCosts.asCurrency)
                LabeledContent(settlement.balance >= 0 ? "Abrechnungsspitze (Nachzahlung)" : "Abrechnungsspitze (Guthaben)", value: abs(settlement.balance).asCurrency)
                    .fontWeight(.semibold)
            }
        } header: {
            Text("Hausgeld · \(unit.name)")
        } footer: {
            Text("Anteil der Einheit: \(String(format: "%.2f", HausgeldCalculator.share(of: unit).value * 100)) % nach \(HausgeldCalculator.share(of: unit).basis).")
        }
    }

    private func planOriginText(_ plan: HausgeldPlan) -> String {
        var text = "Gültig ab \(plan.validFrom.asShortDate)"
        if let source = plan.sourcePlanYear {
            text += " · aus Wirtschaftsplan \(String(source))"
            if plan.isManuallyAdjusted { text += ", angepasst" }
        } else {
            text += " · von Hand eingetragen"
        }
        return text
    }

    @ViewBuilder
    private func monthRow(unit: Unit, month: Int) -> some View {
        if let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) {
            let payment = HausgeldCalculator.payment(for: unit, inMonthOf: date)
            let due = payment?.amountDue ?? HausgeldCalculator.monthlyDue(for: unit, inMonthOf: date)
            if due > 0 {
                HStack {
                    Text(date.asMonthYear)
                    Spacer()
                    Text(due.asCurrency).foregroundStyle(.secondary)
                    Button {
                        if payment?.isPaid == true {
                            payment?.markUnpaid()
                        } else {
                            HausgeldCalculator.markPaid(unit: unit, month: date, context: modelContext)
                        }
                    } label: {
                        Image(systemName: payment?.isPaid == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(payment?.isPaid == true ? Theme.statusGood : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(payment?.isPaid == true ? "Als offen markieren" : "Als bezahlt markieren")
                }
            }
        }
    }

    // MARK: - Sonderumlagen

    private var levySection: some View {
        Section {
            ForEach(levies) { levy in
                Button {
                    levyEditRequest = LevyEditRequest(levy: levy)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(levy.title.isEmpty ? "Sonderumlage" : levy.title)
                            Text("\(levy.taxTreatment.shortLabel) · fällig \(levy.dueDate.asShortDate)" + (levy.unit.map { " · \($0.name)" } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(levy.amount.asCurrency)
                            Text(levy.isPaid ? "Bezahlt" : (levy.isOverdue() ? "Überfällig" : "Offen"))
                                .font(.caption)
                                .foregroundStyle(levy.isPaid ? Theme.statusGood : (levy.isOverdue() ? Theme.statusCritical : Theme.statusWarning))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(levies[index]) }
            }
            Button {
                levyEditRequest = LevyEditRequest(levy: nil)
            } label: {
                Label("Sonderumlage erfassen", systemImage: "plus")
            }
        } header: {
            Text("Sonderumlagen")
        } footer: {
            Text("Sobald eine Sonderumlage als bezahlt erfasst ist, wird sie als Ausgabe mit der gewählten steuerlichen Behandlung gebucht und fließt so in Werbungskosten, Herstellungskosten/AfA, 15-%-Grenze und Cashflow ein.")
        }
    }
}

// MARK: - Hausgeld bearbeiten

struct HausgeldPlanEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let unit: Unit
    let plan: HausgeldPlan?
    let proposal: HausgeldCalculator.Proposal?
    let sourceYear: Int?
    let defaultValidFrom: Date

    @State private var validFrom = Date.now
    @State private var monthlyText = ""
    @State private var apportionableText = ""
    @State private var reserveText = ""
    @State private var notes = ""

    private var validationMessages: [String] {
        [
            FormValidation.number(monthlyText, "Hausgeld monatlich", .positive, required: true),
            FormValidation.number(apportionableText, "davon umlagefähig"),
            FormValidation.number(reserveText, "davon Erhaltungsrücklage"),
            partsExceedTotal ? "Umlagefähiger Anteil und Rücklage sind zusammen höher als das Hausgeld." : nil,
        ].compactMap { $0 }
    }

    private var partsExceedTotal: Bool {
        guard let total = monthlyText.parsedDecimal else { return false }
        return (apportionableText.parsedDecimal ?? 0) + (reserveText.parsedDecimal ?? 0) > total + 0.005
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Gültig ab", selection: $validFrom, displayedComponents: .date)
                    TextField("Hausgeld monatlich (€)", text: $monthlyText)
                    TextField("davon umlagefähig (€)", text: $apportionableText)
                    TextField("davon Erhaltungsrücklage (€)", text: $reserveText)
                } header: {
                    Text(unit.name)
                } footer: {
                    if let proposal {
                        Text("Vorschlag aus dem Wirtschaftsplan \(sourceYear.map { String($0) } ?? ""): Anteil \(String(format: "%.2f", proposal.unitShare * 100)) % nach \(proposal.shareBasis), Jahreswerte ÷ 12. Die Werte lassen sich anpassen, z.B. auf den Betrag laut Einzelwirtschaftsplan.")
                    }
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                }
                ValidationMessagesSection(messages: validationMessages)
                if let plan {
                    Section {
                        Button("Hausgeld-Eintrag löschen", role: .destructive) {
                            modelContext.delete(plan)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(plan == nil ? "Hausgeld festlegen" : "Hausgeld anpassen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(!validationMessages.isEmpty)
                }
            }
            .onAppear(perform: load)
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 380)
            #endif
        }
    }

    private func load() {
        if let plan {
            validFrom = plan.validFrom
            monthlyText = String(plan.monthlyAmount)
            apportionableText = String(plan.apportionableMonthly)
            reserveText = String(plan.reserveFundMonthly)
            notes = plan.notes
        } else {
            validFrom = defaultValidFrom
            if let proposal {
                monthlyText = String(proposal.monthlyAmount)
                apportionableText = String(proposal.apportionableMonthly)
                reserveText = String(proposal.reserveFundMonthly)
            }
        }
    }

    private func save() {
        HausgeldPlanSaving.save(
            unit: unit, existing: plan, proposal: proposal, sourceYear: sourceYear, validFrom: validFrom,
            monthly: monthlyText.parsedDecimal ?? 0, apportionable: apportionableText.parsedDecimal ?? 0,
            reserve: reserveText.parsedDecimal ?? 0, notes: notes, context: modelContext
        )
        dismiss()
    }
}

/// Speichern eines Hausgeld-Plans – ausgelagert, damit testbar.
enum HausgeldPlanSaving {
    @discardableResult
    static func save(unit: Unit, existing: HausgeldPlan?, proposal: HausgeldCalculator.Proposal?, sourceYear: Int?, validFrom: Date, monthly: Double, apportionable: Double, reserve: Double, notes: String, context: ModelContext) -> HausgeldPlan {
        let target: HausgeldPlan
        if let existing {
            target = existing
        } else {
            target = HausgeldPlan()
            target.unit = unit
            target.sourcePlanYear = proposal == nil ? nil : sourceYear
            context.insert(target)
        }
        let changedFromProposal = proposal.map {
            abs($0.monthlyAmount - monthly) > 0.005 || abs($0.apportionableMonthly - apportionable) > 0.005 || abs($0.reserveFundMonthly - reserve) > 0.005
        }
        if existing == nil {
            target.isManuallyAdjusted = changedFromProposal ?? false
        } else if target.sourcePlanYear != nil,
                  abs(target.monthlyAmount - monthly) > 0.005 || abs(target.apportionableMonthly - apportionable) > 0.005 || abs(target.reserveFundMonthly - reserve) > 0.005 {
            target.isManuallyAdjusted = true
        }
        target.validFrom = validFrom
        target.monthlyAmount = monthly
        target.apportionableMonthly = apportionable
        target.reserveFundMonthly = reserve
        target.notes = notes
        return target
    }
}

// MARK: - Sonderumlage bearbeiten

struct SpecialLevyEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let levy: SpecialLevy?

    @State private var title = ""
    @State private var purpose = ""
    @State private var amountText = ""
    @State private var dueDate = Date.now
    @State private var hasResolutionDate = false
    @State private var resolutionDate = Date.now
    @State private var selectedUnit: Unit?
    @State private var selectedMeeting: OwnersMeetingEvent?
    @State private var isPaid = false
    @State private var paidDate = Date.now
    @State private var paidAmountText = ""
    @State private var taxTreatment: TaxTreatment = .maintenanceExpense
    @State private var deductibleText = ""
    @State private var notes = ""

    private var validationMessages: [String] {
        [
            FormValidation.required(title, "Bezeichnung"),
            FormValidation.number(amountText, "Betrag", .positive, required: true),
            isPaid ? FormValidation.number(paidAmountText, "Gezahlter Betrag") : nil,
            FormValidation.number(deductibleText, "Steuerlich anzusetzender Betrag"),
        ].compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sonderumlage") {
                    TextField("Bezeichnung (z.B. Dachsanierung)", text: $title)
                    TextField("Zweck/Beschlussinhalt", text: $purpose, axis: .vertical)
                    TextField("Betrag (€)", text: $amountText)
                    DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    Picker("Einheit", selection: $selectedUnit) {
                        Text("Ganze Immobilie").tag(Unit?.none)
                        ForEach((property.units ?? []).sorted { $0.name < $1.name }) { unit in
                            Text(unit.name).tag(Unit?.some(unit))
                        }
                    }
                }

                Section("Beschluss") {
                    Toggle("Beschlussdatum angeben", isOn: $hasResolutionDate)
                    if hasResolutionDate {
                        DatePicker("Beschlossen am", selection: $resolutionDate, displayedComponents: .date)
                    }
                    Picker("Eigentümerversammlung", selection: $selectedMeeting) {
                        Text("Keine").tag(OwnersMeetingEvent?.none)
                        ForEach((property.ownersMeetings ?? []).sorted { $0.date > $1.date }) { meeting in
                            Text("\(meeting.title) · \(meeting.date.asShortDate)").tag(OwnersMeetingEvent?.some(meeting))
                        }
                    }
                }

                Section("Zahlung") {
                    Toggle("Bezahlt", isOn: $isPaid)
                    if isPaid {
                        DatePicker("Bezahlt am", selection: $paidDate, displayedComponents: .date)
                        TextField("Gezahlter Betrag (€, leer = voller Betrag)", text: $paidAmountText)
                    }
                }

                Section {
                    Picker("Steuerliche Behandlung", selection: $taxTreatment) {
                        ForEach(TaxTreatment.allCases) { treatment in
                            Text(treatment.label).tag(treatment)
                        }
                    }
                    TextField("Steuerlich anzusetzender Betrag (€, optional)", text: $deductibleText)
                } header: {
                    Text("Steuer laut Abrechnung")
                } footer: {
                    Text("Wie in der Abrechnung der Hausverwaltung angegeben. Fließt ein Teil in die Erhaltungsrücklage, hier nur den abziehbaren Betrag eintragen. Nach dem Bezahlen wird eine Ausgabe mit dieser Behandlung gebucht; Herstellungskosten lassen sich dort wie gewohnt aktivieren.")
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                }

                ValidationMessagesSection(messages: validationMessages)

                if let levy {
                    Section {
                        Button("Sonderumlage löschen", role: .destructive) {
                            modelContext.delete(levy)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(levy == nil ? "Sonderumlage erfassen" : "Sonderumlage bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(!validationMessages.isEmpty)
                }
            }
            .onAppear(perform: load)
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
        }
    }

    private func load() {
        guard let levy else { return }
        title = levy.title
        purpose = levy.purpose
        amountText = String(levy.amount)
        dueDate = levy.dueDate
        hasResolutionDate = levy.resolutionDate != nil
        resolutionDate = levy.resolutionDate ?? .now
        selectedUnit = levy.unit
        selectedMeeting = levy.ownersMeeting
        isPaid = levy.isPaid
        paidDate = levy.paidDate ?? .now
        paidAmountText = levy.paidAmount.map { String($0) } ?? ""
        taxTreatment = levy.taxTreatment
        deductibleText = levy.deductibleAmountOverride.map { String($0) } ?? ""
        notes = levy.notes
    }

    private func save() {
        let target = levy ?? {
            let new = SpecialLevy()
            new.property = property
            modelContext.insert(new)
            return new
        }()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.purpose = purpose
        target.amount = amountText.parsedDecimal ?? 0
        target.dueDate = dueDate
        target.resolutionDate = hasResolutionDate ? resolutionDate : nil
        target.unit = selectedUnit
        target.ownersMeeting = selectedMeeting
        target.paidDate = isPaid ? paidDate : nil
        target.paidAmount = isPaid ? paidAmountText.parsedDecimal : nil
        target.taxTreatment = taxTreatment
        target.deductibleAmountOverride = deductibleText.parsedDecimal
        target.notes = notes
        target.syncExpense(context: modelContext)
        dismiss()
    }
}
