import Foundation
import Vision

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

#if os(macOS)
extension NSImage {
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif

/// Aus Texterkennung (OCR) gewonnene Vorschläge für einen gescannten Beleg.
/// Nichts davon ist verbindlich – der Nutzer kann jedes Feld vor dem Sichern korrigieren.
struct ReceiptGuess {
    var date: Date?
    var amount: Double?
    var title: String?
}

enum ReceiptTextExtractor {
    /// Erkennt Text auf dem Bild eines gescannten Belegs und versucht daraus Datum,
    /// Betrag und einen Titel (meist die oberste Zeile, z.B. der Firmenname) zu erraten.
    static func extract(from image: PlatformImage, completion: @escaping (ReceiptGuess) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(ReceiptGuess())
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let guess = parse(lines: lines)
            DispatchQueue.main.async {
                completion(guess)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private static func parse(lines: [String]) -> ReceiptGuess {
        var guess = ReceiptGuess()
        guess.title = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })

        // Betrag: bevorzugt eine Zeile mit "Summe"/"Gesamt"/"Betrag"/"Total", sonst der größte
        // gefundene Geldbetrag im gesamten Text (auf einem Beleg meist die Endsumme).
        let amountPattern = #"(\d{1,3}(?:[.\s]\d{3})*,\d{2})\s*€?"#
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern) else {
            return finishDate(lines: lines, guess: guess)
        }

        func amounts(in text: String) -> [Double] {
            let range = NSRange(text.startIndex..., in: text)
            return amountRegex.matches(in: text, range: range).compactMap { match in
                guard let r = Range(match.range(at: 1), in: text) else { return nil }
                let raw = String(text[r])
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                return Double(raw)
            }
        }

        let keywordLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("summe") || lower.contains("gesamt") || lower.contains("betrag") || lower.contains("total")
        }
        if let fromKeyword = keywordLines.flatMap({ amounts(in: $0) }).max() {
            guess.amount = fromKeyword
        } else {
            let all = lines.flatMap { amounts(in: $0) }
            guess.amount = all.max()
        }

        return finishDate(lines: lines, guess: guess)
    }

    private static func finishDate(lines: [String], guess: ReceiptGuess) -> ReceiptGuess {
        var guess = guess
        let datePattern = #"\b(\d{1,2})[.\/](\d{1,2})[.\/](\d{2,4})\b"#
        guard let dateRegex = try? NSRegularExpression(pattern: datePattern) else { return guess }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = dateRegex.firstMatch(in: line, range: range) else { continue }
            guard let dayRange = Range(match.range(at: 1), in: line),
                  let monthRange = Range(match.range(at: 2), in: line),
                  let yearRange = Range(match.range(at: 3), in: line),
                  let day = Int(line[dayRange]),
                  let month = Int(line[monthRange]),
                  var year = Int(line[yearRange]) else { continue }
            if year < 100 { year += 2000 }
            guard (1...31).contains(day), (1...12).contains(month) else { continue }

            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year
            if let date = Calendar.current.date(from: components), date <= Date.now {
                guess.date = date
                break
            }
        }
        return guess
    }
}
