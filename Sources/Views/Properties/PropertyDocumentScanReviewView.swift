import SwiftUI
import SwiftData

/// Zeigt die aus einer gescannten Teilungserklärung erkannten Angaben zur Kontrolle an, bevor sie
/// auf die Immobilie bzw. eine Einheit übernommen werden – OCR kann Fehler machen, daher keine
/// ungeprüfte automatische Übernahme.
struct PropertyDocumentScanReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let property: Property

    @State private var totalAreaText: String
    @State private var location: String
    @State private var coOwnershipShareText: String
    @State private var purchasePriceText: String
    @State private var furnitureLabel: String
    @State private var furniturePriceText: String
    @State private var selectedUnit: Unit?

    init(property: Property, result: PropertyScanResult) {
        self.property = property
        _totalAreaText = State(initialValue: result.totalAreaSquareMeters.map { String($0) } ?? "")
        _location = State(initialValue: result.location ?? "")
        _coOwnershipShareText = State(initialValue: result.coOwnershipShare.map { String($0) } ?? "")
        _purchasePriceText = State(initialValue: result.purchasePrice.map { String($0) } ?? "")
        _furnitureLabel = State(initialValue: result.furnitureLabel ?? "")
        _furniturePriceText = State(initialValue: result.furniturePrice.map { String($0) } ?? "")
        _selectedUnit = State(initialValue: (property.units ?? []).first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Aus der Teilungserklärung erkannt – bitte prüfen und bei Bedarf korrigieren, bevor du übernimmst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Immobilie") {
                    TextField("Kaufpreis (€)", text: $purchasePriceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section {
                    if !(property.units ?? []).isEmpty {
                        Picker("Einheit", selection: $selectedUnit) {
                            ForEach(property.units ?? []) { unit in
                                Text(unit.name.isEmpty ? "Einheit" : unit.name).tag(Optional(unit))
                            }
                            Text("Neue Einheit anlegen").tag(Optional<Unit>.none)
                        }
                    } else {
                        Text("Es wird eine neue Einheit angelegt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Lage/Bezeichnung (z.B. 2. OG links)", text: $location)
                    TextField("Wohnfläche (m²)", text: $totalAreaText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Miteigentumsanteil (MEA)", text: $coOwnershipShareText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Einheit")
                } footer: {
                    Text("Die Werte werden auf die ausgewählte (bzw. neu angelegte) Einheit übernommen.")
                }

                Section {
                    TextField("Bezeichnung (z.B. Einbauküche)", text: $furnitureLabel)
                    TextField("Preis (€)", text: $furniturePriceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Mitverkaufte Möblierung (optional)")
                } footer: {
                    Text("Wird nur übernommen, wenn hier ein Preis eingetragen ist – als eigenes Wirtschaftsgut zur Abschreibung bei der Einheit.")
                }
            }
            .navigationTitle("Teilungserklärung prüfen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { apply() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 480, idealHeight: 600, maxHeight: 780)
            #endif
        }
    }

    private func apply() {
        if let price = purchasePriceText.parsedDecimal, price > 0 {
            property.purchasePrice = price
        }

        let targetUnit: Unit
        if let selectedUnit {
            targetUnit = selectedUnit
        } else {
            let newUnit = Unit(name: location)
            newUnit.property = property
            modelContext.insert(newUnit)
            targetUnit = newUnit
        }

        if !location.isEmpty {
            targetUnit.name = location
        }
        if let area = totalAreaText.parsedDecimal, area > 0 {
            targetUnit.sizeSquareMeters = area
        }
        if let share = coOwnershipShareText.parsedDecimal, share > 0 {
            targetUnit.coOwnershipShare = share
        }

        if let furniturePrice = furniturePriceText.parsedDecimal, furniturePrice > 0 {
            let asset = DepreciableAsset(
                name: furnitureLabel.isEmpty ? "Möblierung" : furnitureLabel,
                category: .furniture,
                cost: furniturePrice,
                usefulLifeYears: AssetCategory.furniture.defaultUsefulLifeYears,
                placedInServiceDate: property.purchaseDate ?? .now
            )
            asset.property = property
            asset.unit = targetUnit
            modelContext.insert(asset)
        }

        dismiss()
    }
}

#Preview {
    PropertyDocumentScanReviewView(
        property: Property(name: "Musterstraße 1"),
        result: PropertyScanResult(
            totalAreaSquareMeters: 68,
            location: "2. OG links",
            coOwnershipShare: 144,
            purchasePrice: 310_000,
            furnitureLabel: "Einbauküche",
            furniturePrice: 6_500
        )
    )
    .modelContainer(PreviewData.container)
}
