import Foundation

/// Tilgungsplan – aus `PropertyDetailView` ausgelagert, damit er ohne Oberfläche testbar ist.
extension Property {
    /// Vollständiger Tilgungsverlauf ab Finanzierungsbeginn bis zur Volltilgung (oder maximal 60
    /// Jahre als Sicherheitsgrenze), jahresweise Zins/Tilgung/Restschuld.
    func amortizationSchedule() -> [(year: Int, interest: Double, principal: Double, remaining: Double)] {
        guard let loanStartDate, loanAmount > 0 else { return [] }
        var rows: [(year: Int, interest: Double, principal: Double, remaining: Double)] = []
        var year = Calendar.current.component(.year, from: loanStartDate)
        while rows.count < 60 {
            guard let breakdown = loanBreakdown(forYear: year) else { break }
            rows.append((year, breakdown.interest, breakdown.principal, breakdown.remainingBalance))
            if breakdown.remainingBalance <= 0.5 { break }
            year += 1
        }
        return rows
    }

    /// Monatsweiser Tilgungsplan für ein Jahr: die Jahreswerte aus `loanBreakdown(forYear:)`
    /// gleichmäßig auf die 12 Monate verteilt (vereinfachtes Annuitätendarlehen, keine echte
    /// monatliche Verzinsung) – die letzte Restschuld entspricht exakt der jahresweisen
    /// Berechnung, Zwischenmonate sind linear interpoliert.
    func monthlyAmortizationSchedule(forYear year: Int) -> [TilgungsplanReportDocument.MonthRow] {
        guard let yearBreakdown = loanBreakdown(forYear: year) else { return [] }
        let calendar = Calendar.current
        let startYear = loanStartDate.map { calendar.component(.year, from: $0) } ?? year
        let startOfYearBalance: Double = year <= startYear
            ? loanAmount
            : (loanBreakdown(forYear: year - 1)?.remainingBalance ?? loanAmount)

        let monthlyInterest = yearBreakdown.interest / 12
        let monthlyPrincipal = yearBreakdown.principal / 12
        var rows: [TilgungsplanReportDocument.MonthRow] = []
        var balance = startOfYearBalance
        for month in 1...12 {
            balance = month == 12 ? yearBreakdown.remainingBalance : max(0, balance - monthlyPrincipal)
            rows.append(.init(month: month, interest: monthlyInterest, principal: monthlyPrincipal, remainingBalance: balance))
        }
        return rows
    }
}
