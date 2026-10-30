import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(SocialStore.self) private var social
    @Query(sort: \WishList.createdAt, order: .reverse) private var lists: [WishList]
    @Environment(CloudStore.self) private var cloud
    @State private var adding = false
    @State private var search = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("A LITTLE ROOM FOR WHAT YOU LOVE").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.green)
                Text("Keep a little\nwonder close.").font(.system(size: 38, design: .serif))
                Text("Big dreams, small joys, and everything in between.").foregroundStyle(.secondary)
                if cloud.localOnly { Label("On-device library", systemImage: "iphone").font(.caption).foregroundStyle(.secondary) }
                if let message = social.publicationMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                if lists.isEmpty {
                    ContentUnavailableView("Your first wish starts here", systemImage: "sparkles", description: Text("Create a wishlist to collect the things you’re hoping for."))
                    Button("Create a wishlist") { adding = true }.buttonStyle(.borderedProminent)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(lists.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { list in
                            NavigationLink { ListDetail(list: list) } label: {
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack { Image(systemName: list.publicRecordName == nil && !social.publishing.contains(list.id) ? "lock" : "globe"); Spacer(); Text(list.category.uppercased()).font(.caption2) }.foregroundStyle(Theme.green)
                                    Text(list.title).font(.system(.title2, design: .serif)).foregroundStyle(.primary)
                                    HStack { Text("\(list.wishes?.count ?? 0) wishes"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline).foregroundStyle(.secondary)
                                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Theme.sage.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Wishwell").searchable(text: $search, prompt: "Find a wishlist")
            .toolbar { Button("New list", systemImage: "plus") { adding = true }.accessibilityIdentifier("list.add") }
            .sheet(isPresented: $adding) { ListEditor() }
    }
}

struct ListEditor: View {
    var existing: WishList?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @State private var title = ""
    @State private var category = ""
    @State private var isPublic = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Wishlist name", text: $title).accessibilityIdentifier("list.title")
                TextField("Category (optional)", text: $category)
                // An existing list is switched from its own page.
                if existing == nil { Section { PublicSwitch(isOn: $isPublic) } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(existing == nil ? "New wishlist" : "Edit wishlist")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("list.save") }
                }.onAppear { title = existing?.title ?? ""; category = existing?.category ?? "" }
        }
    }
    private func save() {
        let list = existing ?? WishList(title: title)
        if existing == nil { context.insert(list) }
        list.title = title.trimmingCharacters(in: .whitespacesAndNewlines); list.category = category; list.updatedAt = Date()
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription; return }
        // The list is saved first; sharing finishes in the background and reports a failure on the list page.
        if existing == nil && isPublic {
            let social = social, context = context
            Task { do { try await social.setPublic(list, true, context: context) } catch { social.publicationMessage = "Your wishlist is saved but couldn’t be made public: \(error.localizedDescription)" } }
        }
    }
}

struct ListDetail: View {
    let list: WishList
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @State private var adding = false
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    @State private var showFulfilled = true
    @State private var switching: Bool?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(list.title).font(.system(.largeTitle, design: .serif))
                PublicSwitch(isOn: Binding(get: { switching ?? (social.publishing.contains(list.id) || list.publicRecordName != nil) }, set: { setPublic($0) }),
                             working: switching != nil || social.publishing.contains(list.id))
                    .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                if let message = social.publicationMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                Toggle("Show fulfilled wishes", isOn: $showFulfilled)
                if list.sortedWishes.isEmpty { ContentUnavailableView("Ready for a first wish", systemImage: "sparkles") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                    ForEach(list.sortedWishes.filter { showFulfilled || !$0.fulfilled }) { wish in
                        NavigationLink { WishDetail(wish: wish) } label: {
                            WishTile(wish: wish, claim: list.publicRecordName.flatMap { social.claimCache[$0]?[wish.id] })
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Wishlist").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Add a wish", systemImage: "plus") { adding = true }.accessibilityIdentifier("wish.add")
                Menu {
                    Button("Edit wishlist", systemImage: "pencil") { editing = true }
                    ShareLink(item: shareText) { Label("Share a text copy", systemImage: "square.and.arrow.up") }
                    Button("Delete wishlist", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("list.delete")
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("list.menu")
            }
            // Loads which wishes someone might be getting, once the public account is ready.
            .task(id: "\(list.publicRecordName ?? "")|\(social.me?.id ?? "")") {
                if let id = list.publicRecordName, social.me != nil { _ = try? await social.claims(listID: id) }
            }
            .sheet(isPresented: $adding) { WishEditor(list: list) }
            .sheet(isPresented: $editing) { ListEditor(existing: list) }
            .confirmationDialog(deleteTitle, isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete wishlist", role: .destructive) {
                    let known = list.publicRecordName, source = list.id, wishes = (list.wishes ?? []).map(\.id)
                    // Gone from this phone at once; its wishes go with it.
                    context.delete(list)
                    do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription; return }
                    dismiss()
                    // Then its public record goes too, including one kept while the list was private.
                    let social = social
                    Task {
                        do {
                            var record = known
                            if record == nil && social.enabled && social.me != nil { record = try await social.ownListRecord(source: source)?.id }
                            guard let record else { return }
                            // Anyone getting one of these wishes is noted first, so they can be told once it's gone.
                            if !social.isDemo { await PushService.reportRemoval(list: record, wishes: wishes) }
                            try await social.unpublish(record)
                        } catch { social.publicationMessage = "The list was deleted here, but its shared copy needs attention: \(error.localizedDescription)" }
                    }
                }.accessibilityIdentifier("list.confirmDelete")
            } message: { Text(list.publicRecordName == nil ? "This can’t be undone." : "This can’t be undone. It’s also removed from your circle, along with anything people marked as getting.") }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private var deleteTitle: String {
        let count = list.wishes?.count ?? 0
        return count == 0 ? "Delete “\(list.title)”?" : "Delete “\(list.title)” and its \(count) \(count == 1 ? "wish" : "wishes")?"
    }
    private func setPublic(_ on: Bool) {
        switching = on
        Task {
            do { try await social.setPublic(list, on, context: context); social.publicationMessage = nil }
            catch { self.error = error.localizedDescription }
            switching = nil
        }
    }
    private var shareText: String {
        ([list.title] + list.sortedWishes.map { wish in
            "\(wish.fulfilled ? "✓ " : "• ")\(wish.title)" + wish.options.map { "\n  \($0.location) \($0.formattedPrice ?? "")" }.joined()
        }).joined(separator: "\n\n")
    }
}

struct WishTile: View {
    let wish: Wish
    var claim: ClaimState?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(wish.fulfilled ? "Fulfilled" : "A little wish", systemImage: wish.fulfilled ? "checkmark.circle.fill" : "sparkles").font(.caption).foregroundStyle(Theme.green)
            Text(wish.title).font(.system(.title2, design: .serif)).foregroundStyle(.primary)
            OptionRows(options: wish.options, interactive: false)
            ClaimBadge(state: claim)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(wish.fulfilled ? Theme.sage : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Text first, then a small icon, like "amazon.com ↗".
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.imageScale(.small) }
    }
}

struct OptionRows: View {
    let options: [ShoppingOption]
    var interactive = true
    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { option in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Group {
                        if interactive, let link = option.link {
                            Link(destination: link) { Label(option.label, systemImage: "arrow.up.right.square").labelStyle(TrailingIcon()) }.lineLimit(1)
                        } else { Text(option.location.isEmpty ? "Price" : option.label).lineLimit(2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let price = option.formattedPrice { Text(price).fontWeight(.medium).fixedSize() }
                }.font(.subheadline)
            }
        }
    }
}

struct WishDetail: View {
    let wish: Wish
    @Environment(SocialStore.self) private var social
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("A LITTLE SOMETHING TO HOPE FOR").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.green)
                Text(wish.title).font(.system(size: 36, design: .serif))
                Button {
                    wish.fulfilled.toggle(); wish.updatedAt = Date()
                    do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription; return }
                    // Someone getting it hears that it's already been got, once the shared copy shows it.
                    if wish.fulfilled, !social.isDemo, let record = wish.list?.publicRecordName {
                        let id = wish.id
                        Task { await PushService.reportRemoval(list: record, wishes: [id]) }
                    }
                } label: { Label(wish.fulfilled ? "Fulfilled" : "Mark fulfilled", systemImage: wish.fulfilled ? "checkmark.circle.fill" : "checkmark.circle") }
                    .buttonStyle(.bordered).accessibilityIdentifier("wish.fulfilled")
                OptionRows(options: wish.options)
                if let id = wish.list?.publicRecordName { ClaimBadge(state: social.claimCache[id]?[wish.id]) }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(wish.fulfilled ? Theme.sage.opacity(0.3) : Theme.background).navigationTitle("Wish").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu {
                    Button("Edit wish", systemImage: "pencil") { editing = true }
                    Button("Delete wish", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .sheet(isPresented: $editing) { if let list = wish.list { WishEditor(list: list, existing: wish) } }
            .confirmationDialog("Delete this wish?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete wish", role: .destructive) {
                    if !social.isDemo, let record = wish.list?.publicRecordName {
                        let id = wish.id
                        Task { await PushService.reportRemoval(list: record, wishes: [id]) }
                    }
                    context.delete(wish)
                    do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

struct WishEditor: View {
    let list: WishList
    var existing: Wish?
    @Environment(SocialStore.self) private var social
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WishList.createdAt) private var lists: [WishList]
    @State private var title = ""
    @State private var options = [ShoppingOption()]
    @State private var destination: UUID?
    @State private var error: String?
    @FocusState private var focused: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you wishing for?", text: $title).focused($focused, equals: "title").accessibilityIdentifier("wish.title")
                    if existing != nil {
                        Picker("Wishlist", selection: $destination) {
                            ForEach(lists) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    ForEach($options) { $option in
                        HStack(spacing: 12) {
                            TextField("Link or store", text: $option.location).focused($focused, equals: "location-\(option.id)").textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("option.location.\(options.firstIndex(where: { $0.id == option.id }) ?? 0)")
                            Divider()
                            TextField("Price", text: $option.price).focused($focused, equals: "price-\(option.id)").keyboardType(.decimalPad).frame(width: 80).accessibilityIdentifier("option.price.\(options.firstIndex(where: { $0.id == option.id }) ?? 0)")
                            if options.count > 1 { Button("Remove option", systemImage: "minus.circle.fill") { options.removeAll { $0.id == option.id } }.labelStyle(.iconOnly).foregroundStyle(.red).buttonStyle(.borderless) }
                        }
                    }
                    if options.count < 3 { Button("Add an option", systemImage: "plus") { options.append(ShoppingOption()) }.accessibilityIdentifier("option.add") }
                } header: { Text("Shopping options") } footer: { Text("Compare up to three places to buy your wish. Prices are in USD.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(existing == nil ? "New wish" : "Edit wish")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("wish.save") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil }.accessibilityIdentifier("keyboard.done") }
                }
                .onAppear { title = existing?.title ?? ""; options = existing?.options.isEmpty == false ? existing!.options : [ShoppingOption()]; destination = list.id }
        }
    }
    private func save() {
        do {
            let validated = try ShoppingOption.validated(options)
            let target = lists.first(where: { $0.id == destination }) ?? list
            if let existing {
                existing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.optionsData = try JSONEncoder().encode(validated); existing.updatedAt = Date()
                // Moving a wish off a shared list counts as removing it there.
                if target.id != list.id, !social.isDemo, let record = list.publicRecordName {
                    let id = existing.id
                    Task { await PushService.reportRemoval(list: record, wishes: [id]) }
                }
                existing.list = target
            } else {
                context.insert(try Wish(title: title.trimmingCharacters(in: .whitespacesAndNewlines), options: validated, list: target))
            }
            target.updatedAt = Date(); try context.save(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
