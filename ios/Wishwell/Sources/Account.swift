import SwiftUI
import PhotosUI
import UIKit

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @State private var first = ""
    @State private var last = ""
    @State private var photo: PhotosPickerItem?
    @State private var deleting = false
    @State private var password = ""
    @State private var signingOut = false
    @State private var credentials = false
    var body: some View {
        Form {
            if let user = store.user {
                Section {
                    HStack(spacing: 18) {
                        AvatarView(person: user, size: 72)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(user.name).font(.system(.title2, design: .serif))
                            Text(user.email ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Change profile photo", systemImage: "photo") }.disabled(store.busy)
                }
                Section("Your profile") {
                    TextField("First name", text: $first).textContentType(.givenName)
                    TextField("Last name", text: $last).textContentType(.familyName)
                    Button("Save profile") { Task { await store.perform { let data = try await store.request("me", method: "PATCH", body: ["first_name": first, "last_name": last]); store.user = try store.decoder.decode(Person.self, from: data) } } }.disabled(store.busy || (first == user.firstName && last == user.lastName))
                }
                Section("Account security") {
                    Button("Change email or password") { credentials = true }
                }
                Section("Your circle") {
                    LabeledContent("Followers", value: "\(user.followersCount)")
                    LabeledContent("Following", value: "\(user.followingCount)")
                }
                Section {
                    Button("Sign out", role: .destructive) { signingOut = true }.disabled(store.busy)
                    Button("Delete account", role: .destructive) { deleting = true }.disabled(store.busy)
                } footer: { Text("Your account and wishlists are shared with the Wishwell website.") }
            }
        }.navigationTitle("Your profile")
        .task {
            do { let user: Person = try await store.fetch("me"); store.user = user; first = user.firstName; last = user.lastName }
            catch { store.error = error.localizedDescription }
        }
        .sheet(isPresented: $credentials) { CredentialsEditor() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                await store.perform {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw APIError(message: "That image could not be opened.") }
                    let limit: CGFloat = 1200
                    let ratio = min(1, limit / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                    let renderer = UIGraphicsImageRenderer(size: size)
                    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                    guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw APIError(message: "That image could not be prepared.") }
                    try await store.uploadAvatar(jpeg)
                }
                photo = nil
            }
        }
        .confirmationDialog("Sign out of Wishwell?", isPresented: $signingOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await store.perform { try await store.signOut() } } }
        }
        .alert("Delete your account?", isPresented: $deleting) {
            SecureField("Current password", text: $password)
            Button("Delete account", role: .destructive) {
                Task { await store.perform { _ = try await store.request("me", method: "DELETE", body: ["password": password]); password = ""; store.clearSession() } }
            }
            Button("Cancel", role: .cancel) { password = "" }
        } message: { Text("This permanently deletes your account, wishes, lists, and social activity. Enter your password to confirm.") }
    }
}

struct CredentialsEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var current = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Email") { TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Section("Confirm it’s you") { SecureField("Current password", text: $current).textContentType(.password) }
                Section { SecureField("New password", text: $password).textContentType(.newPassword); SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword) } header: { Text("New password") } footer: { Text("Leave blank to keep your password. Saving signs out your other app sessions.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Account security").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task {
                    saving = true; defer { saving = false }
                    do { try await store.updateCredentials(email: email, currentPassword: current, password: password, confirmation: confirmation); current = ""; password = ""; confirmation = ""; dismiss() }
                    catch { self.error = error.localizedDescription }
                } }.disabled(saving || current.isEmpty || email.isEmpty) }
            }.onAppear { email = store.user?.email ?? "" }.interactiveDismissDisabled(saving)
        }
    }
}
