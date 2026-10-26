import SwiftUI
import CoreGraphics
import PDFKit

/// Rendert eine SwiftUI-Ansicht als echtes (durchsuchbares) PDF – der Text wird dabei
/// direkt in den PDF-Kontext gezeichnet statt als Bild gerastert.
enum PDFExporter {
    @MainActor
    static func renderPDF(size: CGSize, @ViewBuilder content: () -> some View) -> Data? {
        let renderer = ImageRenderer(content: content().frame(width: size.width, height: size.height))
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        renderer.render { _, renderInContext in
            pdfContext.beginPDFPage(nil)
            renderInContext(pdfContext)
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()

        return data as Data
    }

    /// Hängt Dokumente (PDFs oder Bilder) als Anlage an ein bereits gerendertes PDF an.
    /// Nicht lesbare Anhänge werden stillschweigend übersprungen.
    static func appendingAttachments(_ attachments: [(data: Data, fileExtension: String)], to baseData: Data) -> Data {
        guard let combined = PDFDocument(data: baseData) else { return baseData }

        for attachment in attachments {
            if attachment.fileExtension.lowercased() == "pdf", let attachmentDocument = PDFDocument(data: attachment.data) {
                for index in 0..<attachmentDocument.pageCount {
                    if let page = attachmentDocument.page(at: index) {
                        combined.insert(page, at: combined.pageCount)
                    }
                }
            } else if let image = PlatformImage(data: attachment.data), let page = PDFPage(image: image) {
                combined.insert(page, at: combined.pageCount)
            }
        }

        return combined.dataRepresentation() ?? baseData
    }
}
