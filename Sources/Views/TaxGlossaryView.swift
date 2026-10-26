import SwiftUI

/// Nachschlagewerk zu den steuerlichen Grundbegriffen bei Immobilien: Anschaffungskosten,
/// Herstellungskosten und Erhaltungsaufwendungen – mit Beispielen, da die Abgrenzung in der
/// Praxis oft die größte Fehlerquelle in der Steuererklärung ist.
struct TaxGlossaryView: View {
    private struct Term: Identifiable {
        let id = UUID()
        let title: String
        let lawReference: String
        let definition: String
        let examples: [String]
        let taxTreatment: String
        let color: Color
        let systemImage: String
    }

    private let terms: [Term] = [
        Term(
            title: "Anschaffungskosten",
            lawReference: "§ 255 Abs. 1 HGB",
            definition: "Alles, was aufgewendet wird, um ein Wirtschaftsgut zu erwerben und in einen betriebsbereiten Zustand zu versetzen – der Kaufpreis selbst sowie alle Kosten, die unmittelbar mit dem Erwerb zusammenhängen (Anschaffungsnebenkosten).",
            examples: [
                "Kaufpreis der Immobilie laut Kaufvertrag.",
                "Grunderwerbsteuer, Notar- und Grundbuchkosten.",
                "Maklerprovision.",
                "Kosten für die erstmalige Herstellung der Betriebsbereitschaft (z.B. Einbau einer Heizung, die zum Bezug fehlt)."
            ],
            taxTreatment: "Keine sofortige Abschreibung – die Anschaffungskosten des Gebäudes bilden die Bemessungsgrundlage für die lineare Gebäude-AfA (i.d.R. 2–3 % pro Jahr über die Nutzungsdauer, siehe § 7 Abs. 4 EStG). Der Bodenanteil ist nicht abschreibbar.",
            color: .blue,
            systemImage: "house"
        ),
        Term(
            title: "Herstellungskosten",
            lawReference: "§ 255 Abs. 2 HGB, § 6 Abs. 1 Nr. 1a EStG",
            definition: "Aufwendungen, die ein Wirtschaftsgut erstmals herstellen, erweitern oder über seinen ursprünglichen Zustand hinaus wesentlich verbessern (Standardhebung). Auch „anschaffungsnahe Herstellungskosten“ zählen dazu: Werden innerhalb von 3 Jahren nach Anschaffung Instandsetzungs-/Modernisierungskosten (netto, ohne USt.) von mehr als 15 % der Gebäude-Anschaffungskosten aufgewendet, gelten sie automatisch als Herstellungskosten – selbst wenn es sich eigentlich um normale Reparaturen handelt.",
            examples: [
                "Anbau, Aufstockung oder Dachgeschossausbau.",
                "Vollständige Badsanierung mit deutlicher Standardanhebung (z.B. von einfach auf gehoben).",
                "Fassadendämmung, die den energetischen Standard wesentlich verbessert.",
                "Beispiel „anschaffungsnah“: Kauf einer Wohnung für 100.000 € (Gebäudeanteil), im 2. Jahr danach Renovierung für 20.000 € netto → über 15 % → gilt vollständig als Herstellungskosten, auch wenn es „nur“ Malerarbeiten und neue Böden waren."
            ],
            taxTreatment: "Keine sofortige Abschreibung. Herstellungskosten erhöhen die Bemessungsgrundlage der Gebäude-AfA und werden mit demselben AfA-Satz wie das Gebäude selbst über die (Rest-)Nutzungsdauer abgeschrieben – nicht mit einer frei gewählten Nutzungsdauer. Ein Gutachten zur Restnutzungsdauer kann die Abschreibungsdauer verkürzen.",
            color: .orange,
            systemImage: "hammer"
        ),
        Term(
            title: "Erhaltungsaufwendungen",
            lawReference: "§ 21 EStG (als Werbungskosten)",
            definition: "Kosten, die den bestehenden Zustand eines Gebäudes lediglich erhalten oder wiederherstellen (Reparatur, Austausch bereits vorhandener Teile), ohne das Gebäude wesentlich zu verbessern oder zu erweitern. Abgrenzung zu Herstellungskosten: entscheidend ist, ob nur der ursprüngliche, zeitgemäße Zustand erhalten wird (Erhaltungsaufwand) oder eine wesentliche Verbesserung/Standardhebung erfolgt (Herstellungskosten).",
            examples: [
                "Reparatur einer defekten Heizung oder Therme.",
                "Streichen der Wände, Austausch abgenutzter Bodenbeläge in gleicher Qualität.",
                "Beseitigung eines Wasserschadens.",
                "Laufende Wartung von Aufzug, Heizung, Dach."
            ],
            taxTreatment: "Sofort und in voller Höhe als Werbungskosten abziehbar im Jahr der Zahlung – keine Verteilung über mehrere Jahre nötig (auf Antrag auch Verteilung auf 2–5 Jahre möglich, § 82b EStDV, bei größeren Erhaltungsaufwendungen).",
            color: .green,
            systemImage: "wrench.and.screwdriver"
        ),
        Term(
            title: "Sonstige Werbungskosten",
            lawReference: "§ 9, § 21 EStG",
            definition: "Alle übrigen Kosten, die im Zusammenhang mit der Vermietung anfallen, aber weder Erhaltungsaufwand noch Herstellungs-/Anschaffungskosten sind.",
            examples: [
                "Gebäudeversicherung, Grundsteuer.",
                "Finanzierungszinsen (nicht die Tilgung – die ist steuerlich nicht abziehbar).",
                "Verwalterhonorar, Kontoführungsgebühren, Steuerberatungskosten für die Vermietung.",
                "Fahrtkosten zur Immobilie, Inserate zur Mietersuche."
            ],
            taxTreatment: "Sofort und in voller Höhe als Werbungskosten abziehbar im Jahr der Zahlung.",
            color: .purple,
            systemImage: "doc.text"
        ),
        Term(
            title: "Geringwertige Wirtschaftsgüter (GWG) & Sofortabzug",
            lawReference: "§ 6 Abs. 2 EStG",
            definition: "Bewegliche, selbständig nutzbare Wirtschaftsgüter (z.B. Einrichtungsgegenstände), deren Anschaffungskosten 800 € (netto) nicht übersteigen.",
            examples: [
                "Waschmaschine für 650 €.",
                "Einzelne Möbelstücke, Lampen, kleinere Haushaltsgeräte."
            ],
            taxTreatment: "Dürfen im Jahr der Anschaffung sofort in voller Höhe abgezogen werden, statt über die Nutzungsdauer verteilt zu werden. Gilt nicht für Herstellungskosten am Gebäude.",
            color: .pink,
            systemImage: "bolt"
        )
    ]

    var body: some View {
        List {
            Section {
                Text("Die Abgrenzung zwischen diesen Begriffen entscheidet, ob eine Ausgabe sofort in voller Höhe absetzbar ist oder nur über viele Jahre verteilt über die AfA – und ist eine der häufigsten Fehlerquellen in der Steuererklärung von Vermietern. Diese Übersicht ersetzt keine Steuerberatung, hilft aber bei der ersten Einordnung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(terms) { term in
                Section {
                    Text(term.definition)
                        .font(.body)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Beispiele")
                            .font(.subheadline.weight(.semibold))
                        ForEach(term.examples, id: \.self) { example in
                            Label(example, systemImage: "circle.fill")
                                .labelStyle(.bullet)
                                .font(.callout)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steuerliche Behandlung")
                            .font(.subheadline.weight(.semibold))
                        Text(term.taxTreatment)
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.title).font(.headline)
                            Text(term.lawReference).font(.caption).textCase(nil)
                        }
                    } icon: {
                        Image(systemName: term.systemImage)
                            .foregroundStyle(term.color)
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle("Steuerbegriffe")
    }
}

/// Einfaches Label ohne System-Icon, nur mit einem kleinen Aufzählungspunkt.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().frame(width: 4, height: 4).padding(.top, 7).opacity(0.5)
            configuration.title
        }
    }
}

private extension LabelStyle where Self == BulletLabelStyle {
    static var bullet: BulletLabelStyle { BulletLabelStyle() }
}

#Preview {
    NavigationStack {
        TaxGlossaryView()
    }
}
