import CloudKit
import CoreData
import CryptoKit
import Foundation

nonisolated enum CareCloudAccount {
  static func identity(_ recordID: CKRecord.ID) -> String {
    SHA256.hash(data: Data(recordID.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// Keep Core Data's deployed record types, IDs, and relationship representation.
/// No care payload is translated or re-imported during the sync handoff.
nonisolated enum CareCloudScope: String, Codable, CaseIterable, Sendable {
  case personal, shared

  func database(in container: CKContainer) -> CKDatabase {
    self == .personal ? container.privateCloudDatabase : container.sharedCloudDatabase
  }
}

nonisolated struct CareCloudID: Codable, Hashable, Sendable {
  var scope: CareCloudScope
  var name: String
  var zone: String
  var owner: String

  init(_ id: CKRecord.ID, scope: CareCloudScope) {
    self.scope = scope
    name = id.recordName
    zone = id.zoneID.zoneName
    owner = id.zoneID.ownerName
  }

  init(zoneID: CKRecordZone.ID, scope: CareCloudScope) {
    self.scope = scope
    name = CKRecordNameZoneWideShare
    zone = zoneID.zoneName
    owner = zoneID.ownerName
  }

  var recordID: CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID) }
  var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zone, ownerName: owner) }
  var zoneKey: String {
    [scope.rawValue, owner, zone].map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
  }
  var key: String {
    [scope.rawValue, owner, zone, name].map { Data($0.utf8).base64EncodedString() }.joined(
      separator: ".")
  }
}

nonisolated enum CareCloudValue: Codable, Equatable, Sendable {
  case string(String)
  case bytes(Data)
  case date(Double)
  case integer(Int64)

  var cloudValue: CKRecordValue {
    switch self {
    case .string(let value): value as NSString
    case .bytes(let value): value as NSData
    case .date(let value): Date(timeIntervalSince1970: value) as NSDate
    case .integer(let value): NSNumber(value: value)
    }
  }
}

nonisolated struct CareCloudRecord: Codable, Equatable, Sendable {
  var id: CareCloudID
  var entity: String
  var fields: [String: CareCloudValue]
  var systemFields: Data?

  static let attributes: [String: [String]] = [
    "FamilyRoot": ["id", "name", "timeZone", "ownerID"],
    "Revision": ["id", "recordID", "parentIDs", "payload", "date", "editorID", "tombstone"],
    "PrivatePreference": ["key", "payload", "date"],
  ]

  init(id: CareCloudID, entity: String, fields: [String: CareCloudValue], systemFields: Data? = nil)
  {
    self.id = id
    self.entity = entity
    self.fields = fields
    self.systemFields = systemFields
  }

  @MainActor
  init(_ record: CKRecord, scope: CareCloudScope) throws {
    id = CareCloudID(record.recordID, scope: scope)
    guard let entity = record["CD_entityName"] as? String,
      let attributes = Self.attributes[entity], record.recordType == "CD_\(entity)"
    else {
      throw CareSyncError.unsupportedRecord
    }
    self.entity = entity
    fields = [:]
    for name in attributes + (entity == "Revision" ? ["family"] : []) {
      let key = "CD_\(name)"
      var value = record[key]
      // Core Data can externalize either binary or string fields into assets.
      if value == nil || (value as? Data)?.isEmpty == true || (value as? String)?.isEmpty == true,
        let asset = record[key + "_ckAsset"] as? CKAsset, let url = asset.fileURL
      {
        let bytes = try Data(contentsOf: url)
        if name == "payload" || name == "parentIDs" {
          value = bytes as NSData
        } else {
          guard let string = String(data: bytes, encoding: .utf8) else {
            throw CareSyncError.invalidRecord
          }
          value = string as NSString
        }
      }
      switch value {
      case let string as String: fields[name] = .string(string)
      case let data as Data: fields[name] = .bytes(data)
      case let date as Date: fields[name] = .date(Self.timestamp(date))
      case let number as NSNumber: fields[name] = .integer(number.int64Value)
      case nil: break
      default: throw CareSyncError.invalidRecord
      }
    }
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder)
    coder.finishEncoding()
    systemFields = coder.encodedData
    try validate()
  }

  @MainActor
  func record() throws -> CKRecord {
    try validate()
    let record: CKRecord
    if let systemFields {
      let coder = try NSKeyedUnarchiver(forReadingFrom: systemFields)
      coder.requiresSecureCoding = true
      guard let decoded = CKRecord(coder: coder), decoded.recordID == id.recordID,
        decoded.recordType == "CD_\(entity)"
      else { throw CareSyncError.invalidRecord }
      coder.finishDecoding()
      record = decoded
    } else {
      record = CKRecord(recordType: "CD_\(entity)", recordID: id.recordID)
    }
    record["CD_entityName"] = entity as NSString
    for name in Self.attributes[entity, default: []] + (entity == "Revision" ? ["family"] : []) {
      record["CD_\(name)"] = fields[name]?.cloudValue
      if name == "payload" || name == "parentIDs" || name == "name" || name == "key"
        || name == "timeZone"
      {
        record["CD_\(name)_ckAsset"] = nil
      }
    }
    return record
  }

  var logicalID: String? {
    guard case .string(let text) = fields["id"], let id = UUID(uuidString: text) else { return nil }
    return id.uuidString
  }

  var familyRecordName: String? {
    guard case .string(let value) = fields["family"] else { return nil }
    return value
  }

  // RecordEnvelope follows the app's main-actor domain-model isolation.
  @MainActor
  func validate() throws {
    guard !id.name.isEmpty, !id.zone.isEmpty, !id.owner.isEmpty else {
      throw CareSyncError.invalidRecord
    }
    guard Self.attributes[entity] != nil else { throw CareSyncError.unsupportedRecord }
    if entity == "PrivatePreference" {
      guard id.scope == .personal, case .string = fields["key"], case .bytes = fields["payload"],
        case .date = fields["date"]
      else { throw CareSyncError.invalidRecord }
    } else {
      guard logicalID != nil else { throw CareSyncError.invalidRecord }
      if entity == "FamilyRoot" {
        guard case .string(let owner) = fields["ownerID"], UUID(uuidString: owner) != nil,
          case .string = fields["name"], case .string(let zone) = fields["timeZone"],
          TimeZone(identifier: zone) != nil
        else { throw CareSyncError.invalidRecord }
      } else {
        guard let familyRecordName, !familyRecordName.isEmpty,
          case .bytes(let payload) = fields["payload"],
          case .bytes(let parents) = fields["parentIDs"],
          case .string(let editor) = fields["editorID"], UUID(uuidString: editor) != nil,
          case .string(let recordID) = fields["recordID"], UUID(uuidString: recordID) != nil,
          case .date = fields["date"], case .integer(let tombstone) = fields["tombstone"],
          tombstone == 0 || tombstone == 1
        else { throw CareSyncError.invalidRecord }
        let envelope = try JSONDecoder().decode(RecordEnvelope.self, from: payload)
        guard RecordEnvelope.supportedVersions.contains(envelope.version),
          envelope.value.id.uuidString == recordID.uppercased()
        else {
          throw CareSyncError.invalidRecord
        }
        _ = try JSONDecoder().decode(Set<UUID>.self, from: parents)
      }
    }
  }

  /// Only mutable family settings use field-wise merging. Revisions and
  /// private defaults are immutable; an ID collision must never overwrite one.
  static func merge(local: Self, server: Self, baseline: Self?) throws -> Self {
    guard local.id == server.id, local.entity == server.entity else {
      throw CareSyncError.invalidRecord
    }
    if local.entity != "FamilyRoot" {
      guard local.fields == server.fields else { throw CareSyncError.revisionCollision }
      return server
    }
    guard local.logicalID == server.logicalID, local.fields["ownerID"] == server.fields["ownerID"]
    else {
      throw CareSyncError.invalidRecord
    }
    var result = server
    for name in ["name", "timeZone"] where local.fields[name] != baseline?.fields[name] {
      if server.fields[name] == baseline?.fields[name] { result.fields[name] = local.fields[name] }
    }
    return result
  }

  static func timestamp(_ date: Date) -> Double {
    (date.timeIntervalSince1970 * 1_000).rounded() / 1_000
  }
}

@MainActor
extension CareCloudRecord {
  init(
    object: NSManagedObject, id: CareCloudID, familyRecordName: String?, systemFields: Data? = nil
  ) throws {
    guard let entity = object.entity.name, let attributes = Self.attributes[entity] else {
      throw CareSyncError.invalidRecord
    }
    var fields: [String: CareCloudValue] = [:]
    for name in attributes {
      switch object.value(forKey: name) {
      case let uuid as UUID: fields[name] = .string(uuid.uuidString)
      case let text as String: fields[name] = .string(text)
      case let data as Data: fields[name] = .bytes(data)
      case let date as Date: fields[name] = .date(Self.timestamp(date))
      case let number as NSNumber: fields[name] = .integer(number.int64Value)
      case nil: break
      default: throw CareSyncError.invalidRecord
      }
    }
    if let familyRecordName { fields["family"] = .string(familyRecordName) }
    self.init(id: id, entity: entity, fields: fields, systemFields: systemFields)
    try validate()
  }

  func apply(to object: NSManagedObject) throws {
    try validate()
    for name in Self.attributes[entity, default: []] {
      let value: Any?
      switch fields[name] {
      case .string(let text):
        if object.entity.attributesByName[name]?.attributeType == .UUIDAttributeType {
          value = UUID(uuidString: text)
        } else {
          value = text
        }
      case .bytes(let data): value = data
      case .date(let seconds): value = Date(timeIntervalSince1970: seconds)
      case .integer(let integer): value = NSNumber(value: integer)
      case nil: value = nil
      }
      object.setValue(value, forKey: name)
    }
  }
}

nonisolated enum CareSyncError: LocalizedError {
  case invalidRecord, unsupportedRecord, revisionCollision, waitingForLegacy, accountChanged,
    unavailable, revoked, corruptJournal
  case legacyMappingUnavailable, legacyRecordMismatch, legacyDeletionPending

  var errorDescription: String? {
    switch self {
    case .invalidRecord, .unsupportedRecord:
      String(localized: "An iCloud record couldn’t be read safely. Your local log has been kept.")
    case .revisionCollision:
      String(localized: "Two versions of a saved revision disagree. Your local records have been kept; syncing needs attention.")
    case .waitingForLegacy:
      String(localized: "Finishing the previous iCloud sync before upgrading. Keep Swaddle open and connected; your entries are saved.")
    case .legacyMappingUnavailable:
      String(localized: "iCloud hasn’t assigned an identity to some saved records yet. The sync upgrade is paused; your local entries are safe.")
    case .legacyRecordMismatch:
      String(localized: "A saved record differs from its iCloud copy. The sync upgrade is paused to preserve both versions.")
    case .legacyDeletionPending:
      String(localized: "A previous deletion hasn’t finished syncing. The sync upgrade is paused so deleted data won’t return.")
    case .accountChanged:
      String(localized: "Sign into the original Apple Account to sync this log. Your local records have been kept.")
    case .unavailable: String(localized: "iCloud isn’t available yet. Your entries are saved on this iPhone.")
    case .revoked:
      String(localized: "Access to this shared family has changed. Reopen the invitation or ask the family owner to check access.")
    case .corruptJournal:
      String(localized: "The local sync checkpoint couldn’t be read. Your care records have been kept; syncing needs attention.")
    }
  }
}
