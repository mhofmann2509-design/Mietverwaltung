import SwiftUI
import SwiftData

/// Zeigt das Vermieterprofil (Einzelsatz) an und schätzt daraus, zusammen mit dem steuerlichen
/// Ergebnis aller Immobilien, die tatsächliche Steuerlast für ein Jahr ab.
struct LandlordView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var landlords: [Landlord]
    @Query(sort: \Property.name) private var properties: [Property]
    @State private var showingEditSheet = false
    @State private var selectedTaxYear = Calendar.current.component(.year, from: .now)

    private var landlord: Landlord? { landlords.first }

    private var availableTaxYears: [Int] {
        let years = Set(properties.flatMap { $0.availableTaxYears })
        return years.isEmpty ? [Calendar.current.component(.year, from: .now)] : years.sorted(by: >)
    }

    private var totalTaxableResultForSelectedYear: Double {
        properties.reduce(0) { $0 + $1.estimatedTaxableResult(forYear: selectedTaxYear) }
    }

    private func estimatedTaxBurden(for landlord: Landlord) -> Double {
        max(0, totalTaxableResultForSelectedYear) * landlord.marginalTaxRatePercent / 100
    }

    var body: some View {
        Group {
            if let landlord {
                List {
                    Section("Vermieter") {
                        Text(landlord.name.isEmpty ? "Noch kein Name hinterlegt" : landlord.name)
                        if !landlord.street.isEmpty || !landlord.zipCode.isEmpty || !landlord.city.isEmpty {
                            Text(landlord.address)
                                .foregroundStyle(.secondary)
                        }
                        if !landlord.email.isEmpty {
                            LabeledContent("E-Mail", value: landlord.email)
                        }
                    }

                    Section {
                        LabeledContent("Kontoinhaber", value: landlord.bankAccountHolder.isEmpty ? "–" : landlord.bankAccountHolder)
                        LabeledContent("IBAN", value: landlord.iban.isEmpty ? "–" : landlord.iban)
                        LabeledContent("BIC", value: landlord.bic.isEmpty ? "–" : landlord.bic)
                    } header: {
                        Text("Bankverbindung")
                    } footer: {
                        Text("Wird künftig auf Anschreiben wie der Nebenkostenabrechnung als Absender verwendet.")
                    }

                    Section {
                        LabeledContent("Grenzsteuersatz", value: landlord.marginalTaxRatePercent.asPercent)
                        Picker("Jahr", selection: $selectedTaxYear) {
                            ForEach(availableTaxYears, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        LabeledContent("Steuerl. Ergebnis \(String(selectedTaxYear)) (alle Immobilien)", value: totalTaxableResultForSelectedYear.asCurrency)
                        LabeledContent("Geschätzte Steuerlast \(String(selectedTaxYear))", value: estimatedTaxBurden(for: landlord).asCurrency)
                            .font(.headline)
                            .foregroundStyle(Theme.statusWarning)
                    } header: {
                        Text("Steuerliche Belastung")
                    } footer: {
                        Text("Grob geschätzt aus dem steuerlichen Ergebnis aller Immobilien × Grenzsteuersatz, bei steuerlichem Verlust 0 €. Vereinfachte Näherung, ersetzt keine Steuerberatung.")
                    }
                }
            } else {
                ContentUnavailableView(
                    "Kein Vermieterprofil",
                    systemImage: "person.text.rectangle",
                    description: Text("Wird automatisch angelegt.")
                )
            }
        }
        .themedScrollBackground()
        .navigationTitle("Vermieter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
            }
        }
        .task { ensureLandlordExists() }
        .sheet(isPresented: $showingEditSheet) {
            if let landlord {
                LandlordEditView(landlord: landlord)
            }
        }
    }

    private func ensureLandlordExists() {
        guard landlords.isEmpty else { return }
        modelContext.insert(Landlord())
    }
}

#Preview {
    NavigationStack {
        LandlordView()
    }
    .modelContainer(PreviewData.container)
}
