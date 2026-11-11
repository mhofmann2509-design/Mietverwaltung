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
    @State private var selectedCategory: DocumentCategory
    private let initialFolder: DocumentFolder?

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
    @State private var saveErrorMessage: String?
    #if os(iOS)
    @State private var showingScanner = false
    #endif

    init(initialProperty: Property? = nil, initialCategory: DocumentCategory? = nil, initialFolder: DocumentFolder? = nil) {
        _selectedProperty = State(initialValue: initialProperty)
        _selectedCategory = State(initialValue: initialFolder?.category ?? initialCategory ?? .propertyDocuments)
        self.initialFolder = initialFolder
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
                    if let initialFolder {
                        LabeledContent("Ordner", value: initialFolder.name)
                    } else {
                        Picker("Reiter", selection: $selectedCategory) {
                            ForEach(DocumentCategory.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                    }
                }

                Section("Verknüpfung (optional)") {
                    if initialFolder != nil, let selectedProperty {
                        // Die Immobilie ist durch den Ordner festgelegt – ein frei wählbarer Picker
                        // könnte sonst ein Dokument anlegen, dessen Immobilie nicht zu dem Ordner
                        // passt, in dem es abgelegt wird (der Ordner bestimmt den Reiter/die
                        // Immobilie, in der es später gefunden wird).
                        LabeledContent("Immobilie", value: selectedProperty.name.isEmpty ? selectedProperty.address : selectedProperty.name)
                    } else {
                        Picker("Immobilie", selection: $selectedProperty) {
                            Text("Keine").tag(Optional<Property>.none)
                            ForEach(properties) { property in
                                Text(property.name).tag(Optional(property))
                            }
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
                        .onChange(of: recordAsExpense) { _, newValue in
                            if newValue, initialFolder == nil { selectedCategory = .invoicesReceipts }
                        }
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

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle("Beleg erfassen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!hasPickedSomething || !validationMessages.isEmpty)
                }
            }
            .alert("Beleg konnte nicht gesichert werden", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
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

    private var validationMessages: [String] {
        guard recordAsExpense else { return [] }
        return [FormValidation.number(amountText, "Betrag", .positive, required: true)].compactMap { $0 }
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
            guard let fileData = try? Data(contentsOf: pickedFileURL) else {
                saveErrorMessage = "Die Datei „\(pickedFileURL.lastPathComponent)“ ist nicht mehr lesbar – z.B. weil das Laufwerk getrennt oder die iCloud-Datei noch nicht geladen wurde. Bitte die Datei erneut auswählen."
                return
            }
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
        document.folder = initialFolder
        document.category = initialFolder?.category ?? selectedCategory
        modelContext.insert(document)

        if recordAsExpense {
            let amount = amountText.parsedDecimal ?? 0
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
