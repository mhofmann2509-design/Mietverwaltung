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
    @State private var showAncillaryCostsBreakdown = false
    @State private var purchaseTransferTaxCostsText = ""
    @State private var purchaseTransferTaxPaid = false
    @State private var purchaseBrokerCostsText = ""
    @State private var purchaseNotaryCostsText = ""
    @State private var purchaseLandRegistryCostsText = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date.now
    @State private var hasEconomicTransferDate = false
    @State private var economicTransferDate = Date.now

    @State private var roomCountText = ""
    @State private var totalUnitCountText = ""
    @State private var ownershipSharePercentText = ""

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

    private var validationMessages: [String] {
        var messages: [String?] = [
            name.trimmingCharacters(in: .whitespaces).isEmpty && street.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Bitte eine Bezeichnung oder Straße angeben." : nil,
            FormValidation.number(purchasePriceText, "Kaufpreis"),
            FormValidation.number(purchaseAncillaryCostsText, "Kaufnebenkosten"),
            FormValidation.number(landValueText, "Bodenwert"),
            FormValidation.integer(constructionYearText, "Baujahr", 1500...(FormValidation.currentYear + 5)),
            FormValidation.integer(roomCountText, "Anzahl der Zimmer", 0...10_000),
            FormValidation.integer(totalUnitCountText, "Einheiten insgesamt", 0...100_000),
            FormValidation.number(ownershipSharePercentText, "Eigentumsanteil", .range(0.01...100)),
            FormValidation.number(loanAmountText, "Darlehenssumme"),
            FormValidation.number(interestRateText, "Zinssatz", .percent),
            FormValidation.number(repaymentRateText, "Tilgungssatz", .percent)
        ]
        if showAncillaryCostsBreakdown {
            messages += [
                FormValidation.number(purchaseTransferTaxCostsText, "Grunderwerbsteuer"),
                FormValidation.number(purchaseBrokerCostsText, "Maklerkosten"),
                FormValidation.number(purchaseNotaryCostsText, "Notarkosten"),
                FormValidation.number(purchaseLandRegistryCostsText, "Auflassungsvormerkung/Grundbuch")
            ]
        }
        if hasAfaRateOverride {
            messages.append(FormValidation.number(afaRateOverrideText, "AfA-Satz", .range(0.01...100), required: true))
        }
        if let price = purchasePriceText.parsedDecimal, let land = landValueText.parsedDecimal, price > 0, land > price {
            messages.append("„Bodenwert“ ist höher als der Kaufpreis.")
        }
        return messages.compactMap { $0 }
    }

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

                generalDataSection

                Section {
                    TextField("Kaufpreis (€)", text: $purchasePriceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Kaufnebenkosten (€, z.B. Grunderwerbsteuer, Notar, Makler)", text: $purchaseAncillaryCostsText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Toggle("Kaufnebenkosten aufschlüsseln", isOn: $showAncillaryCostsBreakdown)
                    if showAncillaryCostsBreakdown {
                        TextField("davon Grunderwerbsteuer (€)", text: $purchaseTransferTaxCostsText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("davon Maklerkosten (€)", text: $purchaseBrokerCostsText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("davon Notarkosten (€)", text: $purchaseNotaryCostsText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("davon Auflassungsvormerkung/Grundbuch (€)", text: $purchaseLandRegistryCostsText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("Dient nur der Transparenz in der AfA-Herleitung; die Kaufnebenkosten-Summe oben bleibt für alle Berechnungen maßgeblich.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Kaufdatum (Beurkundung) bekannt", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Kaufdatum", selection: $purchaseDate, displayedComponents: .date)
                    }
                    Toggle("Übergang Nutzen und Lasten abweichend vom Kaufdatum", isOn: $hasEconomicTransferDate)
                    if hasEconomicTransferDate {
                        DatePicker("Übergang von Besitz, Nutzen und Lasten", selection: $economicTransferDate, displayedComponents: .date)
                    }
                    Toggle("Grunderwerbsteuer bezahlt", isOn: $purchaseTransferTaxPaid)
                    if let property, let gross = property.grossYieldPercent {
                        LabeledContent("Aktuelle Bruttorendite", value: gross.asPercent)
                    }
                } header: {
                    Text("Kauf & Rendite")
                } footer: {
                    Text("Übergang Nutzen und Lasten ist maßgeblich für den Beginn der Gebäude-AfA und der 15-%-Grenze – ohne Angabe gilt das Kaufdatum.")
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
                    if let loanAmount = loanAmountText.parsedDecimal,
                       let interestRate = interestRateText.parsedDecimal,
                       let repaymentRate = repaymentRateText.parsedDecimal,
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

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle(isNew ? "Neue Immobilie" : "Immobilie bearbeiten")
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
            // Deutlich mehr Höhenspielraum als bei den kürzeren Formularen (9 Abschnitte) – ein zu
            // knapper maxHeight-Wert relativ zum tatsächlichen Inhalt führte dazu, dass das Form
            // nicht mehr sauber scrollte und Text am unteren Rand abgeschnitten wirkte.
            .frame(minWidth: 480, idealWidth: 580, maxWidth: 680, minHeight: 560, idealHeight: 820, maxHeight: 980)
            #endif
        }
    }

    /// Ausgelagert, da sonst zu viele Statements im `Form`-ViewBuilder von `body` dem Typchecker
    /// Probleme bereiten (kaskadierende, irreführende „generic parameter could not be inferred“-
    /// Fehler an einer ganz anderen Stelle im Formular).
    @ViewBuilder
    private var generalDataSection: some View {
        Section {
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
            TextField("Eigener Anteil bei Miteigentum (%, nicht MEA einer ETW)", text: $ownershipSharePercentText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        } header: {
            Text("Allgemeine Daten")
        } footer: {
            Text("Eigentumsanteil aus Teilungserklärung oder Kaufvertrag – nur ausfüllen, wenn die Immobilie nicht zu 100 % im Alleineigentum steht. Unabhängig vom Miteigentumsanteil (MEA) einzelner Wohneinheiten.")
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
        showAncillaryCostsBreakdown = property.hasItemizedAncillaryCosts
        purchaseTransferTaxCostsText = property.purchaseTransferTaxCosts == 0 ? "" : String(property.purchaseTransferTaxCosts)
        purchaseTransferTaxPaid = property.purchaseTransferTaxPaid
        purchaseBrokerCostsText = property.purchaseBrokerCosts == 0 ? "" : String(property.purchaseBrokerCosts)
        purchaseNotaryCostsText = property.purchaseNotaryCosts == 0 ? "" : String(property.purchaseNotaryCosts)
        purchaseLandRegistryCostsText = property.purchaseLandRegistryCosts == 0 ? "" : String(property.purchaseLandRegistryCosts)
        if let date = property.purchaseDate {
            hasPurchaseDate = true
            purchaseDate = date
        }
        if let transferDate = property.economicTransferDate {
            hasEconomicTransferDate = true
            economicTransferDate = transferDate
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
        if let ownershipShare = property.ownershipSharePercent {
            ownershipSharePercentText = String(ownershipShare)
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
        let purchasePrice = purchasePriceText.parsedDecimal ?? 0
        let purchaseAncillaryCosts = purchaseAncillaryCostsText.parsedDecimal ?? 0
        let purchaseTransferTaxCosts = showAncillaryCostsBreakdown ? (purchaseTransferTaxCostsText.parsedDecimal ?? 0) : 0
        let purchaseBrokerCosts = showAncillaryCostsBreakdown ? (purchaseBrokerCostsText.parsedDecimal ?? 0) : 0
        let purchaseNotaryCosts = showAncillaryCostsBreakdown ? (purchaseNotaryCostsText.parsedDecimal ?? 0) : 0
        let purchaseLandRegistryCosts = showAncillaryCostsBreakdown ? (purchaseLandRegistryCostsText.parsedDecimal ?? 0) : 0
        let landValue = landValueText.parsedDecimal ?? 0
        let constructionYear = Int(constructionYearText)
        let roomCount = Int(roomCountText)
        let totalUnitCount = Int(totalUnitCountText)
        let ownershipSharePercent = ownershipSharePercentText.parsedDecimal
        let afaRateOverride = hasAfaRateOverride ? afaRateOverrideText.parsedDecimal : nil
        let loanAmount = loanAmountText.parsedDecimal ?? 0
        let interestRate = interestRateText.parsedDecimal ?? 0
        let repaymentRate = repaymentRateText.parsedDecimal ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let name = trimmedName.isEmpty ? street.trimmingCharacters(in: .whitespaces) : trimmedName

        if let property {
            property.name = name
            property.street = street
            property.zipCode = zipCode
            property.city = city
            property.notes = notes
            property.purchasePrice = purchasePrice
            property.purchaseAncillaryCosts = purchaseAncillaryCosts
            property.purchaseTransferTaxCosts = purchaseTransferTaxCosts
            property.purchaseTransferTaxPaid = purchaseTransferTaxPaid
            property.purchaseBrokerCosts = purchaseBrokerCosts
            property.purchaseNotaryCosts = purchaseNotaryCosts
            property.purchaseLandRegistryCosts = purchaseLandRegistryCosts
            property.purchaseDate = hasPurchaseDate ? purchaseDate : nil
            property.economicTransferDate = hasEconomicTransferDate ? economicTransferDate : nil
            property.landValue = landValue
            property.constructionYear = constructionYear
            property.roomCount = roomCount
            property.totalUnitCount = totalUnitCount
            property.ownershipSharePercent = ownershipSharePercent
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
            newProperty.ownershipSharePercent = ownershipSharePercent
            newProperty.economicTransferDate = hasEconomicTransferDate ? economicTransferDate : nil
            newProperty.purchaseTransferTaxCosts = purchaseTransferTaxCosts
            newProperty.purchaseTransferTaxPaid = purchaseTransferTaxPaid
            newProperty.purchaseBrokerCosts = purchaseBrokerCosts
            newProperty.purchaseNotaryCosts = purchaseNotaryCosts
            newProperty.purchaseLandRegistryCosts = purchaseLandRegistryCosts
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
