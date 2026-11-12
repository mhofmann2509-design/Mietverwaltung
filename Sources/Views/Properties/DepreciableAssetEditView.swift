import SwiftUI
import SwiftData

struct DepreciableAssetEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.name) private var properties: [Property]

    let initialProperty: Property?
    let initialUnit: Unit?
    let asset: DepreciableAsset?

    @State private var name = ""
    @State private var category: AssetCategory = .furniture
    @State private var costText = ""
    @State private var usefulLifeYears = 13
    @State private var placedInServiceDate = Date.now
    @State private var notes = ""
    @State private var selectedProperty: Property?
    @State private var selectedUnit: Unit?
    @State private var isUsed = false
    @State private var estimatedValueText = ""
    @State private var isCoRented = false
    @State private var vatRateText = ""
    @State private var showingDeleteConfirmation = false

    init(property: Property? = nil, unit: Unit? = nil, asset: DepreciableAsset?) {
        self.initialProperty = property
        self.initialUnit = unit
        self.asset = asset
    }

    private var isNew: Bool { asset == nil }

    /// Die für GWG-Prüfung und AfA maßgebliche Bemessungsgrundlage im Formular: bei gebraucht
    /// erworbenen Wirtschaftsgütern der angesetzte Zeitwert, sonst die Anschaffungskosten.
    private var effectiveBasis: Double {
        if isUsed {
            return estimatedValueText.parsedDecimal ?? 0
        }
        return costText.parsedDecimal ?? 0
    }

    /// Wie `DepreciableAsset.gwgNetBasis`: ohne Angabe 19 % bei neuen, 0 % bei gebrauchten Gütern.
    private var vatRate: Double {
        vatRateText.parsedDecimal ?? (isUsed ? 0 : 19)
    }

    private var isGWG: Bool {
        guard category != .improvement, effectiveBasis > 0 else { return false }
        return ((effectiveBasis / (1 + vatRate / 100)) * 100).rounded() <= DepreciableAsset.gwgThreshold * 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Wirtschaftsgut") {
                    TextField("Bezeichnung (z.B. Einbauküche)", text: $name)
                    Picker("Art", selection: $category) {
                        ForEach(AssetCategory.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .onChange(of: category) { _, newValue in
                        if isNew {
                            usefulLifeYears = newValue.defaultUsefulLifeYears
                        }
                    }
                }

                Section {
                    TextField(isUsed ? "Ursprünglicher Kaufpreis (falls bekannt, optional)" : "Anschaffungs-/Herstellungskosten (€)", text: $costText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    if category != .improvement {
                        Toggle("Gebraucht erworben", isOn: $isUsed)
                        if isUsed {
                            TextField("Zeitwert bei Anschaffung (€)", text: $estimatedValueText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                    }
                    if category != .improvement {
                        TextField(isUsed ? "Enthaltene USt. (%, privat gekauft: 0)" : "Enthaltene USt. (%, leer = 19)", text: $vatRateText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    DatePicker("Anschaffung/Fertigstellung", selection: $placedInServiceDate, displayedComponents: .date)
                    if isGWG {
                        LabeledContent("Sofortabzug (GWG)", value: String(Calendar.current.component(.year, from: placedInServiceDate)))
                            .foregroundStyle(Theme.statusWarning)
                    } else if category == .improvement {
                        if let rate = selectedProperty?.afaRatePercent {
                            LabeledContent("AfA-Satz lt. Gebäude", value: rate.asPercent)
                            if let cost = costText.parsedDecimal, cost > 0 {
                                LabeledContent("Jährliche Abschreibung", value: (cost * rate / 100).asCurrency)
                            }
                        } else {
                            Text("Bitte zuerst eine Immobilie zuordnen – der AfA-Satz richtet sich nach deren Gebäude-AfA.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Stepper("Nutzungsdauer: \(usefulLifeYears) Jahre", value: $usefulLifeYears, in: 1...80)
                        if effectiveBasis > 0, usefulLifeYears > 0 {
                            LabeledContent("Jährliche Abschreibung", value: (effectiveBasis / Double(usefulLifeYears)).asCurrency)
                        }
                    }
                } header: {
                    Text("Kosten & Abschreibung")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if category == .improvement {
                            Text("Herstellungskosten erhöhen die Bemessungsgrundlage der Gebäude-AfA und werden mit demselben Satz abgeschrieben wie das Gebäude selbst (ggf. verkürzt durch ein Restnutzungsdauergutachten, einstellbar bei der Immobilie) – keine eigene Nutzungsdauer.")
                        } else {
                            Text("Geringwertige Wirtschaftsgüter bis \(Int(DepreciableAsset.gwgThreshold)) € netto werden nach §6 Abs. 2 EStG automatisch im Anschaffungsjahr sofort in voller Höhe (brutto) abgezogen, statt über die Nutzungsdauer verteilt.")
                            if isUsed {
                                Text("Bei gebraucht erworbenen Wirtschaftsgütern ist der angesetzte Zeitwert bei Anschaffung maßgeblich für GWG-Prüfung und AfA – nicht der ursprüngliche Neupreis. Dieser Zeitwert wird einmalig angesetzt; die AfA für die folgenden Jahre berechnet sich danach automatisch.")
                            }
                        }
                    }
                }

                Section {
                    Picker("Immobilie", selection: $selectedProperty) {
                        Text("Keine").tag(Optional<Property>.none)
                        ForEach(properties) { property in
                            Text(property.name).tag(Optional(property))
                        }
                    }
                    if let selectedProperty {
                        Picker("Einheit", selection: $selectedUnit) {
                            Text("Ganze Immobilie").tag(Optional<Unit>.none)
                            ForEach(selectedProperty.units ?? []) { unit in
                                Text(unit.name).tag(Optional(unit))
                            }
                        }
                    }
                    if category != .improvement {
                        Toggle("Mitvermietet", isOn: $isCoRented)
                    }
                } header: {
                    Text("Zuordnung")
                } footer: {
                    if category != .improvement {
                        Text("„Mitvermietet“ markiert Wirtschaftsgüter, die zusammen mit der Einheit vermietet werden (Möblierungszuschlag) – unabhängig davon, welcher Einheit sie zugeordnet sind.")
                    }
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !isNew {
                    Section {
                        Button("Wirtschaftsgut löschen", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .confirmationDialog("Wirtschaftsgut löschen?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                            Button("Endgültig löschen", role: .destructive) {
                                if let asset { DepreciableAsset.delete(asset, context: modelContext) }
                                dismiss()
                            }
                            Button("Abbrechen", role: .cancel) {}
                        } message: {
                            Text(asset?.deletionWarning ?? "")
                        }
                    }
                }

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle(isNew ? "Wirtschaftsgut erfassen" : "Wirtschaftsgut bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(name.isEmpty || selectedProperty == nil || !validationMessages.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 480, idealHeight: 600, maxHeight: 780)
            #endif
        }
    }

    private func loadExistingValues() {
        selectedProperty = asset?.property ?? initialProperty
        selectedUnit = asset?.unit ?? initialUnit
        guard let asset else { return }
        name = asset.name
        category = asset.category
        costText = asset.cost == 0 ? "" : String(asset.cost)
        usefulLifeYears = asset.usefulLifeYears
        placedInServiceDate = asset.placedInServiceDate
        notes = asset.notes
        isUsed = asset.isUsed
        estimatedValueText = asset.estimatedValueAtAcquisition == 0 ? "" : String(asset.estimatedValueAtAcquisition)
        isCoRented = asset.isCoRented
        vatRateText = asset.vatRatePercent.map { String($0) } ?? ""
    }

    private var validationMessages: [String] {
        (isUsed
            ? [FormValidation.number(estimatedValueText, "Zeitwert bei Anschaffung", .positive, required: true),
               FormValidation.number(costText, "Ursprünglicher Kaufpreis")]
            : [FormValidation.number(costText, "Anschaffungs-/Herstellungskosten", .positive, required: true)]
         + [FormValidation.number(vatRateText, "Enthaltene USt.", .percent)]).compactMap { $0 }
    }

    private func save() {
        let cost = costText.parsedDecimal ?? 0
        let estimatedValue = isUsed ? (estimatedValueText.parsedDecimal ?? 0) : 0

        if let asset {
            asset.name = name
            asset.category = category
            asset.cost = cost
            asset.usefulLifeYears = usefulLifeYears
            asset.placedInServiceDate = placedInServiceDate
            asset.notes = notes
            asset.property = selectedProperty
            asset.unit = selectedUnit
            asset.isUsed = isUsed
            asset.estimatedValueAtAcquisition = estimatedValue
            asset.isCoRented = isCoRented
            asset.vatRatePercent = vatRateText.parsedDecimal
        } else {
            let newAsset = DepreciableAsset(name: name, category: category, cost: cost, usefulLifeYears: usefulLifeYears, placedInServiceDate: placedInServiceDate, notes: notes, isUsed: isUsed, estimatedValueAtAcquisition: estimatedValue, isCoRented: isCoRented)
            newAsset.vatRatePercent = vatRateText.parsedDecimal
            newAsset.property = selectedProperty
            newAsset.unit = selectedUnit
            modelContext.insert(newAsset)
        }
        dismiss()
    }
}

#Preview {
    DepreciableAssetEditView(property: Property(name: "Musterstraße 1"), unit: nil, asset: nil)
        .modelContainer(PreviewData.container)
}
