import Foundation

/// Anteil eines Mietverhältnisses an den umlagefähigen Kosten einer Nebenkostenabrechnung.
struct UtilityAllocationShare {
    let unit: Unit
    let tenancy: Tenancy
    /// Anteil der Einheit am Umlageschlüssel (0…1), unabhängig von der Belegungsdauer.
    let unitWeight: Double
    /// Belegte Tage / Tage des Abrechnungszeitraums (0…1).
    let timeShare: Double
    /// Auf Cent gerundet, so verteilt, dass die Summe aller Zeilen exakt der gerundeten Summe der
    /// ungerundeten Anteile entspricht (bei Vollvermietung also exakt den umlagefähigen Kosten).
    let allocatedCost: Double
    let advancesPaid: Double
    /// Konkreter Anteil am Umlageschlüssel, z.B. „144/1.000“ oder „68/123 m²“.
    let keyDetail: String
}

/// Verteilung der umlagefähigen Kosten einer `UtilityStatement` auf die Mietverhältnisse – nach
/// Umlageschlüssel und tagesgenau anteilig bei unterjährigem Ein-/Auszug. Leerstand bleibt beim
/// Vermieter (Gewichte beziehen sich auf die gesamte Immobilie, nicht nur auf belegte Einheiten).
enum UtilityAllocationCalculator {
    static func shares(for statement: UtilityStatement) -> [UtilityAllocationShare] {
        guard let property = statement.property else { return [] }
        let totalDays = dayCount(from: statement.periodStart, to: statement.periodEnd)
        guard totalDays > 0 else { return [] }

        var pending: [(unit: Unit, tenancy: Tenancy, weight: Double, timeShare: Double, exact: Double)] = []
        for unit in property.units ?? [] {
            let unitWeight = weight(forUnit: unit, property: property, method: statement.allocationMethod, on: statement.periodEnd)
            guard unitWeight > 0 else { continue }
            for tenancy in unit.tenancies ?? [] {
                let days = tenancy.activeDays(from: statement.periodStart, to: statement.periodEnd)
                guard days > 0 else { continue }
                let timeShare = Double(days) / Double(totalDays)
                pending.append((unit, tenancy, unitWeight, timeShare, statement.totalApportionableCosts * unitWeight * timeShare))
            }
        }

        let rounded = distributeToCents(pending.map(\.exact))
        return zip(pending, rounded).map { entry, cost in
            UtilityAllocationShare(
                unit: entry.unit,
                tenancy: entry.tenancy,
                unitWeight: entry.weight,
                timeShare: entry.timeShare,
                allocatedCost: cost,
                advancesPaid: entry.tenancy.utilityAdvancesPaid(from: statement.periodStart, to: statement.periodEnd).roundedToCents,
                keyDetail: keyDetail(forUnit: entry.unit, property: property, method: statement.allocationMethod, on: statement.periodEnd)
            )
        }
    }

    /// Gewicht einer Einheit nach dem Umlageschlüssel, bezogen auf die gesamte Immobilie.
    static func weight(forUnit unit: Unit, property: Property, method: AllocationMethod, on date: Date) -> Double {
        switch method {
        case .livingSpace:
            let total = property.totalSizeSquareMeters
            return total > 0 ? unit.sizeSquareMeters / total : 0
        case .unitCount:
            let total = (property.units ?? []).count
            return total > 0 ? 1.0 / Double(total) : 0
        case .personCount:
            let total = (property.units ?? []).reduce(0) { $0 + persons(in: $1, on: date) }
            return total > 0 ? Double(persons(in: unit, on: date)) / Double(total) : 0
        case .coOwnershipShare:
            let total = property.totalCoOwnershipShare
            return total > 0 ? unit.coOwnershipShare / total : 0
        }
    }

    static func keyDetail(forUnit unit: Unit, property: Property, method: AllocationMethod, on date: Date) -> String {
        switch method {
        case .livingSpace:
            return "\(unit.sizeSquareMeters.formatted())/\(property.totalSizeSquareMeters.formatted()) m²"
        case .unitCount:
            return "1/\((property.units ?? []).count)"
        case .personCount:
            let total = (property.units ?? []).reduce(0) { $0 + persons(in: $1, on: date) }
            return "\(persons(in: unit, on: date))/\(total)"
        case .coOwnershipShare:
            return "\(unit.coOwnershipShare.formatted())/\(property.totalCoOwnershipShare.formatted())"
        }
    }

    /// Tage von `start` bis einschließlich `end`, beide auf Tagesbeginn normalisiert – dieselbe
    /// Zählweise wie `Tenancy.activeDays(from:to:)`, damit Zähler und Nenner zusammenpassen.
    static func dayCount(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? -1
        return max(0, days + 1)
    }

    /// Rundet auf Cent nach dem Largest-Remainder-Verfahren: Die gerundeten Werte ergeben in Summe
    /// exakt die auf Cent gerundete Gesamtsumme, statt dass sich Einzelrundungen zu Cent-Differenzen
    /// aufsummieren (z.B. 3 × 33,33 € = 99,99 € statt 100,00 €).
    static func distributeToCents(_ amounts: [Double]) -> [Double] {
        guard !amounts.isEmpty else { return [] }
        let targetCents = Int((amounts.reduce(0, +) * 100).rounded())
        let exactCents = amounts.map { $0 * 100 }
        var cents = exactCents.map { Int($0.rounded(.down)) }
        let remaining = targetCents - cents.reduce(0, +)
        let byRemainder = exactCents.indices.sorted { lhs, rhs in
            let l = exactCents[lhs] - exactCents[lhs].rounded(.down)
            let r = exactCents[rhs] - exactCents[rhs].rounded(.down)
            return l == r ? lhs < rhs : l > r
        }
        for index in byRemainder.prefix(max(0, remaining)) {
            cents[index] += 1
        }
        return cents.map { Double($0) / 100 }
    }

    private static func persons(in unit: Unit, on date: Date) -> Int {
        (unit.tenancies ?? []).filter { $0.isRunning(on: date) }.reduce(0) { $0 + $1.occupantCount }
    }
}
