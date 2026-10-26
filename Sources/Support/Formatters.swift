import Foundation

extension Double {
    /// Formats the value as a Euro amount, e.g. "1.234,50 €".
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "€"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: NSNumber(value: self)) ?? "\(self) €"
    }

    /// Kaufmännisch auf 2 Nachkommastellen (Cent) gerundet – für Geldbeträge, die als
    /// Zwischenergebnis weiterverwendet oder verglichen werden (z.B. Mieterverteilung), nicht nur
    /// für die reine Anzeige-Formatierung.
    var roundedToCents: Double {
        (self * 100).rounded() / 100
    }

    /// Formats the value (already a percentage, e.g. 4.5) as "4,5 %".
    var asPercent: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale(identifier: "de_DE")
        let number = formatter.string(from: NSNumber(value: self)) ?? "\(self)"
        return "\(number) %"
    }
}

extension Date {
    /// Formats the date as "16.12.2026" – fixed numeric day.month.year, independent of the
    /// device's locale/region setting, used for every date shown in the app.
    var asShortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: self)
    }

    var asMonthYear: String {
        self.formatted(.dateTime.month(.wide).year())
    }

    /// The first day of the month containing this date.
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
}
