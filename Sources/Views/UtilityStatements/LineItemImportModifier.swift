import SwiftUI
import UniformTypeIdentifiers

/// Kostenarten-Import (Beleg-Foto per OCR oder Excel/CSV-Datei) mit Prüf-Dialog – gemeinsam von
/// `UtilityStatementEditView` und `WirtschaftsplanEditView` genutzt.
private struct LineItemImportModifier: ViewModifier {
    private struct PendingImport: Identifiable {
        let id = UUID()
        let candidates: [LineItemDraft]
        let sourceDescription: String
        var skippedRowNumbers: [Int] = []
    }

    @Binding var lineItems: [LineItemDraft]
    @Binding var showingReceiptImporter: Bool
    @Binding var showingFileImporter: Bool

    @State private var pendingImport: PendingImport?
    @State private var errorMessage: String?
    @State private var busyMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $showingReceiptImporter, allowedContentTypes: [.image]) { result in
                handleReceiptImport(result)
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text, ExportFile.xlsx]) { result in
                handleFileImport(result)
            }
            .sheet(item: $pendingImport) { pending in
                LineItemImportReviewView(candidates: pending.candidates, sourceDescription: pending.sourceDescription, skippedRowNumbers: pending.skippedRowNumbers) { confirmed in
                    lineItems.removeAll { $0.costType.isEmpty && $0.amountText.isEmpty }
                    lineItems.append(contentsOf: confirmed)
                }
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .busyOverlay(busyMessage)
    }

    private func readData(_ result: Result<URL, Error>) -> (url: URL, data: Data)? {
        guard case .success(let url) = result else { return nil }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Die Datei „\(url.lastPathComponent)“ konnte nicht gelesen werden."
            return nil
        }
        return (url, data)
    }

    private func handleReceiptImport(_ result: Result<URL, Error>) {
        guard let (_, data) = readData(result) else { return }
        busyMessage = "Texterkennung läuft …"
        Task {
            let candidates = await BackgroundWork.run { ReceiptOCR.recognizeLineItems(from: data) }
            busyMessage = nil
            pendingImport = PendingImport(candidates: candidates, sourceDescription: "aus dem gescannten Beleg")
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard let (url, data) = readData(result) else { return }
        do {
            let parsed = try LineItemFileImporter.parse(from: url, data: data)
            pendingImport = PendingImport(candidates: parsed.items, sourceDescription: "aus der importierten Datei", skippedRowNumbers: parsed.skippedRowNumbers)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    func lineItemImport(lineItems: Binding<[LineItemDraft]>, showingReceiptImporter: Binding<Bool>, showingFileImporter: Binding<Bool>) -> some View {
        modifier(LineItemImportModifier(lineItems: lineItems, showingReceiptImporter: showingReceiptImporter, showingFileImporter: showingFileImporter))
    }
}
