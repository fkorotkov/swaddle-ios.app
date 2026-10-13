#if DEBUG
    import SwiftUI

    #Preview("Delete caregiver · History kept") {
        let store = caregiverDeletionPreviewStore()
        CaregiverEditor(store: store, existing: store.snapshot.caregivers.first { $0.name == "Alex" })
    }

    #Preview("Delete caregiver · Large dark") {
        let store = caregiverDeletionPreviewStore()
        CaregiverEditor(store: store, existing: store.snapshot.caregivers.first { $0.name == "Alex" })
            .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility3)
    }

    #Preview("Delete caregiver · Linked account") {
        let store = caregiverDeletionPreviewStore(linked: true)
        CaregiverEditor(store: store, existing: store.snapshot.caregivers.first { $0.name == "Alex" })
    }

    #Preview("Family · Deleted profile history") {
        SettingsView(store: caregiverDeletionPreviewStore(deleted: true))
    }

    @MainActor
    private func caregiverDeletionPreviewStore(linked: Bool = false, deleted: Bool = false)
        -> LogStore
    {
        let store = PreviewData.pumpingHelperStore(profiles: 2)
        do {
            if var person = store.snapshot.caregivers.first(where: { $0.name == "Alex" }) {
                if linked {
                    person.cloudIdentity = "preview-account"
                    try store.save(.caregiver(person))
                }
                if deleted { try store.deleteCaregiver(person.id) }
            }
        } catch { assertionFailure("Caregiver deletion preview failed: \(error)") }
        return store
    }
#endif
