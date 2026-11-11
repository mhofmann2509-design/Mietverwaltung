import SwiftUI
import SwiftData

struct UnitEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let unit: Unit?

    @State private var name = ""
    @State private var sizeSquareMeters = ""
    @State private var rooms = ""
    @State private var coOwnershipShare = ""
    @State private var notes = ""
    @State private var selectedFeatures: Set<UnitFeature> = []

    private var isNew: Bool { unit == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung (z.B. 1. OG rechts)", text: $name)
                    TextField("Größe in m²", text: $sizeSquareMeters)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Zimmer", text: $rooms)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Einheit")
                }

                Section {
                    TextField("Miteigentumsanteil (MEA), z.B. 55,34", text: $coOwnershipShare)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Miteigentumsanteil")
                } footer: {
                    Text("Anteil dieser Einheit laut Teilungserklärung, z.B. „55,34“ von insgesamt 1.000 Anteilen am Objekt. Wird benötigt, wenn die Nebenkosten nach MEA statt nach Wohnfläche umgelegt werden.")
                }

                Section("Ausstattung") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(UnitFeature.allCases) { feature in
                            featureChip(feature)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle(isNew ? "Neue Einheit" : "Einheit bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!validationMessages.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 480, idealHeight: 600, maxHeight: 780)
            #endif
        }
    }

    @ViewBuilder
    private func featureChip(_ feature: UnitFeature) -> some View {
        let isSelected = selectedFeatures.contains(feature)
        Button {
            if isSelected {
                selectedFeatures.remove(feature)
            } else {
                selectedFeatures.insert(feature)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: feature.systemImage)
                Text(feature.label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func loadExistingValues() {
        guard let unit else { return }
        name = unit.name
        sizeSquareMeters = unit.sizeSquareMeters == 0 ? "" : String(unit.sizeSquareMeters)
        rooms = unit.rooms == 0 ? "" : String(unit.rooms)
        coOwnershipShare = unit.coOwnershipShare == 0 ? "" : String(unit.coOwnershipShare)
        notes = unit.notes
        selectedFeatures = Set(unit.features)
    }

    private var validationMessages: [String] {
        [
            FormValidation.required(name, "Bezeichnung"),
            FormValidation.number(sizeSquareMeters, "Größe in m²"),
            FormValidation.number(rooms, "Zimmer"),
            FormValidation.number(coOwnershipShare, "Miteigentumsanteil")
        ].compactMap { $0 }
    }

    private func save() {
        let size = sizeSquareMeters.parsedDecimal ?? 0
        let roomCount = rooms.parsedDecimal ?? 0
        let share = coOwnershipShare.parsedDecimal ?? 0
        let features = Array(selectedFeatures)

        if let unit {
            unit.name = name
            unit.sizeSquareMeters = size
            unit.rooms = roomCount
            unit.coOwnershipShare = share
            unit.notes = notes
            unit.features = features
        } else {
            let newUnit = Unit(name: name, sizeSquareMeters: size, rooms: roomCount, notes: notes, coOwnershipShare: share)
            newUnit.property = property
            newUnit.features = features
            modelContext.insert(newUnit)
        }
        dismiss()
    }
}

#Preview {
    UnitEditView(property: Property(name: "Musterstraße 1"), unit: nil)
        .modelContainer(PreviewData.container)
}
