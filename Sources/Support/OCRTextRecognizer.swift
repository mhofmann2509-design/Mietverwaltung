import Foundation
import Vision
import CoreGraphics
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Gemeinsame Texterkennung (Vision-Framework, läuft vollständig lokal auf dem Gerät) für Beleg-
/// und Dokumenten-Scans: erkennt Text und setzt Fragmente anhand ihrer vertikalen Position zu
/// vollständigen Zeilen zusammen. Vision zerlegt Tabellen/Dokumente mit breiten Abständen (z.B.
/// zwischen Bezeichnung und Wert) sonst oft in einzelne Fragmente statt zusammenhängender Zeilen.
enum OCRTextRecognizer {
    static func recognizeRows(from data: Data) -> [String] {
        guard let cgImage = cgImage(from: data) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }

        return groupIntoRows(observations)
    }

    private static func groupIntoRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        struct Fragment {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
        }

        let fragments: [Fragment] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return Fragment(text: text, midY: box.midY, minX: box.minX)
        }

        // Vision liefert Y-Koordinaten von unten (0) nach oben (1) – absteigend sortieren,
        // damit die Zeilen in Lesereihenfolge (oben nach unten) entstehen.
        let sorted = fragments.sorted { $0.midY > $1.midY }
        let tolerance: CGFloat = 0.007

        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let lastIndex = rows.indices.last, let referenceY = rows[lastIndex].first?.midY, abs(referenceY - fragment.midY) < tolerance {
                rows[lastIndex].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return image.cgImage
        #else
        guard let image = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
