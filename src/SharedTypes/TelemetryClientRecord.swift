import CloudKit
import Foundation

public struct TelemetryClientRecord: Sendable {
    public enum Error: Swift.Error, LocalizedError, Sendable {
        case missingRecordID
        case unexpectedRecordType(String)
        case missingField(String)

        public var errorDescription: String? {
            switch self {
            case .missingRecordID:
                return "Record ID is required for update operations."
            case .unexpectedRecordType(let recordType):
                return "Expected \(TelemetrySchema.clientRecordType) but found \(recordType)."
            case .missingField(let field):
                return "Missing field '\(field)' on CloudKit record."
            }
        }
    }

    public let recordID: CKRecord.ID?
    public let userRecordId: String?
    public var clientId: String
    public var created: Date
    public var isEnabled: Bool
    public var isForceOn: Bool

    public init(
        recordID: CKRecord.ID? = nil,
        clientId: String,
        created: Date,
        isEnabled: Bool,
        isForceOn: Bool = false,
        userRecordId: String? = nil
    ) {
        self.recordID = recordID
        self.userRecordId = userRecordId
        self.clientId = clientId
        self.created = created
        self.isEnabled = isEnabled
        self.isForceOn = isForceOn
    }

    public init(record: CKRecord) throws {
        guard record.recordType == TelemetrySchema.clientRecordType else {
            throw Error.unexpectedRecordType(record.recordType)
        }

        guard let clientId = record[TelemetrySchema.ClientField.clientId.rawValue] as? String else {
            throw Error.missingField(TelemetrySchema.ClientField.clientId.rawValue)
        }

        guard let created = record[TelemetrySchema.ClientField.created.rawValue] as? Date else {
            throw Error.missingField(TelemetrySchema.ClientField.created.rawValue)
        }

        let isEnabled: Bool
        if let storedBool = record[TelemetrySchema.ClientField.isEnabled.rawValue] as? NSNumber {
            isEnabled = storedBool.boolValue
        } else if let stored = record[TelemetrySchema.ClientField.isEnabled.rawValue] as? Bool {
            isEnabled = stored
        } else {
            throw Error.missingField(TelemetrySchema.ClientField.isEnabled.rawValue)
        }

        let isForceOn: Bool
        if let storedForceOn = record[TelemetrySchema.ClientField.isForceOn.rawValue] as? NSNumber {
            isForceOn = storedForceOn.boolValue
        } else if let storedForceOn = record[TelemetrySchema.ClientField.isForceOn.rawValue] as? Bool {
            isForceOn = storedForceOn
        } else {
            isForceOn = false
        }

        self.recordID = record.recordID
        self.userRecordId = record[TelemetrySchema.ClientField.userRecordId.rawValue] as? String
        self.clientId = clientId
        self.created = created
        self.isEnabled = isEnabled
        self.isForceOn = isForceOn
    }

    public func toCKRecord() -> CKRecord {
        let record: CKRecord
        if let recordID {
            record = CKRecord(recordType: TelemetrySchema.clientRecordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: TelemetrySchema.clientRecordType)
        }

        record[TelemetrySchema.ClientField.clientId.rawValue] = clientId as CKRecordValue
        record[TelemetrySchema.ClientField.created.rawValue] = created as CKRecordValue
        record[TelemetrySchema.ClientField.isEnabled.rawValue] = isEnabled as CKRecordValue
        record[TelemetrySchema.ClientField.isForceOn.rawValue] = isForceOn as CKRecordValue

        if let userRecordId {
            record[TelemetrySchema.ClientField.userRecordId.rawValue] = userRecordId as CKRecordValue
        }

        return record
    }

    public func applying(to record: CKRecord) throws -> CKRecord {
        guard record.recordType == TelemetrySchema.clientRecordType else {
            throw Error.unexpectedRecordType(record.recordType)
        }

        record[TelemetrySchema.ClientField.clientId.rawValue] = clientId as CKRecordValue
        record[TelemetrySchema.ClientField.created.rawValue] = created as CKRecordValue
        record[TelemetrySchema.ClientField.isEnabled.rawValue] = isEnabled as CKRecordValue
        record[TelemetrySchema.ClientField.isForceOn.rawValue] = isForceOn as CKRecordValue

        if let userRecordId {
            record[TelemetrySchema.ClientField.userRecordId.rawValue] = userRecordId as CKRecordValue
        }

        return record
    }
}
