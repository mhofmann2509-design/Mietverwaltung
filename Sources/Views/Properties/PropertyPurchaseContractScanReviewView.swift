import SwiftUI
import SwiftData

/// Zeigt die aus einem eingescannten Kaufvertrag erkannten Angaben zur Kontrolle an, bevor sie auf
/// die Immobilie übernommen werden – wie bei der Teilungserklärung keine ungeprüfte automatische
/// Übernahme (siehe `PropertyDocumentScanReviewView`).
struct PropertyPurchaseContractScanReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let property: Property

    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var hasEconomicTransferDate: Bool
    @State private var economicTransferDate: Date
    @State private var purchasePriceText: String
    @State private var landValueText: String

    init(property: Property, result: PurchaseContractScanResult) {
        self.property = property
        _hasPurchaseDate = State(initialValue: result.purchaseDate != nil)
        _purchaseDate = State(initialValue: result.purchaseDate ?? .now)
        _hasEconomicTransferDate = State(initialValue: result.economicTransferDate != nil)
        _economicTransferDate = State(initialValue: result.economicTransferDate ?? .now)
        _purchasePriceText = State(initialValue: result.purchasePrice.map { String($0) } ?? "")
        _landValueText = State(initialValue: result.landValue.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Aus dem Kaufvertrag erkannt – bitte prüfen und bei Bedarf korrigieren, bevor du übernimmst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Kaufpreis (€)", text: $purchasePriceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Kaufdatum (Beurkundung) bekannt", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Kaufdatum", selection: $purchaseDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Kaufpreis & Kaufdatum")
                }

                Section {
                    Toggle("Übergang bekannt", isOn: $hasEconomicTransferDate)
                    if hasEconomicTransferDate {
                        DatePicker("Übergang von Besitz, Nutzen und Lasten", selection: $economicTransferDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Wirtschaftlicher Übergang")
                } footer: {
                    Text("Maßgeblich für den Beginn des Dreijahreszeitraums der 15-%-Grenze – kann vom Beurkundungsdatum abweichen. Die bestehende Gebäude-AfA bleibt unverändert am Kaufdatum.")
                }

                Section {
                    TextField("Grund und Boden (€, falls im Vertrag beziffert)", text: $landValueText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Kaufpreisaufteilung")
                } footer: {
                    Text("Nur ausfüllen, wenn der Vertrag die Aufteilung auf Grund und Boden tatsächlich beziffert – sonst leer lassen und wie bisher manuell in „Immobilie bearbeiten“ pflegen.")
                }
            }
            .navigationTitle("Kaufvertrag prüfen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { apply() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 440, idealHeight: 540, maxHeight: 700)
            #endif
        }
    }

    private func apply() {
        if let price = Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")), price > 0 {
            property.purchasePrice = price
        }
        if let land = Double(landValueText.replacingOccurrences(of: ",", with: ".")), land > 0 {
            property.landValue = land
        }
        property.purchaseDate = hasPurchaseDate ? purchaseDate : property.purchaseDate
        property.economicTransferDate = hasEconomicTransferDate ? economicTransferDate : property.economicTransferDate
        dismiss()
    }
}

#Preview {
    PropertyPurchaseContractScanReviewView(
        property: Property(name: "Musterstraße 1"),
        result: PurchaseContractScanResult(purchaseDate: .now, economicTransferDate: .now, purchasePrice: 310_000, landValue: 70_000)
    )
    .modelContainer(PreviewData.container)
}
