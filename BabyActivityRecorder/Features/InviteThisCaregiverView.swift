import SwiftUI

struct InviteThisCaregiverView: View {
    let store: LogStore
    let caregiverID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var delivery: CaregiverInvitationDelivery?
    @State private var error: String?
    @State private var preparation: Task<Void, Never>?
    @State private var manageAccess = false
    @State private var copiedDiagnostics = false
    @FocusState private var emailFocused: Bool

    private var person: Caregiver? { store.snapshot.caregivers.first { $0.id == caregiverID } }
    private var preparing: Bool { preparation != nil }

    var body: some View {
        NavigationStack {
            Form {
                if let person {
                    Section {
                        Label(person.name, systemImage: person.isMother ? "drop.halffull" : "person.crop.circle")
                            .font(.headline)
                        Text(person.isMother
                             ? String(localized: "They’ll join as \(person.name). Existing pumping history stays with this profile.")
                             : String(localized: "They’ll join as \(person.name) and record entries using this profile."))
                            .foregroundStyle(.secondary)
                    }
                    if let delivery {
                        InvitationReadyContent(delivery: delivery)
                    } else {
                        Section {
                            TextField("Apple Account email", text: $email)
                                .textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($emailFocused).submitLabel(.go)
                                .disabled(preparing)
                                .onSubmit { if validEmail { prepare() } }
                                .accessibilityIdentifier("caregiver.invite.email")
                        } header: { Text("Who should use this profile?") } footer: {
                            Text(person.invitation == nil
                                 ? String(localized: "Use the email they use with their Apple Account. You’ll choose how to send the invitation next.")
                                 : String(localized: "Use the same Apple Account email to send this invitation again. To invite someone else, remove the previous invitation in Family sharing first."))
                        }
                        Section {
                            Label("Can edit the family log", systemImage: "person.2")
                            Text("Includes every child, existing history, and shared pumping. They can add, edit, or delete entries.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let error {
                            Section {
                                ErrorNotice(message: error)
                                Button(copiedDiagnostics ? String(localized: "Details copied") : String(localized: "Copy troubleshooting details"), systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = store.caregiverInvitationDiagnostic
                                    copiedDiagnostics = true
                                }
                                .accessibilityIdentifier("caregiver.invite.diagnostics")
                            }
                        }
                        Section {
                            Button(action: prepare) {
                                HStack(spacing: 10) {
                                    if preparing { ProgressView() }
                                    Text(preparing ? store.caregiverInvitationStage.title : String(localized: "Create invitation"))
                                }.frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(preparing || !validEmail || !store.isOwner)
                            .accessibilityIdentifier("caregiver.invite.create")
                        } footer: {
                            Text(preparing
                                 ? String(localized: "Keep Swaddle open while iCloud finishes. Your caregiver’s history stays with this profile.")
                                 : String(localized: "Only the invited Apple Account can join. Both iPhones need the version of Swaddle that supports profile invitations."))
                        }
                    }
                    Section {
                        Button("Manage family access", systemImage: "person.2.badge.gearshape") { manageAccess = true }
                            .disabled(preparing)
                    }
                } else {
                    ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Invite caregiver").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $manageAccess) { InviteCaregiverView(store: store) }
            .onDisappear { preparation?.cancel() }
        }.tint(LogStyle.forest)
    }

    private var validEmail: Bool { (try? CaregiverInvitationRules.email(email)) != nil }

    private func prepare() {
        guard !preparing, validEmail else { return }
        emailFocused = false
        error = nil
        copiedDiagnostics = false
        preparation = Task {
            defer { preparation = nil }
            do {
                let ready = try await store.prepareCaregiverInvitation(caregiverID: caregiverID, email: email)
                try Task.checkCancellation()
                delivery = ready
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct InvitationReadyContent: View {
    let delivery: CaregiverInvitationDelivery
    var body: some View {
        Section {
            Label(delivery.alreadyAccepted ? String(localized: "iCloud invitation accepted") : String(localized: "Ready to send"), systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(LogStyle.forest)
            Text(delivery.recipientEmail).textSelection(.enabled)
            if delivery.alreadyAccepted {
                Text("Open Swaddle on their iPhone. If the join screen appears, tap Check again.")
            }
            ShareLink(item: delivery.url, subject: Text("Join our family in Swaddle"),
                      message: Text("Join our shared family log as \(delivery.caregiverName). Open this invitation on your iPhone with Swaddle installed.")) {
                Label(delivery.alreadyAccepted ? String(localized: "Share invitation link again") : String(localized: "Send invitation"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("caregiver.invite.send")
        } footer: {
            Text(delivery.alreadyAccepted
                 ? String(localized: "Their caregiver profile and history finish syncing separately. This existing link keeps the same access.")
                 : String(localized: "Send this link to \(delivery.recipientEmail). Access starts when they accept using their Apple Account. Creating the link doesn’t send a message."))
        }
    }
}

#if DEBUG
#Preview("Invite a pumping caregiver") {
    @Previewable @State var store = PreviewData.invitationStore()
    InviteThisCaregiverView(store: store, caregiverID: store.snapshot.caregivers.first { $0.id != store.caregiverID }!.id)
}

#Preview("Invitation ready") {
    NavigationStack {
        Form {
            InvitationReadyContent(delivery: .init(url: URL(string: "https://example.com/invitation")!, caregiverName: "Alex", recipientEmail: "alex@example.com"))
        }.navigationTitle("Invite caregiver").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Invitation already accepted") {
    NavigationStack {
        Form {
            InvitationReadyContent(delivery: .init(url: URL(string: "https://example.com/invitation")!, caregiverName: "Alex",
                                                  recipientEmail: "alex@example.com", alreadyAccepted: true))
        }.navigationTitle("Invite caregiver").navigationBarTitleDisplayMode(.inline)
    }
}
#endif
