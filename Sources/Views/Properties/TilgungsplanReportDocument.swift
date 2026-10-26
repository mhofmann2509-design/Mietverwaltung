import SwiftUI

/// Druckfertiger, monatsweiser Tilgungsplan einer Immobilie für ein einzelnes Jahr, für den
/// PDF-Export. Die Jahreswerte (Zins/Tilgung) aus `Property.loanBreakdown(forYear:)` werden dabei
/// vereinfachend gleichmäßig auf die 12 Monate verteilt – konsistent mit dem bereits an anderer
/// Stelle verwendeten vereinfachten Annuitätendarlehen (keine echte monatliche Verzinsung).
struct TilgungsplanReportDocument: View {
    struct MonthRow: Identifiable {
        let month: Int
        let interest: Double
        let principal: Double
        let remainingBalance: Double
        var id: Int { month }
    }

    let propertyName: String
    let propertyAddress: String
    let generatedAt: Date
    let year: Int
    let purchasePrice: Double
    let loanAmount: Double
    let annualAnnuity: Double
    let rows: [MonthRow]

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    private static let monthNames = [
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tilgungsplan \(String(year))")
                    .font(.system(size: 19, weight: .bold))
                Text("\(propertyName) · \(propertyAddress)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("Stand: \(generatedAt.asShortDate)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.top, 10)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("Kaufpreis")
                    Text(purchasePrice.asCurrency).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("Darlehenssumme")
                    Text(loanAmount.asCurrency)
                }
                GridRow {
                    Text("Annuität \(String(year))").fontWeight(.semibold)
                    Text(annualAnnuity.asCurrency).fontWeight(.semibold)
                }
                GridRow {
                    Text("davon pro Monat")
                    Text((annualAnnuity / 12).asCurrency)
                }
            }
            .font(.system(size: 11))
            .padding(.top, 14)

            Text("Vereinfachtes Annuitätendarlehen: Jahreszins/-tilgung gleichmäßig auf die Monate verteilt, keine echte monatliche Verzinsung.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Monat").fontWeight(.semibold)
                    Text("Zins").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    Text("Tilgung").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    Text("Restschuld").fontWeight(.semibold).gridColumnAlignment(.trailing)
                }
                GridRow { Divider().gridCellColumns(4) }
                ForEach(rows) { row in
                    GridRow {
                        Text(Self.monthNames[safe: row.month - 1] ?? String(row.month))
                        Text(row.interest.asCurrency)
                        Text(row.principal.asCurrency)
                        Text(row.remainingBalance.asCurrency)
                    }
                }
            }
            .font(.system(size: 10))
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    TilgungsplanReportDocument(
        propertyName: "Musterstraße 1",
        propertyAddress: "Musterstraße 1, 12345 Berlin",
        generatedAt: .now,
        year: 2026,
        purchasePrice: 310_000,
        loanAmount: 220_000,
        annualAnnuity: 12_100,
        rows: (1...12).map { month in
            .init(month: month, interest: 500, principal: 508.33, remainingBalance: 200_000 - Double(month) * 508.33)
        }
    )
}
