import SwiftUI
import SwiftData

/// Reine Ansicht eines Wirtschaftsplans (Prognose), in denselben zwei klar getrennten Blöcken wie
/// die Betriebskosten-Abschnitte der Immobilie – konsistent zur Abrechnung, die beim Antippen
/// ebenfalls zuerst eine Ansicht statt direkt den Bearbeiten-Modus zeigt.
struct WirtschaftsplanDetailView: View {
    @Bindable var plan: WirtschaftsplanStatement
    @State private var showingEditSheet = false

    private var apportionableItems: [WirtschaftsplanLineItem] {
        (plan.lineItems ?? []).filter { $0.isApportionable }.sorted { $0.costType < $1.costType }
    }

    private var nonApportionableItems: [WirtschaftsplanLineItem] {
        (plan.lineItems ?? []).filter { !$0.isApportionable }.sorted { $0.costType < $1.costType }
    }

    var body: some View {
        List {
            Section {
                ForEach(apportionableItems) { item in
                    HStack {
                        Text(item.costType)
                        Spacer()
                        Text(item.amount.asCurrency)
                            .foregroundStyle(.secondary)
                    }
                }
                if plan.propertyTaxAmount > 0 {
                    HStack {
                        Text("Grundsteuer")
                        Spacer()
                        Text(plan.propertyTaxAmount.asCurrency)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Umlagefähige Betriebskosten gesamt", value: plan.totalApportionableCosts.asCurrency)
                    .font(.headline)
            } header: {
                Text("Umlagefähige Betriebskosten")
            }

            if !nonApportionableItems.isEmpty {
                Section {
                    ForEach(nonApportionableItems) { item in
                        HStack {
                            Text(item.costType)
                            Spacer()
                            Text(item.amount.asCurrency)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Nicht umlagefähige Betriebskosten gesamt", value: plan.nonApportionableLineItemsTotal.asCurrency)
                        .foregroundStyle(Theme.statusWarning)
                    LabeledContent("Monatliche Belastung (nicht umlagefähige Betriebskosten)", value: (plan.nonApportionableLineItemsTotal / 12).asCurrency)
                        .font(.headline)
                        .foregroundStyle(Theme.statusWarning)
                } header: {
                    Text("Nicht umlagefähige Betriebskosten")
                        .foregroundStyle(Theme.statusWarning)
                }
            }

            if !plan.reserveFundAccountInfo.isEmpty {
                Section("Instandhaltungsrücklagenkonto bei der Hausverwaltung") {
                    Text(plan.reserveFundAccountInfo)
                }
            }

            if !plan.notes.isEmpty {
                Section("Notizen") {
                    Text(plan.notes)
                }
            }
        }
        .navigationTitle("Wirtschaftsplan \(String(plan.year))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            WirtschaftsplanEditView(property: plan.property ?? Property(), plan: plan)
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let plan = (try? context.fetch(FetchDescriptor<WirtschaftsplanStatement>()))?.first ?? WirtschaftsplanStatement()
    return NavigationStack {
        WirtschaftsplanDetailView(plan: plan)
    }
    .modelContainer(PreviewData.container)
}
