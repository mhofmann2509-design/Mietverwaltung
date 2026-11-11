import Foundation

/// Portfolio-Kennzahlen eines Steuerjahres über mehrere Immobilien – Renditen gewichtet nach
/// Kaufpreis bzw. Investitionssumme (nicht als Durchschnitt der Einzelrenditen).
struct PortfolioMetrics {
    let properties: [Property]
    let year: Int
    /// Grenzsteuersatz des Vermieters in Prozent; `nil`, solange kein Vermieter erfasst ist.
    let marginalTaxRatePercent: Double?

    var grossYieldPercent: Double? {
        let relevant = properties.filter { $0.purchasePrice > 0 }
        let totalPrice = relevant.reduce(0.0) { $0 + $1.purchasePrice }
        guard totalPrice > 0 else { return nil }
        return relevant.reduce(0.0) { $0 + $1.annualColdRent(forYear: year) } / totalPrice * 100
    }

    var netYieldPercent: Double? {
        let relevant = properties.filter { $0.totalInvestment > 0 }
        let totalInvestment = relevant.reduce(0.0) { $0 + $1.totalInvestment }
        guard totalInvestment > 0 else { return nil }
        let netIncome = relevant.reduce(0.0) { $0 + $1.annualColdRent(forYear: year) - $1.totalExpenses(forYear: year) }
        return netIncome / totalInvestment * 100
    }

    var totalRent: Double { properties.reduce(0) { $0 + $1.annualColdRent(forYear: year) } }
    var totalWerbungskosten: Double { properties.reduce(0) { $0 + $1.werbungskosten(forYear: year) } }
    var totalAfa: Double { properties.reduce(0) { $0 + $1.totalAfa(forYear: year) } }
    var taxableResult: Double { properties.reduce(0) { $0 + $1.estimatedTaxableResult(forYear: year) } }
    var operativeCashFlow: Double { properties.reduce(0) { $0 + $1.operativeCashFlow(forYear: year) } }
    var freeCashFlow: Double { properties.reduce(0) { $0 + $1.freeCashFlow(forYear: year) } }

    /// Geschätzte Steuer auf einen Überschuss; ein Verlust wird mit 0 angesetzt (keine
    /// Verrechnung mit anderen Einkünften in dieser vereinfachten Schätzung).
    var estimatedTaxBurden: Double {
        guard let marginalTaxRatePercent else { return 0 }
        return max(0, taxableResult) * marginalTaxRatePercent / 100
    }

    var cashFlowAfterTax: Double { freeCashFlow - estimatedTaxBurden }
}
