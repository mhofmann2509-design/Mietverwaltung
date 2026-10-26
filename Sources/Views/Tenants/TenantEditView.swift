import SwiftUI
import SwiftData

struct TenantEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let tenant: Tenant?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var salutation: Salutation = .unspecified
    @State private var email = ""
    @State private var phone = ""
    @State private var previousAddress = ""
    @State private var bankAccountHolder = ""
    @State private var iban = ""
    @State private var bic = ""
    @State private var notes = ""

    private var isNew: Bool { tenant == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Anrede", selection: $salutation) {
                        ForEach(Salutation.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Anrede und Name werden z.B. für das Anschreiben der Nebenkostenabrechnung verwendet.")
                }
                Section("Kontakt") {
                    TextField("E-Mail", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Telefon", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                }
                Section {
                    TextField("Ehemalige Adresse", text: $previousAddress, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Frühere Anschrift")
                } footer: {
                    Text("Anschrift vor Einzug, z.B. für Übergabeprotokoll oder Mieterselbstauskunft.")
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
                } footer: {
                    Text("Für die Erstattung eines Guthabens aus der Nebenkostenabrechnung.")
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isNew ? "Neuer Mieter" : "Mieter bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(firstName.isEmpty && lastName.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 420, idealHeight: 580, maxHeight: 780)
            #endif
        }
    }

    private func loadExistingValues() {
        guard let tenant else { return }
        firstName = tenant.firstName
        lastName = tenant.lastName
        salutation = tenant.salutation
        email = tenant.email
        phone = tenant.phone
        previousAddress = tenant.previousAddress
        bankAccountHolder = tenant.bankAccountHolder
        iban = tenant.iban
        bic = tenant.bic
        notes = tenant.notes
    }

    private func save() {
        if let tenant {
            tenant.firstName = firstName
            tenant.lastName = lastName
            tenant.salutation = salutation
            tenant.email = email
            tenant.phone = phone
            tenant.previousAddress = previousAddress
            tenant.bankAccountHolder = bankAccountHolder
            tenant.iban = iban
            tenant.bic = bic
            tenant.notes = notes
        } else {
            let newTenant = Tenant(firstName: firstName, lastName: lastName, email: email, phone: phone, salutation: salutation, previousAddress: previousAddress, notes: notes, bankAccountHolder: bankAccountHolder, iban: iban, bic: bic)
            modelContext.insert(newTenant)
        }
        dismiss()
    }
}

#Preview {
    TenantEditView(tenant: nil)
        .modelContainer(PreviewData.container)
}
