import SwiftUI
import SwiftData

struct LandlordEditView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var landlord: Landlord

    @State private var name = ""
    @State private var street = ""
    @State private var zipCode = ""
    @State private var city = ""
    @State private var email = ""
    @State private var bankAccountHolder = ""
    @State private var iban = ""
    @State private var bic = ""
    @State private var marginalTaxRateText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Vermieter") {
                    TextField("Name", text: $name)
                }
                Section("Kontakt") {
                    TextField("E-Mail", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Section("Adresse") {
                    TextField("Straße & Hausnummer", text: $street)
                    TextField("Postleitzahl", text: $zipCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Stadt", text: $city)
                }
                Section {
                    TextField("Kontoinhaber", text: $bankAccountHolder)
                    TextField("IBAN", text: $iban)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    TextField("BIC", text: $bic)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                } header: {
                    Text("Bankverbindung")
                }
                Section {
                    TextField("Grenzsteuersatz (%)", text: $marginalTaxRateText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                } header: {
                    Text("Steuer")
                } footer: {
                    Text("Persönlicher Grenzsteuersatz (ggf. inkl. Soli/Kirchensteuer) zur Abschätzung der Steuerlast aus dem steuerlichen Ergebnis aller Immobilien.")
                }
            }
            .navigationTitle("Vermieter bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 460, idealHeight: 620, maxHeight: 780)
            #endif
        }
    }

    private func loadExistingValues() {
        name = landlord.name
        street = landlord.street
        zipCode = landlord.zipCode
        city = landlord.city
        bankAccountHolder = landlord.bankAccountHolder
        iban = landlord.iban
        bic = landlord.bic
        marginalTaxRateText = String(landlord.marginalTaxRatePercent)
    }

    private func save() {
        landlord.name = name
        landlord.street = street
        landlord.zipCode = zipCode
        landlord.city = city
        landlord.bankAccountHolder = bankAccountHolder
        landlord.iban = iban
        landlord.bic = bic
        landlord.marginalTaxRatePercent = Double(marginalTaxRateText.replacingOccurrences(of: ",", with: ".")) ?? landlord.marginalTaxRatePercent
        dismiss()
    }
}

#Preview {
    LandlordEditView(landlord: Landlord())
        .modelContainer(PreviewData.container)
}
