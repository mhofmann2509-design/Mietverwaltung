import Foundation

/// Einnahmen, Werbungskosten und Ergebnis der Anlage V einer Immobilie für ein Steuerjahr – die
/// eine gemeinsame Berechnung für Steuerreport, Steuer-Cockpit und Dashboard.
///
/// Einnahmen nach Zufluss (§ 11 EStG), vereinfacht dem Fälligkeitsmonat zugeordnet: erfasste
/// Zahlungen mit dem tatsächlich gezahlten Betrag, Monate ohne Zahlungseintrag mit dem Soll
/// (gezählt in `estimatedRentMonths`). Umlagen (Nebenkostenvorauszahlungen) sind Einnahmen, die
/// Betriebskosten lt. Nebenkostenabrechnung entsprechend Werbungskosten – Zuführungen zur
/// Instandhaltungsrücklage dagegen erst bei Verwendung (BFH-Rechtsprechung), sie bleiben außen vor.
struct AnlageVCalculation {
    let property: Property
    let year: Int

    let coldRentIncome: Double
    let utilityAdvanceIncome: Double
    let estimatedRentMonths: Int

    let buildingAfa: Double
    let movableAssetAfa: Double
    let improvementAssetAfa: Double
    let interest: Double
    let maintenance: Double
    let utilityCosts: Double
    let travel: Double
    let homeOffice: Double
    let otherDeductible: Double

    /// Ausgaben der Kategorie „Finanzierung“, nicht angesetzt, weil die Schuldzinsen bereits aus
    /// der hinterlegten Finanzierung berechnet werden (sonst doppelt).
    let excludedFinancingExpenses: [Expense]
    /// Ausgaben der Kategorie „Betriebskosten“, nicht angesetzt, weil für das Jahr eine
    /// Nebenkostenabrechnung mit denselben Kosten erfasst ist.
    let excludedUtilityExpenses: [Expense]
    /// Positionen der Nebenkostenabrechnung, die als Zuführung zur Instandhaltungsrücklage
    /// erkannt und deshalb nicht als Werbungskosten angesetzt wurden.
    let excludedReserveItems: [UtilityCostLineItem]

    init(property: Property, year: Int) {
        self.property = property
        self.year = year

        var cold = 0.0
        var utilityIncome = 0.0
        var estimated = 0
        for tenancy in (property.units ?? []).flatMap({ $0.tenancies ?? [] }) {
            let received = tenancy.receivedRent(inYear: year)
            cold += received.coldRent
            utilityIncome += received.utilityAdvances
            estimated += received.estimatedMonths
        }
        coldRentIncome = cold
        utilityAdvanceIncome = utilityIncome
        estimatedRentMonths = estimated

        let assets = property.depreciableAssets ?? []
        buildingAfa = property.buildingAfA(forYear: year)
        movableAssetAfa = assets.filter { $0.category != .improvement }.reduce(0.0) { $0 + $1.depreciation(forYear: year) }
        improvementAssetAfa = assets.filter { $0.category == .improvement }.reduce(0.0) { $0 + $1.depreciation(forYear: year) }
        interest = property.loanBreakdown(forYear: year)?.interest ?? 0
        maintenance = property.maintenanceExpenses(forYear: year)
        travel = property.travelExpenseTotal(forYear: year)
        homeOffice = property.homeOfficeAllowance(forYear: year)

        let statements = (property.utilityStatements ?? []).filter { $0.year == year }
        let reserveItems = statements.flatMap { $0.lineItems ?? [] }.filter { !$0.isApportionable && Self.isReserveContribution($0.costType) }
        excludedReserveItems = reserveItems
        utilityCosts = statements.reduce(0.0) { $0 + $1.totalApportionableCosts + $1.nonApportionableLineItemsTotal }
            - reserveItems.reduce(0.0) { $0 + $1.amount }

        let otherExpenses = property.allExpenses(forYear: year).filter { $0.taxTreatment == .otherDeductible }
        let financing = interest > 0 ? otherExpenses.filter { $0.category == .financing } : []
        let utilities = statements.isEmpty ? [] : otherExpenses.filter { $0.category == .utilities }
        excludedFinancingExpenses = financing
        excludedUtilityExpenses = utilities
        let excludedIDs = Set((financing + utilities).map(\.persistentModelID))
        otherDeductible = otherExpenses.filter { !excludedIDs.contains($0.persistentModelID) }.reduce(0.0) { $0 + $1.amount }
    }

    static func isReserveContribution(_ costType: String) -> Bool {
        let text = costType.lowercased()
        return text.contains("rücklage") || text.contains("ruecklage")
    }

    var totalIncome: Double { coldRentIncome + utilityAdvanceIncome }
    var totalAfa: Double { buildingAfa + movableAssetAfa + improvementAssetAfa }
    var werbungskostenWithoutAfa: Double { interest + maintenance + utilityCosts + travel + homeOffice + otherDeductible }
    var totalWerbungskosten: Double { totalAfa + werbungskostenWithoutAfa }
    var result: Double { totalIncome - totalWerbungskosten }

    /// Umlagen vereinnahmt, aber keine Betriebskosten erfasst – das Ergebnis wäre dann zu hoch.
    var utilityCostsMissing: Bool {
        utilityAdvanceIncome > 0 && utilityCosts == 0
            && !property.allExpenses(forYear: year).contains { $0.category == .utilities && $0.taxTreatment == .otherDeductible }
    }

    /// Eigentumsanteil unter 100 %, sofern erfasst.
    var ownershipSharePercent: Double? {
        guard let share = property.ownershipSharePercent, share > 0, share < 100 else { return nil }
        return share
    }

    var ownerShareOfResult: Double? {
        ownershipSharePercent.map { result * $0 / 100 }
    }
}
