import Foundation
import SwiftData

/// Vereinfachte Berechnung der Restnutzungsdauer (RND) eines Wohngebäudes nach dem
/// Modernisierungsmodell der Anlage 2 ImmoWertV („Modell zur Ermittlung der Restnutzungsdauer
/// von Wohngebäuden bei Modernisierungen"). Für die steuerliche Anerkennung einer verkürzten
/// Nutzungsdauer nach § 7 Abs. 4 Satz 2 EStG ist weiterhin ein Gutachten eines öffentlich
/// bestellten und vereidigten Sachverständigen erforderlich – diese Berechnung dient nur der
/// eigenen Orientierung und Vorbereitung, nicht als Ersatz dafür.
@Model
final class RemainingUsefulLifeAppraisal {
    var createdAt: Date = Date.now
    /// Baujahr, das dieser Einschätzung zugrunde liegt (bei Kernsanierung das Jahr der Sanierung).
    var constructionYear: Int = Calendar.current.component(.year, from: .now)
    var valuationDate: Date = Date.now
    /// Gesamtnutzungsdauer in Jahren – für Wohngebäude aller Typen einheitlich 80 Jahre
    /// (Anlage 2 ImmoWertV), bei Bedarf anpassbar.
    var totalUsefulLifeYears: Double = 80

    // Modernisierungspunkte je Bauteil (0 = nicht modernisiert, Maximalwert = vollständig modernisiert)
    var roofPoints: Int = 0            // Dacherneuerung inkl. Wärmedämmung, max. 4
    var facadePoints: Int = 0          // Wärmedämmung der Außenwände, max. 4
    var windowsPoints: Int = 0         // Fenster und Außentüren, max. 2
    var utilityLinesPoints: Int = 0    // Leitungssysteme (Strom, Gas, Wasser, Abwasser), max. 2
    var heatingPoints: Int = 0         // Heizungsanlage, max. 2
    var bathroomsPoints: Int = 0       // Bäder, max. 2
    var interiorPoints: Int = 0        // Innenausbau (Decken, Fußböden, Treppen), max. 2
    var floorPlanPoints: Int = 0       // Wesentliche Verbesserung der Grundrissgestaltung, max. 2

    /// Bei einer Kernsanierung erlaubt das Modell eine RND von bis zu 90 % statt 70 % der GND.
    var isCoreRenovation: Bool = false
    var notes: String = ""

    var property: Property?

    init(constructionYear: Int = Calendar.current.component(.year, from: .now), valuationDate: Date = .now, totalUsefulLifeYears: Double = 80) {
        self.constructionYear = constructionYear
        self.valuationDate = valuationDate
        self.totalUsefulLifeYears = totalUsefulLifeYears
        self.createdAt = .now
    }

    static let roofMaxPoints = 4
    static let facadeMaxPoints = 4
    static let windowsMaxPoints = 2
    static let utilityLinesMaxPoints = 2
    static let heatingMaxPoints = 2
    static let bathroomsMaxPoints = 2
    static let interiorMaxPoints = 2
    static let floorPlanMaxPoints = 2

    var totalModernizationPoints: Int {
        roofPoints + facadePoints + windowsPoints + utilityLinesPoints + heatingPoints + bathroomsPoints + interiorPoints + floorPlanPoints
    }

    /// Einstufung nach Anlage 2 ImmoWertV, Tabelle 2.
    var modernizationGradeLabel: String {
        switch totalModernizationPoints {
        case 0...1: return "Nicht modernisiert"
        case 2...5: return "Kleine Modernisierungen im Rahmen der Instandhaltung"
        case 6...10: return "Mittlerer Modernisierungsgrad"
        case 11...17: return "Überwiegend modernisiert"
        default: return "Umfassend modernisiert"
        }
    }

    /// Gebäudealter zum Bewertungsstichtag in Jahren.
    var ageYears: Double {
        let calendar = Calendar.current
        let valuationYear = calendar.component(.year, from: valuationDate)
        return Double(max(0, valuationYear - constructionYear))
    }

    var relativeAgePercent: Double {
        guard totalUsefulLifeYears > 0 else { return 0 }
        return (ageYears / totalUsefulLifeYears) * 100
    }

    private struct Coefficients {
        let a: Double
        let b: Double
        let c: Double
        /// Relatives Alter (in %), ab dem statt der einfachen Formel (GND − Alter) die
        /// Modernisierungsformel greift.
        let thresholdPercent: Double
    }

    /// Koeffizienten a, b, c nach Anlage 2 ImmoWertV, Tabelle 3, je Modernisierungspunkt (0–20).
    private static let coefficientTable: [Int: Coefficients] = [
        0: Coefficients(a: 1.2500, b: 2.6250, c: 1.5250, thresholdPercent: 60),
        1: Coefficients(a: 1.2500, b: 2.6250, c: 1.5250, thresholdPercent: 60),
        2: Coefficients(a: 1.0767, b: 2.2757, c: 1.3878, thresholdPercent: 55),
        3: Coefficients(a: 0.9033, b: 1.9263, c: 1.2505, thresholdPercent: 55),
        4: Coefficients(a: 0.7300, b: 1.5770, c: 1.1133, thresholdPercent: 40),
        5: Coefficients(a: 0.6725, b: 1.4578, c: 1.0850, thresholdPercent: 35),
        6: Coefficients(a: 0.6150, b: 1.3385, c: 1.0567, thresholdPercent: 30),
        7: Coefficients(a: 0.5575, b: 1.2193, c: 1.0283, thresholdPercent: 25),
        8: Coefficients(a: 0.5000, b: 1.1000, c: 1.0000, thresholdPercent: 20),
        9: Coefficients(a: 0.4660, b: 1.0270, c: 0.9906, thresholdPercent: 19),
        10: Coefficients(a: 0.4320, b: 0.9540, c: 0.9811, thresholdPercent: 18),
        11: Coefficients(a: 0.3980, b: 0.8810, c: 0.9717, thresholdPercent: 17),
        12: Coefficients(a: 0.3640, b: 0.8080, c: 0.9622, thresholdPercent: 16),
        13: Coefficients(a: 0.3300, b: 0.7350, c: 0.9528, thresholdPercent: 15),
        14: Coefficients(a: 0.3040, b: 0.6760, c: 0.9506, thresholdPercent: 14),
        15: Coefficients(a: 0.2780, b: 0.6170, c: 0.9485, thresholdPercent: 13),
        16: Coefficients(a: 0.2520, b: 0.5580, c: 0.9463, thresholdPercent: 12),
        17: Coefficients(a: 0.2260, b: 0.4990, c: 0.9442, thresholdPercent: 11),
        18: Coefficients(a: 0.2000, b: 0.4400, c: 0.9420, thresholdPercent: 10),
        19: Coefficients(a: 0.2000, b: 0.4400, c: 0.9420, thresholdPercent: 10),
        20: Coefficients(a: 0.2000, b: 0.4400, c: 0.9420, thresholdPercent: 10),
    ]

    /// Restnutzungsdauer (RND) in Jahren nach dem vereinfachten Modernisierungsmodell der
    /// Anlage 2 ImmoWertV. Unterhalb der modellspezifischen Alters-Schwelle gilt die einfache
    /// Formel RND = Gesamtnutzungsdauer − Alter; oberhalb greift die daran stetig anschließende
    /// quadratische Modellformel RND = a·Alter²/GND − b·Alter + c·GND. Die RND wird auf höchstens
    /// 70 % (bei Kernsanierung 90 %) der Gesamtnutzungsdauer begrenzt.
    var remainingUsefulLifeYears: Double {
        guard totalUsefulLifeYears > 0 else { return 0 }
        let points = min(20, max(0, totalModernizationPoints))
        let coefficients = Self.coefficientTable[points] ?? Self.coefficientTable[0]!

        let rawRND: Double
        if relativeAgePercent < coefficients.thresholdPercent {
            rawRND = totalUsefulLifeYears - ageYears
        } else {
            rawRND = coefficients.a * ageYears * ageYears / totalUsefulLifeYears
                - coefficients.b * ageYears
                + coefficients.c * totalUsefulLifeYears
        }

        let capPercent = isCoreRenovation ? 0.9 : 0.7
        let cappedRND = min(rawRND, totalUsefulLifeYears * capPercent)
        return max(1, cappedRND)
    }

    /// Aus der RND abgeleiteter linearer AfA-Satz (100 / RND), gerundet auf eine Nachkommastelle.
    var suggestedAfaRatePercent: Double {
        guard remainingUsefulLifeYears > 0 else { return 0 }
        return (100 / remainingUsefulLifeYears * 10).rounded() / 10
    }
}
