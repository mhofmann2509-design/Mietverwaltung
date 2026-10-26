import Foundation

/// Ein in Bearbeitung befindlicher Eintrag für eine Kostenart der Nebenkostenabrechnung –
/// gemeinsam genutzt vom manuellen Formular, dem OCR-Beleg-Scan und dem Excel/CSV-Import.
struct LineItemDraft: Identifiable {
    let id = UUID()
    var costType: String
    var amountText: String
    var isApportionable: Bool = true
    /// Optionaler Umlageschlüssel laut Hausverwaltung für genau diese Kostenart, z.B. „MEA (4)“
    /// oder „lt.An (11)“ – manche Hausverwaltungen rechnen je Kostenart mit einem anderen
    /// Schlüssel ab. Rein informativ, verändert nicht die App-eigene Mieterverteilung.
    var allocationKeyLabel: String?
}
