import SwiftUI

struct WishlistDetailView: View {
    let id: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var loadError: String?
    @State private var list: WishlistRecord?
    @State private var editing = false
    @State private var adding = false
    @State private var deleting = false
    var body: some View {
        Group {
            if let list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Label(list.isPublic ? "Public wishlist" : "Private wishlist", systemImage: list.isPublic ? "globe" : "lock").font(.caption).foregroundStyle(Theme.green)
                            Spacer()
                            if list.userId == store.user?.id {
                                Button("Add a wish", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent)
                            }
                        }
                        Text(list.title).font(.system(.largeTitle, design: .serif))
                        if list.userId != store.user?.id {
                            NavigationLink(value: Destination.person(list.owner.id)) { HStack { AvatarView(person: list.owner, size: 32); Text(list.owner.name) } }
                        }
                        SocialBar(type: "Wlist", id: list.id, liked: list.liked, likes: list.likesCount, comments: list.commentsCount, refresh: load)
                        if let wishes = list.wishes, !wishes.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                                ForEach(wishes) { wish in
                                    NavigationLink(value: Destination.wish(wish)) { WishCard(wish: wish) }.buttonStyle(.plain)
                                }
                            }
                        } else { ContentUnavailableView("Ready for a first wish", systemImage: "sparkles", description: Text("The things you’re hoping for will live here.")) }
                    }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
                }.background(Theme.background)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn’t load this wishlist", systemImage: "wifi.exclamationmark")
                } description: { Text(loadError) } actions: { Button("Try again") { Task { await load() } } }
            } else { ProgressView("Loading wishlist…") }
        }
        .navigationTitle("Wishlist").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let list {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: URL(string: "https://wishwell-22rh.onrender.com/wlists/\(id)")!)
                        if list.userId == store.user?.id {
                            Button("Edit wishlist", systemImage: "pencil") { editing = true }
                            Button("Delete wishlist", systemImage: "trash", role: .destructive) { deleting = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $editing) { if let list { WishlistEditor(existing: list) { _ in Task { await load() } } } }
        .sheet(isPresented: $adding) { WishEditor(listId: id) { _ in Task { await load() } } }
        .confirmationDialog("Delete this wishlist?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete wishlist", role: .destructive) { Task { await store.perform { _ = try await store.request("wlists/\(id)", method: "DELETE"); try await store.reload(); dismiss() } } }
        } message: { Text("A wishlist must be empty before it can be deleted.") }
        .task { await load() }.refreshable { await load() }
        .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load() async {
        do { list = try await store.fetch("wlists/\(id)"); loadError = nil }
        catch { list = nil; loadError = error.localizedDescription }
    }
}

struct WishCard: View {
    let wish: WishRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if wish.fulfilled { Label("Fulfilled", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(Theme.green) }
                else { Image(systemName: "sparkles").foregroundStyle(Theme.green) }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }
            Text(wish.title).font(.system(.title2, design: .serif))
            OptionRows(options: wish.purchaseOptions, interactive: false)
            HStack(spacing: 18) {
                Label("\(wish.likesCount)", systemImage: wish.liked ? "heart.fill" : "heart")
                Label("\(wish.commentsCount)", systemImage: "bubble.left")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(wish.fulfilled ? Theme.sage : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct OptionRows: View {
    let options: [PurchaseOption]
    var interactive = true
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if options.count > 1 { Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Group {
                        if interactive, let url = option.link { Link(option.location ?? "View option", destination: url).lineLimit(2) }
                        else { Text(option.location ?? "Price").lineLimit(2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let price = option.formattedPrice { Text(price).fontWeight(.medium).fixedSize() }
                }.font(.subheadline)
                if index < options.count - 1 { Divider() }
            }
        }
    }
}

struct WishDetailView: View {
    let initial: WishRecord
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var wish: WishRecord?
    @State private var editing = false
    @State private var deleting = false
    var body: some View {
        let item = wish ?? initial
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("A LITTLE SOMETHING TO HOPE FOR").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.green)
                Text(item.title).font(.system(size: 36, design: .serif))
                if item.userId == store.user?.id {
                    Button {
                        Task { await store.perform { _ = try await store.request("wishes/\(item.id)", method: "PATCH", body: ["wish": ["fulfilled": !item.fulfilled]]); await load() } }
                    } label: { Label(item.fulfilled ? "Fulfilled" : "Mark fulfilled", systemImage: item.fulfilled ? "checkmark.circle.fill" : "checkmark.circle") }
                    .buttonStyle(.bordered).disabled(store.busy)
                    .accessibilityHint(item.fulfilled ? "Mark this wish unfulfilled" : "Keep this wish visible as fulfilled")
                } else if item.fulfilled { Label("Fulfilled", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                OptionRows(options: item.purchaseOptions)
                Divider()
                SocialBar(type: "Wish", id: item.id, liked: item.liked, likes: item.likesCount, comments: item.commentsCount, refresh: load)
            }.padding(28).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }.background(item.fulfilled ? Theme.sage.opacity(0.5) : Theme.background)
        .navigationTitle("Wish").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item.userId == store.user?.id {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit wish", systemImage: "pencil") { editing = true }
                        Button("Remove wish", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $editing) { WishEditor(existing: item, listId: item.wlistId) { updated in wish = updated } }
        .confirmationDialog("Remove this wish?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Remove wish", role: .destructive) { Task { await store.perform { _ = try await store.request("wishes/\(item.id)", method: "DELETE"); try await store.reload(); dismiss() } } }
        }
        .task { await load() }.refreshable { await load() }
        .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load() async {
        do { wish = try await store.fetch("wishes/\(initial.id)") }
        catch { wish = nil; store.error = error.localizedDescription; dismiss() }
    }
}

struct WishlistEditor: View {
    var existing: WishlistRecord? = nil
    var saved: (WishlistRecord) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = ""
    @State private var isPublic = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Your wishlist") {
                    TextField("Name", text: $title)
                    TextField("Category (optional)", text: $category)
                }
                Section { Toggle("Public wishlist", isOn: $isPublic) } footer: {
                    Text(isPublic ? "Anyone with the link can view this list. Members can like and comment." : "Only you can see this list. Following you does not grant access.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? "New wishlist" : "Edit wishlist").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { if let existing { title = existing.title; category = existing.category; isPublic = existing.isPublic } }
            .interactiveDismissDisabled(saving)
        }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            let data = try await store.request(existing.map { "wlists/\($0.id)" } ?? "wlists", method: existing == nil ? "POST" : "PATCH", body: ["wlist": ["title": title, "wl_category": category, "is_public": isPublic]])
            let result = try store.decoder.decode(WishlistRecord.self, from: data)
            saved(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct OptionDraft: Identifiable {
    let id = UUID()
    var location = ""
    var price = ""
}

struct WishEditor: View {
    var existing: WishRecord? = nil
    let listId: Int
    var saved: (WishRecord) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var options = [OptionDraft()]
    @State private var selectedList = 0
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focusedField: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What are you wishing for?").font(.headline)
                        TextField("A name you’ll remember", text: $title).accessibilityIdentifier("wish.title").focused($focusedField, equals: "title")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Where can you find it?").font(.headline)
                        ForEach($options) { $option in
                            let index = options.firstIndex(where: { $0.id == option.id }) ?? 0
                            HStack(alignment: .center, spacing: 10) {
                                TextField("Store or link", text: $option.location).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityLabel("Store or link, option \(index + 1)").focused($focusedField, equals: "location\(option.id)")
                                TextField("Price", text: $option.price).keyboardType(.decimalPad).submitLabel(.done).onSubmit { focusedField = nil }.frame(width: 88)
                                    .accessibilityLabel("Price, option \(index + 1)").focused($focusedField, equals: "price\(option.id)")
                                if index > 0 {
                                    Button { options.removeAll { $0.id == option.id } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 44)
                                    }.buttonStyle(.plain).accessibilityLabel("Remove option \(index + 1)")
                                }
                            }
                        }
                        if options.count < 3 {
                            Button {
                                focusedField = nil
                                options.append(OptionDraft())
                            } label: {
                                Label("Add an option", systemImage: "plus").padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        Text("Compare up to three options. Store/link and price are optional.").font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wishlist").font(.headline)
                        Picker("Add it to", selection: $selectedList) {
                            ForEach(store.lists) { list in Text(list.title).tag(list.id) }
                        }.pickerStyle(.menu)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.textFieldStyle(.roundedBorder).padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).background(Theme.background)
            .navigationTitle(existing == nil ? "New wish" : "Edit wish").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.accessibilityIdentifier("wish.save").disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedList == 0) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil }.accessibilityIdentifier("wish.keyboardDone") }
            }
            .onAppear {
                selectedList = listId
                if let existing {
                    title = existing.title
                    options = existing.purchaseOptions.isEmpty ? [OptionDraft()] : existing.purchaseOptions.map { OptionDraft(location: $0.location ?? "", price: $0.price ?? "") }
                }
            }.interactiveDismissDisabled(saving)
        }
    }
    private func save() async {
        var attributes: [String: Any] = ["title": title, "wlists_id": selectedList]
        for index in 0..<3 {
            let option = index < options.count ? options[index] : OptionDraft()
            let suffix = index == 0 ? "" : "_\(index + 1)"
            let price = option.price.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            if !price.isEmpty && (Decimal(string: price) == nil || Decimal(string: price)! < 0) { error = "Enter a valid, nonnegative price for option \(index + 1)."; return }
            attributes["location\(suffix)"] = option.location
            attributes["price\(suffix)"] = price.isEmpty ? NSNull() : price as Any
        }
        saving = true; defer { saving = false }
        do {
            let data = try await store.request(existing.map { "wishes/\($0.id)" } ?? "wishes", method: existing == nil ? "POST" : "PATCH", body: ["wish": attributes])
            let result = try store.decoder.decode(WishRecord.self, from: data)
            saved(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
