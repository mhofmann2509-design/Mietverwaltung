import SwiftUI

/// Interne Gesamtübersicht einer Nebenkostenabrechnung als PDF – anders als die Schreiben an die
/// Mieter nennt sie zusätzlich die nicht umlagefähigen Kostenarten und die komplette
/// Mieterverteilung auf einen Blick, zur eigenen Kontrolle/Ablage.
struct GesamtuebersichtReportDocument: View {
    struct LineItem: Identifiable {
        let id = UUID()
        let costType: String
        let amount: Double
        let isApportionable: Bool
    }

    struct AllocationRow: Identifiable {
        let id = UUID()
        let tenantName: String
        let unitName: String
        let allocatedCost: Double
        let advancesPaid: Double
        var difference: Double { allocatedCost - advancesPaid }
    }

    let propertyName: String
    let propertyAddress: String
    let year: Int
    let periodText: String
    let allocationMethodLabel: String
    let lineItems: [LineItem]
    let propertyTaxAmount: Double
    let totalApportionableCosts: Double
    let nonApportionableTotal: Double
    let reserveFundAccountInfo: String
    let allocationRows: [AllocationRow]
    let generatedAt: Date

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    private var apportionableItems: [LineItem] { lineItems.filter { $0.isApportionable } }
    private var nonApportionableItems: [LineItem] { lineItems.filter { !$0.isApportionable } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nebenkostenabrechnung \(String(year)) – Gesamtübersicht")
                    .font(.system(size: 17, weight: .bold))
                Text("\(propertyName) · \(propertyAddress)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("Zeitraum \(periodText) · Umlageschlüssel: \(allocationMethodLabel) · Stand: \(generatedAt.asShortDate)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.top, 8)

            Text("Umlagefähige Betriebskosten")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 16)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(apportionableItems) { item in
                    GridRow {
                        Text(item.costType)
                        Text(item.amount.asCurrency).gridColumnAlignment(.trailing)
                    }
                }
                GridRow {
                    Text("Grundsteuer")
                    Text(propertyTaxAmount.asCurrency)
                }
                GridRow { Divider().padding(.vertical, 2).gridCellColumns(2) }
                GridRow {
                    Text("Umlagefähig gesamt").fontWeight(.semibold)
                    Text(totalApportionableCosts.asCurrency).fontWeight(.semibold)
                }
            }
            .font(.system(size: 10))
            .padding(.top, 6)

            if !nonApportionableItems.isEmpty {
                Text("Nicht umlagefähige Betriebskosten (verbleiben beim Vermieter)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 16)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                    ForEach(nonApportionableItems) { item in
                        GridRow {
                            Text(item.costType)
                            Text(item.amount.asCurrency).gridColumnAlignment(.trailing)
                        }
                    }
                    GridRow { Divider().padding(.vertical, 2).gridCellColumns(2) }
                    GridRow {
                        Text("Nicht umlagefähig gesamt").fontWeight(.semibold)
                        Text(nonApportionableTotal.asCurrency).fontWeight(.semibold)
                    }
                }
                .font(.system(size: 10))
                .padding(.top, 6)
            }

            if !reserveFundAccountInfo.isEmpty {
                Text("Instandhaltungsrücklagenkonto: \(reserveFundAccountInfo)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            if !allocationRows.isEmpty {
                Text("Verteilung auf Mieter")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 20)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        Text("Mieter").fontWeight(.semibold)
                        Text("Einheit").fontWeight(.semibold)
                        Text("Anteil").fontWeight(.semibold).gridColumnAlignment(.trailing)
                        Text("Vorauszahlung").fontWeight(.semibold).gridColumnAlignment(.trailing)
                        Text("Nachz./Guthaben").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    }
                    GridRow { Divider().gridCellColumns(5) }
                    ForEach(allocationRows) { row in
                        GridRow {
                            Text(row.tenantName)
                            Text(row.unitName)
                            Text(row.allocatedCost.asCurrency)
                            Text(row.advancesPaid.asCurrency)
                            Text(row.difference >= 0 ? "+\(row.difference.asCurrency)" : row.difference.asCurrency)
                        }
                    }
                }
                .font(.system(size: 9.5))
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

#Preview {
    GesamtuebersichtReportDocument(
        propertyName: "Musterstraße 1",
        propertyAddress: "Musterstraße 1, 12345 Berlin",
        year: 2026,
        periodText: "01.01.2026 – 31.12.2026",
        allocationMethodLabel: "Nach Wohnfläche",
        lineItems: [
            .init(costType: "Heizung", amount: 1450, isApportionable: true),
            .init(costType: "Wasser/Abwasser", amount: 620, isApportionable: true),
            .init(costType: "Verwaltergebühr", amount: 240, isApportionable: false)
        ],
        propertyTaxAmount: 310,
        totalApportionableCosts: 2380,
        nonApportionableTotal: 240,
        reserveFundAccountInfo: "DE12 3456 7890 1234 5678 90, Stand 12.400 €",
        allocationRows: [
            .init(tenantName: "Erika Musterfrau", unitName: "1. OG rechts", allocatedCost: 1200, advancesPaid: 1150)
        ],
        generatedAt: .now
    )
}
