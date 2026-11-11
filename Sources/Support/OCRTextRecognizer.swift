import Foundation
import Vision
import CoreGraphics
import PDFKit
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
        if let pdfImage = cgImage(fromPDF: data) { return pdfImage }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return image.cgImage
        #else
        guard let image = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    /// Rendert die erste Seite eines PDFs in eine Bitmap, damit auch eingescannte/exportierte
    /// PDF-Belege (nicht nur Fotos) per Vision erkannt werden können – `UIImage`/`NSImage` können
    /// PDF-Daten nicht direkt als Bild dekodieren, sonst bliebe die Texterkennung bei PDF-Belegen
    /// stillschweigend leer.
    private static func cgImage(fromPDF data: Data) -> CGImage? {
        guard let pdfDocument = PDFDocument(data: data), let page = pdfDocument.page(at: 0) else { return nil }
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }

        let scale: CGFloat = 3
        let pixelSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
