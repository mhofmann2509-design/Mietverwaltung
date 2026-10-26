import SwiftUI

/// Druckfertige Aufstellung der Gebäudeabschreibung (AfA) einer Immobilie nach § 7 Abs. 4 EStG,
/// für den PDF-Export zur Vorlage beim Finanzamt: Grundlagen der Berechnung (Kaufpreis, Bodenwert,
/// abschreibbarer Gebäudewert, angewandter AfA-Satz) sowie ein mehrjähriger AfA-Verlauf mit
/// kumulierter Abschreibung und Restbuchwert.
struct GebaeudeAfaReportDocument: View {
    struct YearRow: Identifiable {
        let year: Int
        let afaAmount: Double
        let cumulativeAfa: Double
        let remainingBookValue: Double
        var id: Int { year }
    }

    let propertyName: String
    let propertyAddress: String
    let generatedAt: Date
    let purchasePrice: Double
    let landValue: Double
    let buildingValue: Double
    let constructionYear: Int?
    let purchaseDate: Date?
    let afaRatePercent: Double
    /// Ob der AfA-Satz manuell festgelegt wurde (z.B. aus einem Restnutzungsdauergutachten),
    /// statt aus dem Baujahr typisiert abgeleitet zu sein.
    let isManualRate: Bool
    let annualAfa: Double
    let rows: [YearRow]

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    private var legalBasisText: String {
        isManualRate
            ? "§ 7 Abs. 4 Satz 2 EStG (abweichender AfA-Satz, z.B. lt. Restnutzungsdauergutachten)"
            : "§ 7 Abs. 4 Satz 1 EStG (gesetzlich typisierter linearer Satz nach Baujahr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gebäudeabschreibung (AfA)")
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
                    Text("Bodenwert (nicht abschreibbar)")
                    Text(landValue.asCurrency)
                }
                GridRow {
                    Text("Abschreibbarer Gebäudewert").fontWeight(.semibold)
                    Text(buildingValue.asCurrency).fontWeight(.semibold)
                }
                if let constructionYear {
                    GridRow {
                        Text("Baujahr")
                        Text(String(constructionYear))
                    }
                }
                if let purchaseDate {
                    GridRow {
                        Text("Anschaffungsdatum")
                        Text(purchaseDate.asShortDate)
                    }
                }
                GridRow {
                    Text("Angewandter AfA-Satz")
                    Text(afaRatePercent.asPercent)
                }
                GridRow {
                    Text("Jährliche AfA").fontWeight(.semibold)
                    Text(annualAfa.asCurrency).fontWeight(.semibold)
                }
            }
            .font(.system(size: 11))
            .padding(.top, 14)

            Text("Rechtsgrundlage: \(legalBasisText)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text("AfA-Verlauf")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 24)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Jahr").fontWeight(.semibold)
                    Text("AfA").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    Text("Kumulierte AfA").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    Text("Restbuchwert").fontWeight(.semibold).gridColumnAlignment(.trailing)
                }
                GridRow { Divider().gridCellColumns(4) }
                ForEach(rows) { row in
                    GridRow {
                        Text(String(row.year))
                        Text(row.afaAmount.asCurrency)
                        Text(row.cumulativeAfa.asCurrency)
                        Text(row.remainingBookValue.asCurrency)
                    }
                }
            }
            .font(.system(size: 10))
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

#Preview {
    GebaeudeAfaReportDocument(
        propertyName: "Musterstraße 1",
        propertyAddress: "Musterstraße 1, 12345 Berlin",
        generatedAt: .now,
        purchasePrice: 310_000,
        landValue: 70_000,
        buildingValue: 240_000,
        constructionYear: 1998,
        purchaseDate: .now,
        afaRatePercent: 2.0,
        isManualRate: false,
        annualAfa: 4_800,
        rows: (0..<10).map { offset in
            .init(year: 2024 + offset, afaAmount: 4_800, cumulativeAfa: 4_800 * Double(offset + 1), remainingBookValue: 240_000 - 4_800 * Double(offset + 1))
        }
    )
}
