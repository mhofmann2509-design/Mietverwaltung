import Foundation
import SwiftData

// Eingefrorener Stand des Datenmodells vor der Versionierung (Version 1.0.0).
//
// NICHT ÄNDERN: Diese Kopie muss exakt dem Modell entsprechen, mit dem alle bis Version 1
// angelegten Datenbanken erstellt wurden – nur so erkennt SwiftData bestehende Datenbanken und
// kann sie auf die aktuelle Version migrieren. Sie enthält nur die gespeicherten Felder, keine
// Logik. `MigrationTests` prüft die Übereinstimmung gegen eine echte V1-Datenbank.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Property.self, Unit.self, Tenant.self, Tenancy.self, RentStep.self, RentPayment.self,
            Expense.self, Document.self, DocumentFolder.self, DepreciableAsset.self,
            UtilityStatement.self, UtilityCostLineItem.self, UtilityStatementDispatch.self,
            Landlord.self, RemainingUsefulLifeAppraisal.self,
            WirtschaftsplanStatement.self, WirtschaftsplanLineItem.self,
            TrackedYear.self, TaxChecklistItem.self, TaxFilingStatus.self,
            ThreeYearThresholdCase.self, ThresholdExpenseAssessment.self, CapitalizationDecision.self,
            TravelExpense.self, HomeOfficeEntry.self, OwnersMeetingEvent.self,
        ]
    }

    @Model
    final class CapitalizationDecision {
        var decidedAt: Date = Date.now
        var effectiveYear: Int = Calendar.current.component(.year, from: .now)
        var reason: String = ""
        var property: Property?
        var thresholdCase: ThreeYearThresholdCase?
        var resultingAsset: DepreciableAsset?
        @Relationship(inverse: \Expense.capitalizationDecision)
        var sourceExpenses: [Expense]? = []
        init() {}
    }

    @Model
    final class DepreciableAsset {
        var name: String = ""
        var categoryRaw: String = "other"
        var cost: Double = 0
        var usefulLifeYears: Int = 10
        var placedInServiceDate: Date = Date.now
        var notes: String = ""
        var isUsed: Bool = false
        var estimatedValueAtAcquisition: Double = 0
        var isCoRented: Bool = false
        var vatRatePercent: Double?
        var property: Property?
        var unit: Unit?
        @Relationship(deleteRule: .cascade, inverse: \Document.depreciableAsset)
        var documents: [Document]? = []
        @Relationship(deleteRule: .nullify, inverse: \CapitalizationDecision.resultingAsset)
        var capitalizationDecisions: [CapitalizationDecision]? = []
        init() {}
    }

    @Model
    final class Document {
        var title: String = ""
        var fileName: String = ""
        var fileExtension: String = ""
        @Attribute(.externalStorage) var data: Data = Data()
        var addedAt: Date = Date.now
        var receiptDate: Date = Date.now
        var property: Property?
        var unit: Unit?
        var tenant: Tenant?
        var tenancy: Tenancy?
        var expense: Expense?
        var utilityStatement: UtilityStatement?
        var depreciableAsset: DepreciableAsset?
        var categoryRaw: String?
        var folder: DocumentFolder?
        @Relationship(deleteRule: .nullify, inverse: \OwnersMeetingEvent.invitationDocument)
        var ownersMeetingInvitations: [OwnersMeetingEvent]? = []
        @Relationship(deleteRule: .nullify, inverse: \TaxChecklistItem.linkedDocument)
        var linkedChecklistItems: [TaxChecklistItem]? = []
        init() {}
    }

    @Model
    final class DocumentFolder {
        var name: String = ""
        var categoryRaw: String = "propertyDocuments"
        var createdAt: Date = Date.now
        var property: Property?
        @Relationship(deleteRule: .nullify, inverse: \Document.folder)
        var documents: [Document]? = []
        init() {}
    }

    @Model
    final class Expense {
        var date: Date = Date.now
        var amount: Double = 0
        var categoryRaw: String = "other"
        var title: String = ""
        var notes: String = ""
        var taxTreatmentRaw: String = "otherDeductible"
        var vatRatePercent: Double?
        var receiptPending: Bool = false
        var completionDate: Date?
        var trade: String?
        var measureGroupID: UUID?
        var property: Property?
        var unit: Unit?
        @Relationship(deleteRule: .cascade, inverse: \Document.expense)
        var documents: [Document]? = []
        @Relationship(deleteRule: .cascade, inverse: \ThresholdExpenseAssessment.expense)
        var thresholdAssessments: [ThresholdExpenseAssessment]? = []
        var capitalizationDecision: CapitalizationDecision?
        init() {}
    }

    @Model
    final class HomeOfficeEntry {
        var taxYear: Int = Calendar.current.component(.year, from: Date.now)
        var days: Int = 0
        var dailyRate: Double = 6.0
        var property: Property?
        init() {}
    }

    @Model
    final class Landlord {
        var name: String = ""
        var street: String = ""
        var zipCode: String = ""
        var city: String = ""
        var email: String = ""
        var bankAccountHolder: String = ""
        var iban: String = ""
        var bic: String = ""
        var marginalTaxRatePercent: Double = 42
        var usesTaxAdvisor: Bool = false
        init() {}
    }

    @Model
    final class OwnersMeetingEvent {
        var title: String = "Eigentümerversammlung"
        var date: Date = Date.now
        var location: String = ""
        var notes: String = ""
        var calendarEventIdentifier: String?
        var property: Property?
        var invitationDocument: Document?
        init() {}
    }

    @Model
    final class Property {
        var name: String = ""
        var street: String = ""
        var zipCode: String = ""
        var city: String = ""
        var notes: String = ""
        var createdAt: Date = Date.now
        var roomCount: Int?
        var totalUnitCount: Int?
        var ownershipSharePercent: Double?
        var purchasePrice: Double = 0
        var purchaseAncillaryCosts: Double = 0
        var purchaseTransferTaxCosts: Double = 0
        var purchaseTransferTaxPaid: Bool = false
        var purchaseBrokerCosts: Double = 0
        var purchaseNotaryCosts: Double = 0
        var purchaseLandRegistryCosts: Double = 0
        var purchaseDate: Date?
        var economicTransferDate: Date?
        var landValue: Double = 0
        var constructionYear: Int?
        var afaRatePercentOverride: Double?
        var loanAmount: Double = 0
        var interestRatePercent: Double = 0
        var initialRepaymentRatePercent: Double = 0
        var loanStartDate: Date?
        var landlordName: String = ""
        var bankAccountHolder: String = ""
        var iban: String = ""
        var bic: String = ""
        @Relationship(deleteRule: .cascade, inverse: \Unit.property)
        var units: [Unit]? = []
        @Relationship(deleteRule: .cascade, inverse: \Expense.property)
        var expenses: [Expense]? = []
        @Relationship(deleteRule: .cascade, inverse: \Document.property)
        var documents: [Document]? = []
        @Relationship(deleteRule: .cascade, inverse: \DocumentFolder.property)
        var documentFolders: [DocumentFolder]? = []
        @Relationship(deleteRule: .cascade, inverse: \DepreciableAsset.property)
        var depreciableAssets: [DepreciableAsset]? = []
        @Relationship(deleteRule: .cascade, inverse: \UtilityStatement.property)
        var utilityStatements: [UtilityStatement]? = []
        @Relationship(deleteRule: .cascade, inverse: \RemainingUsefulLifeAppraisal.property)
        var remainingUsefulLifeAppraisals: [RemainingUsefulLifeAppraisal]? = []
        @Relationship(deleteRule: .cascade, inverse: \WirtschaftsplanStatement.property)
        var wirtschaftsplaene: [WirtschaftsplanStatement]? = []
        @Relationship(deleteRule: .cascade, inverse: \TaxChecklistItem.property)
        var taxChecklistItems: [TaxChecklistItem]? = []
        @Relationship(deleteRule: .cascade, inverse: \ThreeYearThresholdCase.property)
        var thresholdCases: [ThreeYearThresholdCase]? = []
        @Relationship(deleteRule: .cascade, inverse: \CapitalizationDecision.property)
        var capitalizationDecisions: [CapitalizationDecision]? = []
        @Relationship(deleteRule: .cascade, inverse: \TravelExpense.property)
        var travelExpenses: [TravelExpense]? = []
        @Relationship(deleteRule: .cascade, inverse: \HomeOfficeEntry.property)
        var homeOfficeEntries: [HomeOfficeEntry]? = []
        @Relationship(deleteRule: .cascade, inverse: \OwnersMeetingEvent.property)
        var ownersMeetings: [OwnersMeetingEvent]? = []
        init() {}
    }

    @Model
    final class RemainingUsefulLifeAppraisal {
        var createdAt: Date = Date.now
        var constructionYear: Int = Calendar.current.component(.year, from: .now)
        var valuationDate: Date = Date.now
        var totalUsefulLifeYears: Double = 80
        var roofPoints: Int = 0
        var facadePoints: Int = 0
        var windowsPoints: Int = 0
        var utilityLinesPoints: Int = 0
        var heatingPoints: Int = 0
        var bathroomsPoints: Int = 0
        var interiorPoints: Int = 0
        var floorPlanPoints: Int = 0
        var isCoreRenovation: Bool = false
        var notes: String = ""
        var property: Property?
        init() {}
    }

    @Model
    final class RentPayment {
        var dueDate: Date = Date.now
        var coldRentDue: Double = 0
        var utilityAdvanceDue: Double = 0
        var paidDate: Date?
        var paidAmount: Double?
        var note: String = ""
        var tenancy: Tenancy?
        init() {}
    }

    @Model
    final class RentStep {
        var effectiveDate: Date = Date.now
        var coldRent: Double = 0
        var tenancy: Tenancy?
        init() {}
    }

    @Model
    final class TaxChecklistItem {
        var title: String = ""
        var itemDescription: String = ""
        var statusRaw: String = "open"
        var modeRaw: String = "initialSetup"
        var taxYear: Int?
        var dueDate: Date?
        var completedAt: Date?
        var comment: String = ""
        var openQuestion: String = ""
        var createdAt: Date = Date.now
        var templateKey: String = ""
        var property: Property?
        var linkedDocument: Document?
        init() {}
    }

    @Model
    final class TaxFilingStatus {
        var taxYear: Int = Calendar.current.component(.year, from: .now) - 1
        var submittedAt: Date?
        var deadlineOverride: Date?
        init() {}
    }

    @Model
    final class Tenancy {
        var startDate: Date = Date.now
        var endDate: Date?
        var coldRent: Double = 0
        var utilityAdvance: Double = 0
        var deposit: Double = 0
        var depositReceived: Bool = false
        var depositReturnedAt: Date?
        var noticePeriodMonths: Int = 3
        var occupantCount: Int = 1
        var notes: String = ""
        var createdAt: Date = Date.now
        var contractTypeRaw: String = "standard"
        var lastRentIncreaseDate: Date?
        var lastIndexAdjustmentDate: Date?
        var modernizationAnnouncedAt: Date?
        var modernizationIncreaseDeclaredAt: Date?
        var unit: Unit?
        var tenant: Tenant?
        @Relationship(deleteRule: .cascade, inverse: \RentPayment.tenancy)
        var payments: [RentPayment]? = []
        @Relationship(deleteRule: .cascade, inverse: \Document.tenancy)
        var documents: [Document]? = []
        @Relationship(deleteRule: .cascade, inverse: \UtilityStatementDispatch.tenancy)
        var statementDispatches: [UtilityStatementDispatch]? = []
        @Relationship(deleteRule: .cascade, inverse: \RentStep.tenancy)
        var rentSteps: [RentStep]? = []
        init() {}
    }

    @Model
    final class Tenant {
        var firstName: String = ""
        var lastName: String = ""
        var email: String = ""
        var phone: String = ""
        var salutationRaw: String = "unspecified"
        var previousAddress: String = ""
        var notes: String = ""
        var createdAt: Date = Date.now
        var bankAccountHolder: String = ""
        var iban: String = ""
        var bic: String = ""
        @Relationship(deleteRule: .cascade, inverse: \Tenancy.tenant)
        var tenancies: [Tenancy]? = []
        @Relationship(deleteRule: .cascade, inverse: \Document.tenant)
        var documents: [Document]? = []
        init() {}
    }

    @Model
    final class ThreeYearThresholdCase {
        var periodStart: Date = Date.now
        var periodEnd: Date = Date.now
        var notes: String = ""
        var createdAt: Date = Date.now
        var manuallyClosed: Bool = false
        var property: Property?
        @Relationship(deleteRule: .cascade, inverse: \ThresholdExpenseAssessment.thresholdCase)
        var assessments: [ThresholdExpenseAssessment]? = []
        @Relationship(deleteRule: .nullify, inverse: \CapitalizationDecision.thresholdCase)
        var linkedCapitalizationDecisions: [CapitalizationDecision]? = []
        init() {}
    }

    @Model
    final class ThresholdExpenseAssessment {
        var statusRaw: String = "unclassified"
        var reason: String = ""
        var updatedAt: Date = Date.now
        var expense: Expense?
        var thresholdCase: ThreeYearThresholdCase?
        init() {}
    }

    @Model
    final class TrackedYear {
        var category: String = ""
        var year: Int = Calendar.current.component(.year, from: .now)
        init() {}
    }

    @Model
    final class TravelExpense {
        var date: Date = Date.now
        var purpose: String = ""
        var kilometers: Double = 0
        var ratePerKilometer: Double = 0.30
        var property: Property?
        init() {}
    }

    @Model
    final class Unit {
        var name: String = ""
        var sizeSquareMeters: Double = 0
        var rooms: Double = 0
        var notes: String = ""
        var createdAt: Date = Date.now
        var featureRawValues: [String] = []
        var coOwnershipShare: Double = 0
        var property: Property?
        @Relationship(deleteRule: .cascade, inverse: \Tenancy.unit)
        var tenancies: [Tenancy]? = []
        @Relationship(deleteRule: .cascade, inverse: \Expense.unit)
        var expenses: [Expense]? = []
        @Relationship(deleteRule: .cascade, inverse: \Document.unit)
        var documents: [Document]? = []
        @Relationship(deleteRule: .cascade, inverse: \DepreciableAsset.unit)
        var depreciableAssets: [DepreciableAsset]? = []
        init() {}
    }

    @Model
    final class UtilityStatement {
        var periodStart: Date = Date.now
        var periodEnd: Date = Date.now
        var allocationMethodRaw: String = "livingSpace"
        var propertyTaxAmount: Double = 0
        var reserveFundAccountInfo: String = ""
        var notes: String = ""
        var createdAt: Date = Date.now
        var property: Property?
        @Relationship(deleteRule: .cascade, inverse: \UtilityCostLineItem.statement)
        var lineItems: [UtilityCostLineItem]? = []
        @Relationship(deleteRule: .cascade, inverse: \Document.utilityStatement)
        var documents: [Document]? = []
        @Relationship(deleteRule: .cascade, inverse: \UtilityStatementDispatch.statement)
        var dispatches: [UtilityStatementDispatch]? = []
        init() {}
    }

    @Model
    final class UtilityCostLineItem {
        var costType: String = ""
        var amount: Double = 0
        var isApportionable: Bool = true
        var allocationKeyLabel: String = ""
        var statement: UtilityStatement?
        init() {}
    }

    @Model
    final class UtilityStatementDispatch {
        var sentDate: Date = Date.now
        var statement: UtilityStatement?
        var tenancy: Tenancy?
        init() {}
    }

    @Model
    final class WirtschaftsplanStatement {
        var year: Int = Calendar.current.component(.year, from: .now)
        var propertyTaxAmount: Double = 0
        var reserveFundAccountInfo: String = ""
        var notes: String = ""
        var createdAt: Date = Date.now
        var property: Property?
        @Relationship(deleteRule: .cascade, inverse: \WirtschaftsplanLineItem.statement)
        var lineItems: [WirtschaftsplanLineItem]? = []
        init() {}
    }

    @Model
    final class WirtschaftsplanLineItem {
        var costType: String = ""
        var amount: Double = 0
        var isApportionable: Bool = true
        var allocationKeyLabel: String = ""
        var statement: WirtschaftsplanStatement?
        init() {}
    }
}
