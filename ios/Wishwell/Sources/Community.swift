import SwiftUI

struct SocialBar: View {
    let type: String
    let id: Int
    let liked: Bool
    let likes: Int
    let comments: Int
    let refresh: () async -> Void
    @Environment(AppStore.self) private var store
    @State private var showingComments = false
    var body: some View {
        HStack(spacing: 24) {
            Button {
                Task { await store.perform { _ = try await store.request("like", method: liked ? "DELETE" : "POST", body: ["target_type": type, "target_id": id]); await refresh() } }
            } label: { Label("\(likes)", systemImage: liked ? "heart.fill" : "heart") }
            .accessibilityLabel("\(liked ? "Unlike" : "Like"), \(likes) likes").disabled(store.busy)
            Button { showingComments = true } label: { Label("\(comments)", systemImage: "bubble.left") }.accessibilityLabel("\(comments) comments")
            Spacer()
        }
        .sheet(isPresented: $showingComments, onDismiss: { Task { await refresh() } }) { CommentsView(type: type, id: id) }
    }
}

struct CommentsView: View {
    let type: String
    let id: Int
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CommentRecord] = []
    @State private var bodyText = ""
    @State private var loading = true
    @State private var sending = false
    @State private var page = 1
    @State private var more = false
    @State private var error: String?
    @State private var deleteId: Int?
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.red); Button("Try again") { Task { await load() } } }
                if !loading && comments.isEmpty { ContentUnavailableView("Start a conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Leave a little encouragement.")) }
                ForEach(comments) { comment in
                    HStack(alignment: .top) {
                        AvatarView(person: comment.user, size: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(comment.user.name).font(.subheadline.weight(.semibold))
                            Text(comment.body).font(.body)
                        }
                        Spacer()
                        if comment.user.id == store.user?.id { Button("Delete", systemImage: "trash", role: .destructive) { deleteId = comment.id }.labelStyle(.iconOnly).buttonStyle(.borderless) }
                    }.padding(.vertical, 5)
                }
                if more { Button("Load more comments") { Task { await load(next: true) } } }
            }.navigationTitle("Comments").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .bottom) {
                        TextField("Write a comment…", text: $bodyText, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                        Button { Task { await post() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(sending || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.count > 500).accessibilityLabel("Post comment")
                    }
                    Text("\(bodyText.count)/500").font(.caption2).foregroundStyle(bodyText.count > 500 ? .red : .secondary)
                }.padding().background(.bar)
            }
            .confirmationDialog("Delete your comment?", isPresented: Binding(get: { deleteId != nil }, set: { if !$0 { deleteId = nil } }), titleVisibility: .visible) {
                Button("Delete comment", role: .destructive) { if let deleteId { Task { do { _ = try await store.request("comments/\(deleteId)", method: "DELETE"); await load() } catch { self.error = error.localizedDescription }; self.deleteId = nil } } }
            }
            .task { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
        }
    }
    private func load(next: Bool = false) async {
        do {
            let number = next ? page + 1 : 1
            let rows: [CommentRecord] = try await store.fetch("comments?target_type=\(type)&target_id=\(id)&page=\(number)")
            comments = next ? comments + rows : rows; page = number; more = rows.count == 40; error = nil
        } catch { comments = []; more = false; self.error = error.localizedDescription }
        loading = false
    }
    private func post() async {
        sending = true; defer { sending = false }
        do { _ = try await store.request("comments", method: "POST", body: ["target_type": type, "target_id": id, "body": bodyText]); bodyText = ""; await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct CircleView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var query = ""
    @State private var group = "following"
    @State private var people: [Person] = []
    @State private var feed: [WishlistRecord] = []
    @State private var loading = true
    @State private var page = 1
    @State private var more = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Picker("Your circle", selection: $group) {
                    Text("Following").tag("following")
                    Text("Followers").tag("followers")
                    Text("Discover").tag("search")
                }.pickerStyle(.segmented)
            }
            if let error { Text(error).foregroundStyle(.red); Button("Try again") { Task { await load() } } }
            if loading { ProgressView() }
            Section(query.isEmpty ? (group == "search" ? "Search by first or last name" : "Your people") : "Search results") {
                ForEach(people) { person in
                    NavigationLink(value: Destination.person(person.id)) {
                        HStack(spacing: 12) { AvatarView(person: person); VStack(alignment: .leading) { Text(person.name); Text(person.following ? "Following" : "Wishwell member").font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                if !loading && people.isEmpty { Text(query.isEmpty ? "Find someone to share a little inspiration with." : "No members found.").foregroundStyle(.secondary) }
                if more { Button("Load more people") { Task { await load(next: true) } } }
            }
            if query.isEmpty && group == "following" && !feed.isEmpty {
                Section("Shared by your circle") {
                    ForEach(feed) { list in
                        NavigationLink(value: Destination.list(list.id)) {
                            VStack(alignment: .leading, spacing: 6) { Text(list.title).font(.system(.title3, design: .serif)); Text("\(list.owner.name) · \(list.wishesCount) wishes").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    NavigationLink("Browse all shared lists") { FollowingListsView() }
                }
            }
        }.navigationTitle("Your circle")
        .searchable(text: $query, prompt: "Find people by name")
        .task(id: "\(group):\(query)") {
            do { try await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return }; await load() } catch {}
        }.refreshable { await load() }
        .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load(next: Bool = false) async {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedGroup = group
        loading = !next
        do {
            let number = next ? page + 1 : 1
            let term = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
            let path = search.isEmpty && selectedGroup != "search" ? "people?group=\(selectedGroup)&page=\(number)" : "people?q=\(term)&page=\(number)"
            let rows: [Person] = try await store.fetch(path)
            guard !Task.isCancelled && group == selectedGroup && query.trimmingCharacters(in: .whitespacesAndNewlines) == search else { return }
            people = next ? people + rows : rows; page = number; more = rows.count == 40
            if search.isEmpty && selectedGroup == "following" { feed = try await store.fetch("wlists?feed=following") } else { feed = [] }
            error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
}

struct FollowingListsView: View {
    @Environment(AppStore.self) private var store
    @State private var lists: [WishlistRecord] = []
    @State private var page = 0
    @State private var more = true
    var body: some View {
        List {
            ForEach(lists) { list in NavigationLink(value: Destination.list(list.id)) { ListCard(list: list) }.listRowSeparator(.hidden) }
            if more { Button("Load more") { Task { await load() } } }
        }.navigationTitle("Shared lists").task { if page == 0 { await load() } }
    }
    private func load() async {
        await store.perform { let rows: [WishlistRecord] = try await store.fetch("wlists?feed=following&page=\(page + 1)"); lists += rows; page += 1; more = rows.count == 40 }
    }
}

struct PersonView: View {
    let id: Int
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var loadError: String?
    @State private var profile: ProfileResponse?
    @State private var extraLists: [WishlistRecord] = []
    @State private var page = 1
    @State private var more = false
    var body: some View {
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        AvatarView(person: profile.user, size: 80)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.user.name).font(.system(.title, design: .serif))
                            Text("\(profile.user.followersCount) followers · \(profile.user.followingCount) following").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if id != store.user?.id {
                        Button(profile.user.following ? "Unfollow" : "Follow", systemImage: profile.user.following ? "person.badge.minus" : "person.badge.plus") {
                            Task { await store.perform { _ = try await store.request("people/\(id)/follow", method: profile.user.following ? "DELETE" : "POST"); await load() } }
                        }.buttonStyle(.borderedProminent).disabled(store.busy)
                    }
                    Text("Shared wishes").font(.system(.title2, design: .serif))
                    if profile.wlists.isEmpty { Text("No public wishlists yet.").foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))]) {
                        ForEach(profile.wlists + extraLists) { list in NavigationLink(value: Destination.list(list.id)) { ListCard(list: list) }.buttonStyle(.plain) }
                    }
                    if more { Button("Load more lists") { Task { await load(next: true) } } }
                }.padding(24).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn’t load this profile", systemImage: "wifi.exclamationmark")
                } description: { Text(loadError) } actions: { Button("Try again") { Task { await load() } } }
            } else { ProgressView("Loading profile…") }
        }.background(Theme.background).navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load(next: Bool = false) async {
        do {
            let number = next ? page + 1 : 1
            let response: ProfileResponse = try await store.fetch("people/\(id)?page=\(number)")
            if next { extraLists += response.wlists } else { profile = response; extraLists = [] }
            page = number; more = response.wlists.count == 40; loadError = nil
        } catch { profile = nil; loadError = error.localizedDescription }
    }
}

struct ActivityView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var rows: [ActivityRecord] = []
    @State private var loading = true
    @State private var more = false
    @State private var page = 1
    var body: some View {
        List {
            if loading { ProgressView() }
            if !loading && rows.isEmpty { ContentUnavailableView("You’re all caught up", systemImage: "bell", description: Text("Follows, likes, comments, and new wishes from your circle will appear here.")) }
            ForEach(rows) { row in
                NavigationLink(value: row.wlistId.map { Destination.list($0) } ?? Destination.person(row.actorId)) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: row.icon).foregroundStyle(Theme.green).frame(width: 36, height: 36).background(Theme.sage, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.message).font(.subheadline).fontWeight(row.read ? .regular : .semibold)
                            if let date = ISO8601DateFormatter().date(from: row.createdAt) { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                        }
                        if !row.read { Circle().fill(Theme.green).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                    }.padding(.vertical, 6)
                }
            }
            if more { Button("Load more notifications") { Task { await load(next: true) } } }
        }.navigationTitle("Notifications")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Mark shown as read") { Task { await markRead() } }.disabled(rows.allSatisfy(\.read)) } }
        .task { await load() }.refreshable { await load() }
        .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load(next: Bool = false) async {
        do {
            let number = next ? page + 1 : 1
            let response: ActivityResponse = try await store.fetch("notifications?page=\(number)")
            rows = next ? rows + response.notifications : response.notifications
            page = number; more = response.notifications.count == 40; store.unreadCount = response.unreadCount
        } catch { rows = []; store.error = error.localizedDescription }
        loading = false
    }
    private func markRead() async {
        await store.perform {
            for chunk in stride(from: 0, to: rows.count, by: 100) {
                let ids = Array(rows[chunk..<min(chunk + 100, rows.count)]).map(\.id)
                _ = try await store.request("notifications/read", method: "PATCH", body: ["ids": ids])
            }
            rows = rows.map { var row = $0; row.read = true; return row }
            let response: ActivityResponse = try await store.fetch("notifications")
            store.unreadCount = response.unreadCount
        }
    }
}
