import SwiftUI
import Charts

/// Eigenständiger, nicht steuerlicher Jahresbericht zur Wirtschaftlichkeit einer Immobilie
/// (Rendite, Cashflow, Finanzierung) für Investor und finanzierende Bank – getrennt von den
/// Steuerreports in `TaxReportPDFBuilder`, da er andere Adressaten und einen anderen Zweck hat
/// (wirtschaftliche statt steuerliche Beurteilung). Alle Zahlen stammen unverändert aus den
/// bereits an anderer Stelle verwendeten, getesteten `Property`-Berechnungen (siehe
/// `PropertyDetailView`s Finanzen-Reiter) – hier nur neu zusammengestellt und visualisiert.
struct WirtschaftsberichtDocument: View {
    struct YearFigure: Identifiable {
        let year: Int
        let coldRent: Double
        let cashFlow: Double
        var id: Int { year }
    }

    let propertyName: String
    let propertyAddress: String
    let generatedAt: Date
    let year: Int

    let purchasePrice: Double
    let coldRentAnnual: Double
    let grossYieldPercent: Double?
    let netYieldPercent: Double?

    let operativeCashFlow: Double
    let freeCashFlow: Double
    let freeCashFlowAfterTax: Double?

    /// Barausgaben (Werbungskosten ohne AfA) + nicht umlagefähige Nebenkosten zusammen – die
    /// dritte Verwendungskategorie der Kaltmiete neben Zins und Tilgung.
    let operatingCashCosts: Double
    let interest: Double
    let principal: Double
    let remainingBalance: Double
    let loanAmount: Double
    let interestRatePercent: Double

    /// Mehrjahresentwicklung Kaltmiete/Cashflow – für den Trend-Chart; leer, wenn nicht genug
    /// Jahre vorliegen (z.B. direkt nach Erwerb).
    let yearlyFigures: [YearFigure]

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    // Eigene, feste Farbpalette statt `Theme.*`: dieses Dokument wird als PDF exportiert und darf
    // nicht vom live gewählten App-Erscheinungsbild des Nutzers abhängen (siehe an anderer Stelle
    // behobener Fehler, bei dem eine themeabhängige Farbe in einem PDF zu einem falschen
    // Linien-/Balkenton führte, der je nach Nutzereinstellung anders aussah).
    private enum Palette {
        static let accent = Color(red: 0.067, green: 0.161, blue: 0.298)
        static let good = Color(red: 0.169, green: 0.482, blue: 0.306)
        static let bad = Color(red: 0.698, green: 0.235, blue: 0.235)
        static let textPrimary = Color.black.opacity(0.87)
        static let textSecondary = Color.black.opacity(0.54)
        static let divider = Color.black.opacity(0.14)
        static let interest = Color(red: 0.698, green: 0.235, blue: 0.235)
        static let principal = Color(red: 0.067, green: 0.161, blue: 0.298)
        static let operating = Color(red: 0.698, green: 0.533, blue: 0.106)
    }

    /// Bänderchen der Kaltmieten-Verwendung – alle drei Positionen sind konstruktionsbedingt
    /// ≥ 0 (im Gegensatz zum Cashflow, der negativ werden kann und deshalb bewusst NICHT Teil
    /// dieser Aufteilung ist, sondern separat als Kennzahl/Trendlinie gezeigt wird).
    private var usageSegments: [(label: String, amount: Double, color: Color)] {
        [
            ("Zins", max(0, interest), Palette.interest),
            ("Tilgung", max(0, principal), Palette.principal),
            ("Betriebskosten", max(0, operatingCashCosts), Palette.operating)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.accent).frame(height: 2).padding(.top, 10)

            kpiGrid.padding(.top, 18)

            if !usageSegments.isEmpty {
                usageChart.padding(.top, 20)
            }

            if yearlyFigures.count >= 2 {
                trendChart.padding(.top, 20)
            }

            financingBlock.padding(.top, 20)

            Spacer(minLength: 0)

            Text("Wirtschaftlicher Jahresbericht – keine Steuerunterlage, keine Anlageberatung. Alle Angaben auf Basis der in der App erfassten Daten, ohne Gewähr.")
                .font(.system(size: 7.5))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 10)
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Palette.textPrimary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("WIRTSCHAFTSBERICHT")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.accent)
                .tracking(0.8)
            Text("\(propertyName) · \(String(year))")
                .font(.system(size: 19, weight: .bold))
            Text(propertyAddress)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textSecondary)
            Text("Stand: \(generatedAt.asShortDate)")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func kpiTile(_ title: String, _ value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone ?? Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiGrid: some View {
        Grid(horizontalSpacing: 18, verticalSpacing: 14) {
            GridRow {
                kpiTile("Jahreskaltmiete", coldRentAnnual.asCurrency)
                kpiTile("Bruttorendite", grossYieldPercent?.asPercent ?? "nicht ermittelbar")
                kpiTile("Nettorendite", netYieldPercent?.asPercent ?? "nicht ermittelbar")
            }
            GridRow {
                kpiTile("Operativer Cashflow", operativeCashFlow.asCurrency, tone: operativeCashFlow >= 0 ? Palette.good : Palette.bad)
                kpiTile(freeCashFlowAfterTax != nil ? "Freier Cashflow (n. Steuer)" : "Freier Cashflow (vor Steuer)", (freeCashFlowAfterTax ?? freeCashFlow).asCurrency, tone: (freeCashFlowAfterTax ?? freeCashFlow) >= 0 ? Palette.good : Palette.bad)
                kpiTile("Restschuld", remainingBalance.asCurrency)
            }
        }
    }

    private var usageChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VERWENDUNG DER KALTMIETE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.accent)
                .tracking(0.4)
            Chart {
                ForEach(usageSegments, id: \.label) { segment in
                    BarMark(x: .value("Betrag", segment.amount), y: .value("Position", "Kaltmiete"))
                        .foregroundStyle(segment.color)
                }
            }
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 34)
            HStack(spacing: 16) {
                ForEach(usageSegments, id: \.label) { segment in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(segment.color).frame(width: 8, height: 8)
                        Text("\(segment.label) \(segment.amount.asCurrency)")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(freeCashFlow >= 0 ? Palette.good : Palette.bad).frame(width: 8, height: 8)
                    Text("Verbleibender Cashflow \(freeCashFlow.asCurrency)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEHRJAHRESENTWICKLUNG")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.accent)
                .tracking(0.4)
            Chart {
                ForEach(yearlyFigures) { figure in
                    BarMark(x: .value("Jahr", String(figure.year)), y: .value("Kaltmiete", figure.coldRent))
                        .foregroundStyle(Palette.accent.opacity(0.35))
                        .position(by: .value("Reihe", "Kaltmiete"))
                    BarMark(x: .value("Jahr", String(figure.year)), y: .value("Cashflow", figure.cashFlow))
                        .foregroundStyle(figure.cashFlow >= 0 ? Palette.good : Palette.bad)
                        .position(by: .value("Reihe", "Cashflow"))
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Palette.divider)
                    AxisValueLabel().font(.system(size: 7.5)).foregroundStyle(Palette.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 7.5)).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(height: 110)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(0.35)).frame(width: 8, height: 8)
                    Text("Kaltmiete").font(.system(size: 8.5)).foregroundStyle(Palette.textSecondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.good).frame(width: 8, height: 8)
                    Text("Freier Cashflow").font(.system(size: 8.5)).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var financingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FINANZIERUNG")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.accent)
                .tracking(0.4)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    Text("Darlehenssumme").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                    Text(loanAmount.asCurrency).font(.system(size: 9.5)).monospacedDigit()
                    Text("Zinssatz p.a.").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                    Text(interestRatePercent.asPercent).font(.system(size: 9.5)).monospacedDigit()
                }
                GridRow {
                    Text("Zins \(String(year))").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                    Text(interest.asCurrency).font(.system(size: 9.5)).monospacedDigit()
                    Text("Tilgung \(String(year))").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                    Text(principal.asCurrency).font(.system(size: 9.5)).monospacedDigit()
                }
                GridRow {
                    Text("Kapitaldienst \(String(year))").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                    Text((interest + principal).asCurrency).font(.system(size: 9.5)).monospacedDigit()
                    Text("Restschuld Ende \(String(year))").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                    Text(remainingBalance.asCurrency).font(.system(size: 9.5)).monospacedDigit()
                }
                if purchasePrice > 0 {
                    GridRow {
                        Text("Restschuld in % des Kaufpreises").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                        Text((remainingBalance / purchasePrice * 100).asPercent).font(.system(size: 9.5)).monospacedDigit()
                        if interest + principal > 0 {
                            Text("Kapitaldienstdeckungsgrad (DSCR)").font(.system(size: 9.5)).foregroundStyle(Palette.textSecondary)
                            Text(String(format: "%.2f", (coldRentAnnual - operatingCashCosts) / (interest + principal))).font(.system(size: 9.5)).monospacedDigit()
                        } else {
                            Text("")
                            Text("")
                        }
                    }
                }
            }
            Text("Beleihungsauslauf anhand des Kaufpreises genähert, mangels erfasstem aktuellen Verkehrswert – keine Wertermittlung. Kapitaldienstdeckungsgrad (DSCR) = (Kaltmiete − Betriebskosten) ÷ Kapitaldienst; > 1 bedeutet, die Erträge decken Zins und Tilgung.")
                .font(.system(size: 7.5))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)
        }
    }
}

#Preview {
    WirtschaftsberichtDocument(
        propertyName: "Musterstraße 1",
        propertyAddress: "Musterstraße 1, 12345 Berlin",
        generatedAt: .now,
        year: 2026,
        purchasePrice: 310_000,
        coldRentAnnual: 17_680,
        grossYieldPercent: 5.7,
        netYieldPercent: 3.2,
        operativeCashFlow: 1_850,
        freeCashFlow: 2_279,
        freeCashFlowAfterTax: 1_950,
        operatingCashCosts: 1_120,
        interest: 7_386,
        principal: 4_713,
        remainingBalance: 198_400,
        loanAmount: 220_000,
        interestRatePercent: 3.5,
        yearlyFigures: [
            .init(year: 2024, coldRent: 16_200, cashFlow: 1_400),
            .init(year: 2025, coldRent: 17_000, cashFlow: 1_900),
            .init(year: 2026, coldRent: 17_680, cashFlow: 2_279)
        ]
    )
}
