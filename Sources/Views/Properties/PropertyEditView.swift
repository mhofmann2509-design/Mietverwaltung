import SwiftUI
import SwiftData

struct PropertyEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property?

    @State private var name = ""
    @State private var street = ""
    @State private var zipCode = ""
    @State private var city = ""
    @State private var notes = ""

    @State private var purchasePriceText = ""
    @State private var purchaseAncillaryCostsText = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date.now

    @State private var roomCountText = ""
    @State private var totalUnitCountText = ""

    @State private var landValueText = ""
    @State private var constructionYearText = ""
    @State private var hasAfaRateOverride = false
    @State private var afaRateOverrideText = ""

    @State private var loanAmountText = ""
    @State private var interestRateText = ""
    @State private var repaymentRateText = ""
    @State private var hasLoanStartDate = false
    @State private var loanStartDate = Date.now

    @State private var landlordName = ""

    @State private var bankAccountHolder = ""
    @State private var iban = ""
    @State private var bic = ""

    private var isNew: Bool { property == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Immobilie") {
                    TextField("Bezeichnung (z.B. Musterstraße 1)", text: $name)
                }
                Section("Adresse") {
                    TextField("Straße & Hausnummer", text: $street)
                    TextField("Postleitzahl", text: $zipCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Stadt", text: $city)
                }

                Section("Allgemeine Daten") {
                    TextField("Baujahr", text: $constructionYearText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Anzahl der Zimmer (gesamt)", text: $roomCountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Einheiten insgesamt lt. Teilungserklärung", text: $totalUnitCountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Section("Kauf & Rendite") {
                    TextField("Kaufpreis (€)", text: $purchasePriceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Kaufnebenkosten (€, z.B. Grunderwerbsteuer, Notar, Makler)", text: $purchaseAncillaryCostsText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Kaufdatum bekannt", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Kaufdatum", selection: $purchaseDate, displayedComponents: .date)
                    }
                    if let property, let gross = property.grossYieldPercent {
                        LabeledContent("Aktuelle Bruttorendite", value: gross.asPercent)
                    }
                }

                Section {
                    TextField("Bodenwert (€, nicht abschreibbar)", text: $landValueText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("AfA-Satz manuell festlegen", isOn: $hasAfaRateOverride)
                    if hasAfaRateOverride {
                        TextField("AfA-Satz (%)", text: $afaRateOverrideText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } else if let property {
                        LabeledContent("Automatischer AfA-Satz", value: property.defaultAfaRatePercent.asPercent)
                    }
                } header: {
                    Text("Abschreibung (AfA)")
                } footer: {
                    Text("Der AfA-Satz wird – falls nicht manuell gesetzt – aus dem Baujahr abgeleitet (§7 Abs. 4 EStG, vereinfacht).")
                }

                Section {
                    TextField("Darlehenssumme (€)", text: $loanAmountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Zinssatz (% p.a.)", text: $interestRateText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Anfänglicher Tilgungssatz (% p.a.)", text: $repaymentRateText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Finanzierungsbeginn bekannt", isOn: $hasLoanStartDate)
                    if hasLoanStartDate {
                        DatePicker("Finanzierungsbeginn", selection: $loanStartDate, displayedComponents: .date)
                    }
                    if let loanAmount = Double(loanAmountText.replacingOccurrences(of: ",", with: ".")),
                       let interestRate = Double(interestRateText.replacingOccurrences(of: ",", with: ".")),
                       let repaymentRate = Double(repaymentRateText.replacingOccurrences(of: ",", with: ".")),
                       loanAmount > 0 {
                        LabeledContent("Rate/Jahr (Annuität)", value: (loanAmount * (interestRate + repaymentRate) / 100).asCurrency)
                    }
                } header: {
                    Text("Finanzierung")
                } footer: {
                    Text("Vereinfachtes Annuitätendarlehen ohne Sondertilgungen/Zinsanpassung – für Rate-, Zins-/Tilgungs- und Cashflow-Berechnung.")
                }

                Section {
                    TextField("Name des Vermieters", text: $landlordName)
                } header: {
                    Text("Absender")
                } footer: {
                    Text("Wird als Unterschrift auf Anschreiben wie der Nebenkostenabrechnung verwendet.")
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
                    Text("Wird auf der Nebenkostenabrechnung angegeben, falls ein Mieter eine Nachzahlung leisten muss.")
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isNew ? "Neue Immobilie" : "Immobilie bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(name.isEmpty && street.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            // Deutlich mehr Höhenspielraum als bei den kürzeren Formularen (9 Abschnitte) – ein zu
            // knapper maxHeight-Wert relativ zum tatsächlichen Inhalt führte dazu, dass das Form
            // nicht mehr sauber scrollte und Text am unteren Rand abgeschnitten wirkte.
            .frame(minWidth: 480, idealWidth: 580, maxWidth: 680, minHeight: 560, idealHeight: 820, maxHeight: 980)
            #endif
        }
    }

    private func loadExistingValues() {
        guard let property else { return }
        name = property.name
        street = property.street
        zipCode = property.zipCode
        city = property.city
        notes = property.notes
        purchasePriceText = property.purchasePrice == 0 ? "" : String(property.purchasePrice)
        purchaseAncillaryCostsText = property.purchaseAncillaryCosts == 0 ? "" : String(property.purchaseAncillaryCosts)
        if let date = property.purchaseDate {
            hasPurchaseDate = true
            purchaseDate = date
        }
        landValueText = property.landValue == 0 ? "" : String(property.landValue)
        if let year = property.constructionYear {
            constructionYearText = String(year)
        }
        if let roomCount = property.roomCount {
            roomCountText = String(roomCount)
        }
        if let totalUnitCount = property.totalUnitCount {
            totalUnitCountText = String(totalUnitCount)
        }
        if let override = property.afaRatePercentOverride {
            hasAfaRateOverride = true
            afaRateOverrideText = String(override)
        }
        loanAmountText = property.loanAmount == 0 ? "" : String(property.loanAmount)
        interestRateText = property.interestRatePercent == 0 ? "" : String(property.interestRatePercent)
        repaymentRateText = property.initialRepaymentRatePercent == 0 ? "" : String(property.initialRepaymentRatePercent)
        if let loanStart = property.loanStartDate {
            hasLoanStartDate = true
            loanStartDate = loanStart
        }
        landlordName = property.landlordName
        bankAccountHolder = property.bankAccountHolder
        iban = property.iban
        bic = property.bic
    }

    private func save() {
        let purchasePrice = Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let purchaseAncillaryCosts = Double(purchaseAncillaryCostsText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let landValue = Double(landValueText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let constructionYear = Int(constructionYearText)
        let roomCount = Int(roomCountText)
        let totalUnitCount = Int(totalUnitCountText)
        let afaRateOverride = hasAfaRateOverride ? Double(afaRateOverrideText.replacingOccurrences(of: ",", with: ".")) : nil
        let loanAmount = Double(loanAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let interestRate = Double(interestRateText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let repaymentRate = Double(repaymentRateText.replacingOccurrences(of: ",", with: ".")) ?? 0

        if let property {
            property.name = name
            property.street = street
            property.zipCode = zipCode
            property.city = city
            property.notes = notes
            property.purchasePrice = purchasePrice
            property.purchaseAncillaryCosts = purchaseAncillaryCosts
            property.purchaseDate = hasPurchaseDate ? purchaseDate : nil
            property.landValue = landValue
            property.constructionYear = constructionYear
            property.roomCount = roomCount
            property.totalUnitCount = totalUnitCount
            property.afaRatePercentOverride = afaRateOverride
            property.loanAmount = loanAmount
            property.interestRatePercent = interestRate
            property.initialRepaymentRatePercent = repaymentRate
            property.loanStartDate = hasLoanStartDate ? loanStartDate : nil
            property.landlordName = landlordName
            property.bankAccountHolder = bankAccountHolder
            property.iban = iban
            property.bic = bic
        } else {
            let newProperty = Property(
                name: name, street: street, zipCode: zipCode, city: city, notes: notes,
                purchasePrice: purchasePrice,
                purchaseAncillaryCosts: purchaseAncillaryCosts,
                purchaseDate: hasPurchaseDate ? purchaseDate : nil,
                landValue: landValue,
                constructionYear: constructionYear
            )
            newProperty.roomCount = roomCount
            newProperty.totalUnitCount = totalUnitCount
            newProperty.afaRatePercentOverride = afaRateOverride
            newProperty.loanAmount = loanAmount
            newProperty.interestRatePercent = interestRate
            newProperty.initialRepaymentRatePercent = repaymentRate
            newProperty.loanStartDate = hasLoanStartDate ? loanStartDate : nil
            newProperty.landlordName = landlordName
            newProperty.bankAccountHolder = bankAccountHolder
            newProperty.iban = iban
            newProperty.bic = bic
            modelContext.insert(newProperty)
        }
        dismiss()
    }
}

#Preview {
    PropertyEditView(property: nil)
        .modelContainer(PreviewData.container)
}
