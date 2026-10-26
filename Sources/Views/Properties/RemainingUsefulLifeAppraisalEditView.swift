import SwiftUI
import SwiftData

struct RemainingUsefulLifeAppraisalEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var property: Property
    let appraisal: RemainingUsefulLifeAppraisal?

    @State private var constructionYearText = ""
    @State private var valuationDate = Date.now
    @State private var totalUsefulLifeYearsText = "80"
    @State private var roofPoints = 0
    @State private var facadePoints = 0
    @State private var windowsPoints = 0
    @State private var utilityLinesPoints = 0
    @State private var heatingPoints = 0
    @State private var bathroomsPoints = 0
    @State private var interiorPoints = 0
    @State private var floorPlanPoints = 0
    @State private var isCoreRenovation = false
    @State private var notes = ""
    @State private var showingAppliedConfirmation = false

    private var isNew: Bool { appraisal == nil }

    private var totalUsefulLifeYears: Double {
        Double(totalUsefulLifeYearsText.replacingOccurrences(of: ",", with: ".")) ?? 80
    }

    /// Erzeugt aus den aktuellen Formularwerten ein (nicht gespeichertes) Gutachten, um RND und
    /// AfA-Satz schon während der Eingabe live anzuzeigen.
    private var preview: RemainingUsefulLifeAppraisal {
        let draft = RemainingUsefulLifeAppraisal(
            constructionYear: Int(constructionYearText) ?? Calendar.current.component(.year, from: .now),
            valuationDate: valuationDate,
            totalUsefulLifeYears: totalUsefulLifeYears
        )
        draft.roofPoints = roofPoints
        draft.facadePoints = facadePoints
        draft.windowsPoints = windowsPoints
        draft.utilityLinesPoints = utilityLinesPoints
        draft.heatingPoints = heatingPoints
        draft.bathroomsPoints = bathroomsPoints
        draft.interiorPoints = interiorPoints
        draft.floorPlanPoints = floorPlanPoints
        draft.isCoreRenovation = isCoreRenovation
        return draft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Baujahr", text: $constructionYearText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    DatePicker("Bewertungsstichtag", selection: $valuationDate, displayedComponents: .date)
                    TextField("Gesamtnutzungsdauer (Jahre)", text: $totalUsefulLifeYearsText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Kernsanierung (Baujahr = Sanierungsjahr)", isOn: $isCoreRenovation)
                } header: {
                    Text("Gebäude")
                } footer: {
                    Text("Gesamtnutzungsdauer für Wohngebäude lt. Anlage 2 ImmoWertV einheitlich 80 Jahre. Bei Kernsanierung erlaubt das Modell eine RND von bis zu 90 % statt 70 % der Gesamtnutzungsdauer.")
                }

                Section {
                    modernizationStepper("Dach (inkl. Wärmedämmung)", value: $roofPoints, max: RemainingUsefulLifeAppraisal.roofMaxPoints)
                    modernizationStepper("Fassade (Wärmedämmung Außenwände)", value: $facadePoints, max: RemainingUsefulLifeAppraisal.facadeMaxPoints)
                    modernizationStepper("Fenster & Außentüren", value: $windowsPoints, max: RemainingUsefulLifeAppraisal.windowsMaxPoints)
                    modernizationStepper("Leitungssysteme (Strom/Gas/Wasser/Abwasser)", value: $utilityLinesPoints, max: RemainingUsefulLifeAppraisal.utilityLinesMaxPoints)
                    modernizationStepper("Heizungsanlage", value: $heatingPoints, max: RemainingUsefulLifeAppraisal.heatingMaxPoints)
                    modernizationStepper("Bäder", value: $bathroomsPoints, max: RemainingUsefulLifeAppraisal.bathroomsMaxPoints)
                    modernizationStepper("Innenausbau (Decken, Fußböden, Treppen)", value: $interiorPoints, max: RemainingUsefulLifeAppraisal.interiorMaxPoints)
                    modernizationStepper("Grundrissgestaltung", value: $floorPlanPoints, max: RemainingUsefulLifeAppraisal.floorPlanMaxPoints)
                } header: {
                    Text("Modernisierungsgrad je Bauteil")
                } footer: {
                    Text("0 Punkte = nicht modernisiert, Höchstwert = vollständig modernisiert (Anlage 2 ImmoWertV, Tabelle 1).")
                }

                Section {
                    LabeledContent("Modernisierungspunkte gesamt", value: "\(preview.totalModernizationPoints) / 20")
                    LabeledContent("Modernisierungsgrad", value: preview.modernizationGradeLabel)
                    LabeledContent("Gebäudealter zum Stichtag", value: "\(Int(preview.ageYears)) Jahre")
                    LabeledContent("Restnutzungsdauer (RND)", value: "\(Int(preview.remainingUsefulLifeYears.rounded())) Jahre")
                        .font(.headline)
                    LabeledContent("Daraus abgeleiteter AfA-Satz", value: preview.suggestedAfaRatePercent.asPercent)
                        .font(.headline)
                        .foregroundStyle(Theme.statusWarning)

                    Button {
                        applyAsAfaRate()
                    } label: {
                        Label("Als AfA-Satz der Immobilie übernehmen", systemImage: "checkmark.circle")
                    }
                    if showingAppliedConfirmation {
                        Text("Übernommen – der AfA-Satz der Immobilie wurde auf \(preview.suggestedAfaRatePercent.asPercent) gesetzt.")
                            .font(.caption)
                            .foregroundStyle(Theme.statusGood)
                    }
                } header: {
                    Text("Berechnung")
                } footer: {
                    Text("Vereinfachtes Modell nach Anlage 2 ImmoWertV. Für die steuerliche Anerkennung einer verkürzten Nutzungsdauer nach § 7 Abs. 4 Satz 2 EStG ist weiterhin ein Gutachten eines öffentlich bestellten und vereidigten Sachverständigen erforderlich – diese Berechnung ersetzt das nicht, sondern dient nur der eigenen Orientierung.")
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isNew ? "Restnutzungsdauergutachten" : "Gutachten bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 560, idealWidth: 620, maxWidth: 760, minHeight: 620, idealHeight: 820, maxHeight: 960)
            #endif
        }
    }

    @ViewBuilder
    private func modernizationStepper(_ title: String, value: Binding<Int>, max: Int) -> some View {
        Stepper("\(title): \(value.wrappedValue) / \(max)", value: value, in: 0...max)
    }

    private func applyAsAfaRate() {
        property.afaRatePercentOverride = preview.suggestedAfaRatePercent
        showingAppliedConfirmation = true
    }

    private func loadExistingValues() {
        if let appraisal {
            constructionYearText = String(appraisal.constructionYear)
            valuationDate = appraisal.valuationDate
            totalUsefulLifeYearsText = String(appraisal.totalUsefulLifeYears)
            roofPoints = appraisal.roofPoints
            facadePoints = appraisal.facadePoints
            windowsPoints = appraisal.windowsPoints
            utilityLinesPoints = appraisal.utilityLinesPoints
            heatingPoints = appraisal.heatingPoints
            bathroomsPoints = appraisal.bathroomsPoints
            interiorPoints = appraisal.interiorPoints
            floorPlanPoints = appraisal.floorPlanPoints
            isCoreRenovation = appraisal.isCoreRenovation
            notes = appraisal.notes
        } else if let constructionYear = property.constructionYear {
            constructionYearText = String(constructionYear)
        }
    }

    private func save() {
        let target: RemainingUsefulLifeAppraisal
        if let appraisal {
            target = appraisal
        } else {
            target = RemainingUsefulLifeAppraisal()
            target.property = property
            modelContext.insert(target)
        }
        target.constructionYear = Int(constructionYearText) ?? target.constructionYear
        target.valuationDate = valuationDate
        target.totalUsefulLifeYears = totalUsefulLifeYears
        target.roofPoints = roofPoints
        target.facadePoints = facadePoints
        target.windowsPoints = windowsPoints
        target.utilityLinesPoints = utilityLinesPoints
        target.heatingPoints = heatingPoints
        target.bathroomsPoints = bathroomsPoints
        target.interiorPoints = interiorPoints
        target.floorPlanPoints = floorPlanPoints
        target.isCoreRenovation = isCoreRenovation
        target.notes = notes
        dismiss()
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    return RemainingUsefulLifeAppraisalEditView(property: property, appraisal: nil)
        .modelContainer(PreviewData.container)
}
