import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddDocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.name) private var properties: [Property]
    @Query(sort: \Tenant.lastName) private var tenants: [Tenant]

    @State private var title = ""
    @State private var receiptDate = Date.now
    @State private var selectedProperty: Property?
    @State private var selectedUnit: Unit?
    @State private var selectedTenant: Tenant?

    @State private var pickedFileURL: URL?
    @State private var scannedImageData: Data?
    @State private var previewImage: PlatformImage?
    @State private var fileExtensionOverride: String?
    @State private var isRecognizingText = false

    @State private var recordAsExpense = false
    @State private var amountText = ""
    @State private var category: ExpenseCategory = .other
    @State private var taxTreatment: TaxTreatment = ExpenseCategory.other.defaultTaxTreatment

    @State private var showingFileImporter = false
    #if os(iOS)
    @State private var showingScanner = false
    #endif

    init(initialProperty: Property? = nil) {
        _selectedProperty = State(initialValue: initialProperty)
    }

    private var hasPickedSomething: Bool {
        pickedFileURL != nil || scannedImageData != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Beleg") {
                    #if os(iOS)
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Beleg scannen", systemImage: "doc.viewfinder")
                    }
                    #endif
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label(pickedFileURL?.lastPathComponent ?? "Datei auswählen", systemImage: "paperclip")
                    }

                    if let previewImage {
                        platformImage(previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if isRecognizingText {
                        HStack {
                            ProgressView()
                            Text("Text wird erkannt …")
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Titel", text: $title)
                    DatePicker("Belegdatum", selection: $receiptDate, displayedComponents: .date)
                }

                Section("Verknüpfung (optional)") {
                    Picker("Immobilie", selection: $selectedProperty) {
                        Text("Keine").tag(Optional<Property>.none)
                        ForEach(properties) { property in
                            Text(property.name).tag(Optional(property))
                        }
                    }
                    if let selectedProperty {
                        Picker("Einheit", selection: $selectedUnit) {
                            Text("Keine").tag(Optional<Unit>.none)
                            ForEach(selectedProperty.units ?? []) { unit in
                                Text(unit.name).tag(Optional(unit))
                            }
                        }
                    }
                    Picker("Mieter", selection: $selectedTenant) {
                        Text("Keiner").tag(Optional<Tenant>.none)
                        ForEach(tenants) { tenant in
                            Text(tenant.fullName).tag(Optional(tenant))
                        }
                    }
                }

                Section {
                    Toggle("Als Ausgabe erfassen (steuerlich)", isOn: $recordAsExpense)
                    if recordAsExpense {
                        TextField("Betrag (€)", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Picker("Kategorie", selection: $category) {
                            ForEach(ExpenseCategory.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                        .onChange(of: category) { _, newValue in
                            taxTreatment = newValue.defaultTaxTreatment
                        }
                        Picker("Steuerliche Behandlung", selection: $taxTreatment) {
                            ForEach(TaxTreatment.allCases) { option in
                                Label(option.shortLabel, systemImage: option.systemImage).tag(option)
                            }
                        }
                    }
                } footer: {
                    Text("Belege werden nach Belegdatum sortiert und lassen sich für die Steuererklärung gebündelt wieder abrufen.")
                }
            }
            .navigationTitle("Beleg erfassen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!hasPickedSomething)
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image, .data]) { result in
                handlePickedFile(result)
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentCameraScanner { image in
                    handleScannedImage(image)
                }
                .ignoresSafeArea()
            }
            #endif
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 480, idealHeight: 620, maxHeight: 780)
            #endif
        }
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        pickedFileURL = url
        scannedImageData = nil
        fileExtensionOverride = nil
        if title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }

        let imageExtensions = ["jpg", "jpeg", "png", "heic"]
        if imageExtensions.contains(url.pathExtension.lowercased()), let image = PlatformImage(data: data) {
            previewImage = image
            runTextRecognition(on: image)
        } else {
            previewImage = nil
        }
    }

    private func handleScannedImage(_ image: PlatformImage?) {
        guard let image else { return }
        #if os(iOS)
        scannedImageData = image.jpegData(compressionQuality: 0.85)
        #endif
        pickedFileURL = nil
        fileExtensionOverride = "jpg"
        previewImage = image
        runTextRecognition(on: image)
    }

    private func runTextRecognition(on image: PlatformImage) {
        isRecognizingText = true
        ReceiptTextExtractor.extract(from: image) { guess in
            isRecognizingText = false
            if let guessedTitle = guess.title, title.isEmpty || title == pickedFileURL?.deletingPathExtension().lastPathComponent {
                title = guessedTitle
            }
            if let date = guess.date {
                receiptDate = date
            }
            if let amount = guess.amount {
                amountText = String(amount)
                recordAsExpense = true
            }
        }
    }

    private func save() {
        let data: Data
        let fileName: String
        let fileExtension: String

        if let scannedImageData {
            data = scannedImageData
            fileName = title.isEmpty ? "Beleg.jpg" : "\(title).jpg"
            fileExtension = "jpg"
        } else if let pickedFileURL {
            let didStartAccessing = pickedFileURL.startAccessingSecurityScopedResource()
            defer { if didStartAccessing { pickedFileURL.stopAccessingSecurityScopedResource() } }
            guard let fileData = try? Data(contentsOf: pickedFileURL) else { return }
            data = fileData
            fileName = pickedFileURL.lastPathComponent
            fileExtension = fileExtensionOverride ?? pickedFileURL.pathExtension
        } else {
            return
        }

        let document = Document(title: title, fileName: fileName, fileExtension: fileExtension, data: data, receiptDate: receiptDate)
        document.property = selectedProperty
        document.unit = selectedUnit
        document.tenant = selectedTenant
        modelContext.insert(document)

        if recordAsExpense {
            let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let expense = Expense(date: receiptDate, amount: amount, category: category, title: title, taxTreatment: taxTreatment)
            expense.property = selectedProperty
            expense.unit = selectedUnit
            modelContext.insert(expense)
            document.expense = expense
        }

        dismiss()
    }
}

#Preview {
    AddDocumentView()
        .modelContainer(PreviewData.container)
}
