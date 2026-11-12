import Foundation
import SwiftData

/// Verteilt die Homeoffice-Pauschale anteilig nach Tagesanteil auf die einzelnen Immobilien. Die
/// Jahresdeckelung (ab 2023 210 Tage/1.260 €, 2020–2022 120 Tage/600 €, § 4 Abs. 5 S. 1 Nr. 6c
/// i.V.m. § 9 Abs. 5 EStG) gilt pro
/// Person über ALLE Immobilien hinweg, nicht je Objekt – deshalb die objektübergreifende Abfrage
/// über den ModelContext statt einer reinen `Property`-Methode.
enum HomeOfficeAllocation {
    /// Gesetzlicher Tagessatz (§ 4 Abs. 5 Satz 1 Nr. 6c EStG): ab 2023 6 €, 2020–2022 5 €,
    /// davor gab es keine Tagespauschale (`nil`).
    static func dailyRate(forYear year: Int) -> Double? {
        if year >= 2023 { return 6 }
        if year >= 2020 { return 5 }
        return nil
    }

    /// Höchstzahl Tage pro Person und Jahr: ab 2023 210 (= 1.260 €), 2020–2022 120 (= 600 €).
    static func cappedDays(forYear year: Int) -> Int {
        year >= 2023 ? 210 : 120
    }

    static func annualCapAmount(forYear year: Int) -> Double {
        Double(cappedDays(forYear: year)) * (dailyRate(forYear: year) ?? 0)
    }

    private static func allEntries(for property: Property, taxYear: Int) -> [HomeOfficeEntry] {
        guard let context = property.modelContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<HomeOfficeEntry>())) ?? []
        return all.filter { $0.taxYear == taxYear }
    }

    /// Eigene Tage dieser Immobilie für das Steuerjahr.
    static func ownDays(for property: Property, taxYear: Int) -> Int {
        allEntries(for: property, taxYear: taxYear)
            .filter { $0.property?.persistentModelID == property.persistentModelID }
            .reduce(0) { $0 + $1.days }
    }

    /// Ob die 210-Tage-Grenze über alle Immobilien hinweg für dieses Steuerjahr überschritten ist.
    static func isCapExceeded(for property: Property, taxYear: Int) -> Bool {
        let total = allEntries(for: property, taxYear: taxYear).reduce(0) { $0 + $1.days }
        return total > cappedDays(forYear: taxYear)
    }

    /// Anteiliger, bereits gedeckelter Pauschalbetrag dieser Immobilie für das Steuerjahr.
    static func apportionedAmount(for property: Property, taxYear: Int) -> Double {
        let entries = allEntries(for: property, taxYear: taxYear)
        let totalDays = entries.reduce(0) { $0 + $1.days }
        guard totalDays > 0 else { return 0 }
        let ownDays = entries
            .filter { $0.property?.persistentModelID == property.persistentModelID }
            .reduce(0) { $0 + $1.days }
        guard ownDays > 0, let rate = dailyRate(forYear: taxYear) else { return 0 }
        let cappedTotal = min(Double(totalDays) * rate, annualCapAmount(forYear: taxYear))
        return cappedTotal * Double(ownDays) / Double(totalDays)
    }
}
