import SwiftUI

/// Druckfertiger Bericht über alle Ausgaben einer Immobilie oder aller Immobilien, gruppiert
/// nach Objekt, für den PDF-Export zur Vorlage beim Finanzamt (Rechnungsdatum, Bezeichnung,
/// steuerliche Kategorie, Betrag, je Objekt und insgesamt zusammengerechnet).
struct ExpenseReportDocument: View {
    struct Row: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let treatment: TaxTreatment
        let amount: Double
    }

    struct PropertyGroup: Identifiable {
        let propertyName: String
        let rows: [Row]
        var id: String { propertyName }
        var total: Double { rows.reduce(0) { $0 + $1.amount } }
    }

    let taxYear: Int
    let generatedAt: Date
    let groups: [PropertyGroup]
    let maintenanceTotal: Double
    let otherDeductibleTotal: Double
    let capitalizedTotal: Double
    let grandTotal: Double

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ausgabenübersicht")
                    .font(.system(size: 19, weight: .bold))
                Text("Steuerjahr \(String(taxYear)) · Stand: \(generatedAt.asShortDate)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.top, 10)

            ForEach(groups) { group in
                Text(group.propertyName)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 20)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("Datum").fontWeight(.semibold)
                        Text("Bezeichnung").fontWeight(.semibold)
                        Text("Kategorie").fontWeight(.semibold)
                        Text("Betrag").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    }
                    GridRow { Divider().gridCellColumns(4) }
                    ForEach(group.rows) { row in
                        GridRow {
                            Text(row.date.asShortDate)
                            Text(row.title)
                            Text(row.treatment.shortLabel)
                            Text(row.amount.asCurrency)
                        }
                    }
                    GridRow { Divider().padding(.vertical, 2).gridCellColumns(4) }
                    GridRow {
                        Text("Summe \(group.propertyName)").fontWeight(.semibold)
                        Text("")
                        Text("")
                        Text(group.total.asCurrency).fontWeight(.semibold)
                    }
                }
                .font(.system(size: 10))
                .padding(.top, 8)
            }

            Text("Zusammenfassung nach steuerlicher Behandlung")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 26)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("Erhaltungsaufwendungen (sofort abziehbar)")
                    Text(maintenanceTotal.asCurrency).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("Sonstige Werbungskosten (sofort abziehbar)")
                    Text(otherDeductibleTotal.asCurrency)
                }
                if capitalizedTotal > 0 {
                    GridRow {
                        Text("Herstellungskosten (über Nutzungsdauer AfA)")
                        Text(capitalizedTotal.asCurrency)
                    }
                }
                GridRow { Divider().padding(.vertical, 2).gridCellColumns(2) }
                GridRow {
                    Text("Gesamt").fontWeight(.semibold)
                    Text(grandTotal.asCurrency).fontWeight(.semibold)
                }
            }
            .font(.system(size: 11))
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

#Preview {
    ExpenseReportDocument(
        taxYear: 2026,
        generatedAt: .now,
        groups: [
            .init(propertyName: "Musterstraße 1", rows: [
                .init(date: .now, title: "Heizung gewartet", treatment: .maintenanceExpense, amount: 240),
                .init(date: .now, title: "Hausversicherung", treatment: .otherDeductible, amount: 380)
            ])
        ],
        maintenanceTotal: 240,
        otherDeductibleTotal: 380,
        capitalizedTotal: 0,
        grandTotal: 620
    )
}
