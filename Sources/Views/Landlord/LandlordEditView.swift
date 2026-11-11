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
    @State private var usesTaxAdvisor = false

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
                    Toggle("Steuererklärung durch Steuerberater", isOn: $usesTaxAdvisor)
                } header: {
                    Text("Steuer")
                } footer: {
                    Text("Persönlicher Grenzsteuersatz (ggf. inkl. Soli/Kirchensteuer) zur Abschätzung der Steuerlast aus dem steuerlichen Ergebnis aller Immobilien. Die Steuerberater-Angabe bestimmt die angezeigte gesetzliche Abgabefrist (§ 149 AO).")
                }

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle("Vermieter bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!validationMessages.isEmpty)
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
        email = landlord.email
        bankAccountHolder = landlord.bankAccountHolder
        iban = landlord.iban
        bic = landlord.bic
        marginalTaxRateText = String(landlord.marginalTaxRatePercent)
        usesTaxAdvisor = landlord.usesTaxAdvisor
    }

    private var validationMessages: [String] {
        [
            FormValidation.required(name, "Name"),
            FormValidation.number(marginalTaxRateText, "Grenzsteuersatz", .range(0...60))
        ].compactMap { $0 }
    }

    private func save() {
        landlord.name = name
        landlord.street = street
        landlord.zipCode = zipCode
        landlord.city = city
        landlord.email = email
        landlord.bankAccountHolder = bankAccountHolder
        landlord.iban = iban
        landlord.bic = bic
        landlord.marginalTaxRatePercent = marginalTaxRateText.parsedDecimal ?? landlord.marginalTaxRatePercent
        landlord.usesTaxAdvisor = usesTaxAdvisor
        dismiss()
    }
}

#Preview {
    LandlordEditView(landlord: Landlord())
        .modelContainer(PreviewData.container)
}
