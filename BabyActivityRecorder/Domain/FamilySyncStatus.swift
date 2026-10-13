import Foundation

struct FamilySyncStatus: Equatable, Sendable {
  enum Phase: Equatable, Sendable {
    case local, preparing, uploading, checking, attention, checked
  }

  let phase: Phase

  init(
    cloudEnabled: Bool, isSyncing: Bool, pendingUploads: Int, needsAttention: Bool,
    lastCheck: Date?
  ) {
    if !cloudEnabled {
      phase = .local
    } else if needsAttention {
      phase = .attention
    } else if isSyncing {
      phase = .checking
    } else if pendingUploads > 0 {
      phase = .uploading
    } else if lastCheck == nil {
      phase = .preparing
    } else {
      phase = .checked
    }
  }

  var title: String {
    switch phase {
    case .local: String(localized: "Saved on this iPhone")
    case .preparing: String(localized: "Preparing iCloud")
    case .uploading: String(localized: "Waiting to upload")
    case .checking: String(localized: "Checking iCloud")
    case .attention: String(localized: "iCloud needs attention")
    case .checked: String(localized: "iCloud checked")
    }
  }

  var isWorking: Bool { phase == .checking || phase == .uploading || phase == .preparing }
}
