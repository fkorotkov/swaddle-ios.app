import Foundation
import Testing

@testable import LittleLogCore

struct FamilySyncStatusTests {
  @Test func pendingUploadIsOrdinaryWorkRatherThanAnError() {
    let status = FamilySyncStatus(
      cloudEnabled: true, isSyncing: false, pendingUploads: 1,
      needsAttention: false, lastCheck: .now)
    #expect(status.phase == .uploading)
    #expect(status.title == "Waiting to upload")
  }

  @Test func firstDownloadNeverClaimsTheFamilyIsUpToDate() {
    let status = FamilySyncStatus(
      cloudEnabled: true, isSyncing: false, pendingUploads: 0,
      needsAttention: false, lastCheck: nil)
    #expect(status.phase == .preparing)
  }

  @Test func failureRemainsVisibleEvenWithPendingWork() {
    let status = FamilySyncStatus(
      cloudEnabled: true, isSyncing: true, pendingUploads: 2,
      needsAttention: true, lastCheck: .now)
    #expect(status.phase == .attention)
  }

  @Test func localStorageAndCloudChecksHaveDifferentClaims() {
    let local = FamilySyncStatus(
      cloudEnabled: false, isSyncing: false, pendingUploads: 0,
      needsAttention: false, lastCheck: nil)
    #expect(local.phase == .local)
    let checked = FamilySyncStatus(
      cloudEnabled: true, isSyncing: false, pendingUploads: 0,
      needsAttention: false, lastCheck: .now)
    #expect(checked.title == "iCloud checked")
    let checking = FamilySyncStatus(
      cloudEnabled: true, isSyncing: true, pendingUploads: 0,
      needsAttention: false, lastCheck: .now)
    #expect(checking.phase == .checking)
  }
}
