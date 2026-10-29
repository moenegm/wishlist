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
                                    HStack { Image(systemName: list.publicRecordName == nil ? "lock" : "globe"); Spacer(); Text(list.category.uppercased()).font(.caption2) }.foregroundStyle(Theme.green)
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
    @State private var title = ""
    @State private var category = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Wishlist name", text: $title).accessibilityIdentifier("list.title")
                TextField("Category (optional)", text: $category)
                Section { Label(existing?.publicRecordName == nil ? "Private to you" : "Published to your circle", systemImage: existing?.publicRecordName == nil ? "lock" : "globe") } footer: { Text("New lists are always private. Manage publishing from the wishlist’s sharing menu.") }
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
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(list.publicRecordName == nil ? "Private wishlist" : "Published wishlist", systemImage: list.publicRecordName == nil ? "lock" : "globe").font(.caption).foregroundStyle(Theme.green)
                Text(list.title).font(.system(.largeTitle, design: .serif))
                Toggle("Show fulfilled wishes", isOn: $showFulfilled)
                if list.sortedWishes.isEmpty { ContentUnavailableView("Ready for a first wish", systemImage: "sparkles") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                    ForEach(list.sortedWishes.filter { showFulfilled || !$0.fulfilled }) { wish in
                        NavigationLink { WishDetail(wish: wish) } label: { WishTile(wish: wish) }.buttonStyle(.plain)
                    }
                }
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Wishlist").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Add a wish", systemImage: "plus") { adding = true }.accessibilityIdentifier("wish.add")
                Menu {
                    NavigationLink { ListSharingView(list: list) } label: { Label("Wishlist sharing", systemImage: "person.2") }
                    Button("Edit wishlist", systemImage: "pencil") { editing = true }
                    ShareLink(item: shareText) { Label("Share a text copy", systemImage: "square.and.arrow.up") }
                    Button("Delete wishlist", systemImage: "trash", role: .destructive) { deleting = true }.disabled(!(list.wishes ?? []).isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("list.menu")
            }
            .sheet(isPresented: $adding) { WishEditor(list: list) }
            .sheet(isPresented: $editing) { ListEditor(existing: list) }
            .confirmationDialog("Delete this empty wishlist?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete wishlist", role: .destructive) {
                    guard (list.wishes ?? []).isEmpty else { error = "Move or delete the wishes in this list first."; return }
                    Task {
                        do {
                            if let id = list.publicRecordName { try await social.unpublish(id) }
                            guard (list.wishes ?? []).isEmpty else { throw WishwellError("Move or delete the wishes in this list first.") }
                            context.delete(list); try context.save(); dismiss()
                        } catch { context.rollback(); self.error = error.localizedDescription }
                    }
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private var shareText: String {
        ([list.title] + list.sortedWishes.map { wish in
            "\(wish.fulfilled ? "✓ " : "• ")\(wish.title)" + wish.options.map { "\n  \($0.location) \($0.formattedPrice ?? "")" }.joined()
        }).joined(separator: "\n\n")
    }
}

struct WishTile: View {
    let wish: Wish
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(wish.fulfilled ? "Fulfilled" : "A little wish", systemImage: wish.fulfilled ? "checkmark.circle.fill" : "sparkles").font(.caption).foregroundStyle(Theme.green)
            Text(wish.title).font(.system(.title2, design: .serif)).foregroundStyle(.primary)
            OptionRows(options: wish.options, interactive: false)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(wish.fulfilled ? Theme.sage : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
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
                        if interactive, let link = option.link { Link(option.location, destination: link).lineLimit(2) }
                        else { Text(option.location.isEmpty ? "Price" : option.location).lineLimit(2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let price = option.formattedPrice { Text(price).fontWeight(.medium).fixedSize() }
                }.font(.subheadline)
            }
        }
    }
}

struct WishDetail: View {
    let wish: Wish
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
                    do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
                } label: { Label(wish.fulfilled ? "Fulfilled" : "Mark fulfilled", systemImage: wish.fulfilled ? "checkmark.circle.fill" : "checkmark.circle") }
                    .buttonStyle(.bordered).accessibilityIdentifier("wish.fulfilled")
                OptionRows(options: wish.options)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("What are you wishing for?", text: $title).textFieldStyle(.roundedBorder).focused($focused, equals: "title").accessibilityIdentifier("wish.title")
                    if existing != nil {
                        Picker("Wishlist", selection: $destination) {
                            ForEach(lists) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    Text("Shopping options").font(.headline)
                    Text("Compare up to three places to buy your wish.").font(.subheadline).foregroundStyle(.secondary)
                    ForEach($options) { $option in
                        HStack(alignment: .top, spacing: 8) {
                            TextField("Link or store", text: $option.location).focused($focused, equals: "location-\(option.id)").textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("option.location.\(options.firstIndex(where: { $0.id == option.id }) ?? 0)")
                            TextField("Price", text: $option.price).focused($focused, equals: "price-\(option.id)").keyboardType(.decimalPad).frame(width: 88).accessibilityIdentifier("option.price.\(options.firstIndex(where: { $0.id == option.id }) ?? 0)")
                            if options.count > 1 { Button("Remove option", systemImage: "minus.circle") { options.removeAll { $0.id == option.id } }.labelStyle(.iconOnly) }
                        }.textFieldStyle(.roundedBorder)
                    }
                    if options.count < 3 { Button("Add an option", systemImage: "plus") { options.append(ShoppingOption()) }.accessibilityIdentifier("option.add") }
                    Text("Prices are in USD.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(Theme.background).navigationTitle(existing == nil ? "New wish" : "Edit wish").navigationBarTitleDisplayMode(.inline)
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
                existing.optionsData = try JSONEncoder().encode(validated); existing.updatedAt = Date(); existing.list = target
            } else {
                context.insert(try Wish(title: title.trimmingCharacters(in: .whitespacesAndNewlines), options: validated, list: target))
            }
            target.updatedAt = Date(); try context.save(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
