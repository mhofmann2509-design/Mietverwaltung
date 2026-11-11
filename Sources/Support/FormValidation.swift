import SwiftUI

/// Gemeinsame Prüfregeln für Zahlenfelder in den Bearbeiten-Formularen. Jede Regel liefert eine
/// Fehlermeldung oder `nil`; Formulare sammeln die Meldungen, sperren damit „Sichern“ und zeigen
/// sie über `ValidationMessagesSection` an – statt unlesbare Eingaben stillschweigend als 0 zu
/// speichern.
enum FormValidation {
    enum Rule {
        case nonNegative
        case positive
        case percent
        case range(ClosedRange<Double>)
    }

    static func number(_ text: String, _ label: String, _ rule: Rule = .nonNegative, required: Bool = false) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return required ? "„\(label)“ fehlt." : nil }
        guard let value = DecimalInputParser.parse(trimmed) else { return "„\(label)“ ist keine gültige Zahl." }
        switch rule {
        case .nonNegative:
            return value >= 0 ? nil : "„\(label)“ darf nicht negativ sein."
        case .positive:
            return value > 0 ? nil : "„\(label)“ muss größer als 0 sein."
        case .percent:
            return (0...100).contains(value) ? nil : "„\(label)“ muss zwischen 0 und 100 % liegen."
        case .range(let range):
            return range.contains(value) ? nil : "„\(label)“ muss zwischen \(range.lowerBound.formatted()) und \(range.upperBound.formatted()) liegen."
        }
    }

    static func integer(_ text: String, _ label: String, _ range: ClosedRange<Int>, required: Bool = false) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return required ? "„\(label)“ fehlt." : nil }
        guard let value = Int(trimmed) else { return "„\(label)“ ist keine gültige ganze Zahl." }
        return range.contains(value) ? nil : "„\(label)“ muss zwischen \(range.lowerBound) und \(range.upperBound) liegen."
    }

    static var currentYear: Int { Calendar.current.component(.year, from: .now) }

    static func required(_ text: String, _ label: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "„\(label)“ fehlt." : nil
    }

    static func dateOrder(start: Date, end: Date?, startLabel: String = "Beginn", endLabel: String = "Ende") -> String? {
        guard let end, Calendar.current.startOfDay(for: end) < Calendar.current.startOfDay(for: start) else { return nil }
        return "„\(endLabel)“ liegt vor „\(startLabel)“."
    }
}

/// Zeigt die gesammelten Prüfmeldungen eines Formulars – leer, solange alles gültig ist.
struct ValidationMessagesSection: View {
    let messages: [String]

    var body: some View {
        if !messages.isEmpty {
            Section {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Bitte korrigieren, um zu sichern.")
            }
        }
    }
}
