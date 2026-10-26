import SwiftUI

/// Druckfertiger, itemisierter Bericht über abschreibbare Wirtschaftsgüter für ein bestimmtes
/// Steuerjahr, gruppiert nach Objekt – für den PDF-Export zur Vorlage beim Finanzamt. Wird sowohl
/// für die Möblierungsliste (ohne Kostenspalte – für die Steuer zählt nur die AfA/der Sofortabzug)
/// als auch für die Herstellungskosten-Liste (mit Kostenspalte und Gesamtsumme) verwendet.
struct AssetReportDocument: View {
    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let placedInServiceDate: Date
        let cost: Double
        /// Die für das gewählte Steuerjahr tatsächlich anzusetzende AfA (monatsgenau anteilig im
        /// Anschaffungsjahr, 0 außerhalb des Abschreibungszeitraums).
        let afaForYear: Double
        /// Ob der Sofortabzug (GWG) genau in diesem Steuerjahr greift.
        let isSofortabzugThisYear: Bool
    }

    struct PropertyGroup: Identifiable {
        let propertyName: String
        let rows: [Row]
        var id: String { propertyName }
        var totalCost: Double { rows.reduce(0) { $0 + $1.cost } }
        var totalAfaForYear: Double { rows.reduce(0) { $0 + $1.afaForYear } }
    }

    let title: String
    let taxYear: Int
    let generatedAt: Date
    let groups: [PropertyGroup]
    /// Ob die Kostenspalte und die Gesamt-Anschaffungskosten gezeigt werden sollen. Für die reine
    /// Möblierungsliste steuerlich irrelevant (nur AfA/Sofortabzug zählen); für Herstellungskosten
    /// dagegen relevant, da sie die Bemessungsgrundlage der Gebäude-AfA bilden.
    let showCostColumn: Bool

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    private var totalCost: Double { groups.reduce(0) { $0 + $1.totalCost } }
    private var totalAfaForYear: Double { groups.reduce(0) { $0 + $1.totalAfaForYear } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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
                        Text("Bezeichnung").fontWeight(.semibold)
                        Text("Anschaffung").fontWeight(.semibold)
                        if showCostColumn {
                            Text("Betrag").fontWeight(.semibold).gridColumnAlignment(.trailing)
                        }
                        Text("AfA \(String(taxYear)) bzw. Sofortabzug").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    }
                    GridRow { Divider().gridCellColumns(showCostColumn ? 4 : 3) }
                    ForEach(group.rows) { row in
                        GridRow {
                            Text(row.name)
                            Text(row.placedInServiceDate.asShortDate)
                            if showCostColumn {
                                Text(row.cost.asCurrency)
                            }
                            if row.isSofortabzugThisYear {
                                Text("Sofortabzug").foregroundStyle(.orange)
                            } else {
                                Text(row.afaForYear.asCurrency)
                            }
                        }
                    }
                    GridRow { Divider().padding(.vertical, 2).gridCellColumns(showCostColumn ? 4 : 3) }
                    GridRow {
                        Text("Summe \(group.propertyName)").fontWeight(.semibold)
                        Text("")
                        if showCostColumn {
                            Text(group.totalCost.asCurrency).fontWeight(.semibold)
                        }
                        Text(group.totalAfaForYear.asCurrency).fontWeight(.semibold)
                    }
                }
                .font(.system(size: 10))
                .padding(.top, 8)
            }

            if groups.count > 1 {
                Text("Gesamt (alle Objekte)")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 26)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                    if showCostColumn {
                        GridRow {
                            Text("Anschaffungskosten")
                            Text(totalCost.asCurrency).gridColumnAlignment(.trailing)
                        }
                    }
                    GridRow {
                        Text("AfA \(String(taxYear))")
                        Text(totalAfaForYear.asCurrency)
                    }
                }
                .font(.system(size: 11))
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

#Preview {
    AssetReportDocument(
        title: "Möblierungsliste",
        taxYear: 2026,
        generatedAt: .now,
        groups: [
            .init(propertyName: "Musterstraße 1", rows: [
                .init(name: "Einbauküche", placedInServiceDate: .now, cost: 6_500, afaForYear: 650, isSofortabzugThisYear: false),
                .init(name: "Waschmaschine", placedInServiceDate: .now, cost: 650, afaForYear: 0, isSofortabzugThisYear: true)
            ])
        ],
        showCostColumn: false
    )
}
