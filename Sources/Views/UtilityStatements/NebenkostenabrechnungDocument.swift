import SwiftUI

/// Druckfertiges Anschreiben für eine Nebenkostenabrechnung (A4), für den PDF-Export.
/// Bewusst mit festen Farben (schwarz auf weiß), unabhängig vom System-Farbschema,
/// da dies ein Dokument zum Drucken/Versenden ist und kein App-Bildschirm.
///
/// Enthält bewusst nur die umlagefähigen Kostenarten – nicht umlagefähige Kosten gehen den
/// Mieter nichts an und werden hier nicht aufgeführt (siehe `apportionableLineItems`).
struct NebenkostenabrechnungDocument: View {
    struct LineItem {
        let type: String
        let amount: Double
    }

    let propertyName: String
    let propertyAddress: String
    let year: Int
    let periodStart: Date
    let periodEnd: Date
    let tenantName: String
    /// Fertige Anrede fürs Anschreiben, z.B. „Sehr geehrter Herr Mustermann,“ (siehe `Tenant.formalSalutation`).
    let tenantSalutationLine: String
    let unitName: String
    let allocationMethodLabel: String
    /// Konkreter Anteil des Mieters am gewählten Umlageschlüssel als Verhältnis, z.B. „144/1.000“
    /// bei MEA oder „68/123 m²“ bei Wohnfläche – unabhängig davon, welche Maßeinheit zugrunde liegt.
    let allocationKeyDetail: String
    /// Nur die umlagefähigen Kostenarten (Grundsteuer separat über `propertyTaxAmount`).
    let apportionableLineItems: [LineItem]
    let propertyTaxAmount: Double
    let apportionableTotal: Double
    let allocatedShare: Double
    let advancesPaid: Double
    let landlordName: String
    let landlordEmail: String
    let bankAccountHolder: String
    let iban: String
    let bic: String

    /// Positiv = Nachzahlung des Mieters, negativ = Guthaben zugunsten des Mieters.
    private var difference: Double { allocatedShare - advancesPaid }
    private var isPayment: Bool { difference >= 0.005 }
    private var hasBankDetails: Bool { !iban.trimmingCharacters(in: .whitespaces).isEmpty }

    static let pageSize = CGSize(width: 595, height: 842) // A4 bei 72 dpi

    private var periodText: String {
        "\(periodStart.asShortDate) – \(periodEnd.asShortDate)"
    }

    /// Übliche, von der Rechtsprechung als angemessen anerkannte Zahlungsfrist für die
    /// Nachzahlung aus einer Betriebskostenabrechnung (in Anlehnung an § 286 Abs. 3 BGB).
    /// Gesetzlich ist keine feste Frist vorgeschrieben; deutlich kürzere Fristen (z.B. 7–14 Tage)
    /// gelten als unangemessen kurz. Maßgeblich ist der Zugang dieses Schreibens beim Mieter.
    private static let paymentDeadlineDays = 30

    private var paymentDueDate: Date {
        Calendar.current.date(byAdding: .day, value: Self.paymentDeadlineDays, to: .now) ?? .now
    }

    /// Faltmarken (DIN 5008) bei 105 mm und 210 mm ab Oberkante, damit das Blatt für ein
    /// Fenster-Kuvert (C6/5) korrekt in Drittel gefaltet werden kann.
    private static let foldMarkPositions: [CGFloat] = [105, 210].map { $0 * 72.0 / 25.4 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            letterContent
                .padding(44)

            ForEach(Self.foldMarkPositions, id: \.self) { y in
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 12, height: 0.75)
                    .position(x: 6, y: y)
            }
        }
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .foregroundStyle(Color.black)
    }

    private var letterContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(propertyName).font(.system(size: 12, weight: .semibold))
                    Text(propertyAddress).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now.asShortDate).font(.system(size: 9)).foregroundStyle(.secondary)
            }

            // Platziert im Sichtfenster-Bereich eines Fenster-Kuverts (DIN 5008 Form A: Anschriftfeld
            // ab ca. 45 mm Blattoberkante, oberhalb der ersten Falzmarke bei 105 mm).
            VStack(alignment: .leading, spacing: 2) {
                Text(tenantName).font(.system(size: 11))
                Text(unitName).font(.system(size: 11))
                Text(propertyAddress).font(.system(size: 11))
            }
            .padding(.top, 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("Nebenkostenabrechnung \(String(year))")
                    .font(.system(size: 19, weight: .bold))
                Text("Abrechnungszeitraum: \(periodText)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 26)

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.top, 10)

            Text(salutation)
                .font(.system(size: 11))
                .padding(.top, 16)

            Text(introText)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("Kostenart").fontWeight(.semibold)
                    Text("Umlageschlüssel").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    Text("Betrag").fontWeight(.semibold).gridColumnAlignment(.trailing)
                }
                GridRow { Divider().gridCellColumns(3) }
                ForEach(Array(apportionableLineItems.enumerated()), id: \.offset) { _, item in
                    GridRow {
                        Text(item.type)
                        Text(allocationKeyDetail)
                        Text(item.amount.asCurrency)
                    }
                }
                GridRow {
                    Text("Grundsteuer")
                    Text(allocationKeyDetail)
                    Text(propertyTaxAmount.asCurrency)
                }
                GridRow { Divider().padding(.vertical, 2).gridCellColumns(3) }
                GridRow {
                    Text("Umlagefähige Gesamtkosten").fontWeight(.semibold)
                    Text("")
                    Text(apportionableTotal.asCurrency).fontWeight(.semibold)
                }
            }
            .font(.system(size: 11))
            .padding(.top, 14)

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                row(left: "Ihr Anteil", right: allocatedShare.asCurrency)
                row(left: "Geleistete Vorauszahlungen", right: advancesPaid.asCurrency)
                row(
                    left: isPayment ? "Nachzahlung" : "Guthaben zu Ihren Gunsten",
                    right: abs(difference).asCurrency,
                    bold: true,
                    color: isPayment ? Color(red: 0.75, green: 0.1, blue: 0.1) : Color(red: 0.1, green: 0.5, blue: 0.2)
                )
            }
            .padding(.top, 6)

            if isPayment {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bitte überweisen Sie den Nachzahlungsbetrag innerhalb von \(Self.paymentDeadlineDays) Tagen, spätestens bis zum \(paymentDueDate.asShortDate), auf folgendes Konto:")
                        .font(.system(size: 10))
                        .fixedSize(horizontal: false, vertical: true)

                    if hasBankDetails {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bankAccountHolder).font(.system(size: 10, weight: .semibold))
                            Text("IBAN: \(iban)").font(.system(size: 10))
                            if !bic.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("BIC: \(bic)").font(.system(size: 10))
                            }
                        }
                        .padding(.top, 10)
                    } else {
                        Text("(Keine Bankverbindung hinterlegt – bitte in der Immobilie ergänzen.)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                }
                .padding(.top, 14)
            } else {
                Text("Das Guthaben zu Ihren Gunsten verrechnen wir mit der nächsten fälligen Miete.")
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Mit freundlichen Grüßen")
                    .font(.system(size: 11))
                Text(landlordName.isEmpty ? propertyName : landlordName)
                    .font(.system(size: 11))
                    .padding(.top, 20)
                if !landlordEmail.isEmpty {
                    Text(landlordEmail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 0)
        }
    }

    private var salutation: String { tenantSalutationLine }

    private var introText: String {
        "im Rahmen der Betriebskostenabrechnung übersenden wir Ihnen die Abrechnung der umlagefähigen Betriebskosten für Ihre Wohnung \(unitName) für den oben genannten Abrechnungszeitraum. Die Einzelpositionen sowie die Berechnung Ihres Anteils entnehmen Sie bitte der folgenden Aufstellung."
    }

    @ViewBuilder
    private func row(left: String, right: String, bold: Bool = false, color: Color = .black) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(left)
            Spacer(minLength: 12)
            Text(right)
        }
        .font(.system(size: 11, weight: bold ? .semibold : .regular))
        .foregroundStyle(color)
        .padding(.vertical, 3)
    }
}

#Preview {
    NebenkostenabrechnungDocument(
        propertyName: "Musterstraße 1",
        propertyAddress: "Musterstraße 1, 12345 Berlin",
        year: 2025,
        periodStart: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1)) ?? .now,
        periodEnd: Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 31)) ?? .now,
        tenantName: "Erika Musterfrau",
        tenantSalutationLine: "Sehr geehrte Frau Musterfrau,",
        unitName: "1. OG rechts",
        allocationMethodLabel: "Nach Miteigentumsanteilen (MEA)",
        allocationKeyDetail: "144/1.000",
        apportionableLineItems: [
            .init(type: "Heizung", amount: 1450),
            .init(type: "Wasser/Abwasser", amount: 620),
            .init(type: "Hausmeister", amount: 480),
        ],
        propertyTaxAmount: 310,
        apportionableTotal: 2860,
        allocatedShare: 1850,
        advancesPaid: 2160,
        landlordName: "Max Mustermann",
        landlordEmail: "max@mustermann.de",
        bankAccountHolder: "Max Mustermann",
        iban: "DE02 1203 0000 0012 3456 78",
        bic: "BYLADEM1001"
    )
}
