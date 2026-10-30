import SwiftUI
import SwiftData
import UserNotifications

extension SocialStore {
    static func makeForApp() -> SocialStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--social-preview") {
            let store = SocialStore(database: DemoSocialDatabase(), enabled: true); store.isDemo = true; return store
        }
        #if !targetEnvironment(simulator)
        // --social-live-cloud uses the personal iCloud library, for checking read markers across devices.
        if ProcessInfo.processInfo.arguments.contains("--social-live-ui") || ProcessInfo.processInfo.arguments.contains("--social-live-cloud") {
            let store = SocialStore(enabled: true); store.isLiveTest = true; return store
        }
        #endif
        #endif
        return SocialStore()
    }
    func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await operation() } catch { self.error = error.localizedDescription }
    }
}

/// Push alerts for follows, likes and comments. Asked for when a profile is published, the point where alerts become useful.
@MainActor
enum AlertPermission {
    /// Live tests skip the permission prompt unless launched with --alerts, which the push alert tests use.
    static func allowed(for social: SocialStore) -> Bool {
        !social.isDemo && (!social.isLiveTest || ProcessInfo.processInfo.arguments.contains("--alerts"))
    }
    static func request() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
    static func registerIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        #if DEBUG
        print("Wishwell alerts: permission \(settings.authorizationStatus.rawValue) alert \(settings.alertSetting.rawValue) center \(settings.notificationCenterSetting.rawValue) lock \(settings.lockScreenSetting.rawValue) style \(settings.alertStyle.rawValue)")
        #endif
        if settings.authorizationStatus == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }
}

struct CircleView: View {
    @Environment(SocialStore.self) private var social
    @Environment(CloudStore.self) private var cloud
    @State private var query = ""
    @State private var group = "following"
    @State private var people: [PublicProfile] = []
    @State private var lists: [PublicList] = []
    @State private var loading = false
    @State private var message: String?
    var body: some View {
        List {
            if social.isDemo { Text("Social simulator preview · No data leaves this device").font(.caption).foregroundStyle(.secondary) }
            if social.isLiveTest { Text("Live social test · Development CloudKit\(cloud.localOnly ? " with a separate test library" : "")").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("social.liveTestBanner") }
            if !social.enabled {
                ContentUnavailableView("Your circle is being prepared", systemImage: "person.2", description: Text("CloudKit’s social permissions need to be configured before publishing. Your private library is ready to use."))
            } else if social.me == nil {
                ContentUnavailableView("Let your friends find you", systemImage: "person.crop.circle.badge.plus", description: Text("Turn on Public account in Settings to find people, follow them, and share wishlists. Each wishlist stays private until you make it public."))
            } else {
                Section {
                    Picker("Your circle", selection: $group) {
                        Text("Following").tag("following"); Text("Followers").tag("followers"); Text("Discover").tag("discover")
                    }.pickerStyle(.segmented)
                }
                if loading { ProgressView() }
                if let message { Text(message).foregroundStyle(.secondary) }
                Section(query.isEmpty ? "Your people" : "Search results") {
                    ForEach(people) { person in
                        NavigationLink { PublicPersonView(person: person) } label: { PersonRow(person: person) }
                    }
                    if loading && people.isEmpty { ProgressView() }
                    else if !loading && people.isEmpty { Text(group == "discover" && query.isEmpty ? "Search by a first or last name." : "No people to show yet.").foregroundStyle(.secondary) }
                }
                if query.isEmpty && group == "following" {
                    Section("Shared by your circle") {
                        ForEach(lists) { list in NavigationLink { PublicListView(id: list.id) } label: { PublicListRow(list: list) } }
                    }
                }
            }
        }.navigationTitle("Your circle").searchable(text: $query, prompt: "Find people by name")
            .onChange(of: group, initial: true) { _, value in
                // Show the last-known people straight away; the fresh list replaces them when it arrives.
                guard query.isEmpty else { return }
                people = social.circleCache[value] ?? []
                lists = value == "following" ? people.flatMap { social.ownerListCache[$0.ownerID] ?? [] } : []
            }
            .task(id: "\(query):\(group):\(social.me?.id ?? "")") {
                do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await load() } catch {}
            }.refreshable { await load() }
    }
    private func load() async {
        guard social.enabled, social.me != nil else { return }
        loading = true; defer { loading = false }
        do {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines), selected = group
            let rows: [PublicProfile]
            if !term.isEmpty { rows = try await social.search(term) }
            else if group == "following" { rows = try await social.following() }
            else if group == "followers", let me = social.me { rows = try await social.followers(of: me) }
            else { rows = [] }
            try Task.checkCancellation()
            guard term == query.trimmingCharacters(in: .whitespacesAndNewlines), selected == group else { return }
            people = rows
            if term.isEmpty { social.circleCache[selected] = rows }
            if term.isEmpty && group == "following" {
                var shared: [PublicList] = []
                for person in rows { shared += try await social.lists(owner: person.ownerID) }
                lists = shared
            } else { lists = [] }
            message = nil
        } catch { if !Task.isCancelled { people = []; lists = []; message = error.localizedDescription } }
    }
}

struct PersonRow: View {
    let person: PublicProfile
    var body: some View {
        HStack(spacing: 14) { PublicAvatar(person: person); Text(person.name) }
    }
}
struct PublicAvatar: View {
    let person: PublicProfile
    var body: some View {
        Group {
            if let data = person.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Text(String(person.name.prefix(1))).font(.system(.title2, design: .serif)).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.peach) }
        }.frame(width: 48, height: 48).clipShape(Circle()).accessibilityHidden(true)
    }
}
/// A person's profile photo, full size.
struct PhotoViewer: View {
    let person: PublicProfile
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let data = person.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
                .navigationTitle(person.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct PublicListRow: View {
    let list: PublicList
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(list.title).font(.system(.title3, design: .serif))
            Label("\(list.wishes.count) wishes", systemImage: "globe").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct PublicPersonView: View {
    let person: PublicProfile
    @Environment(SocialStore.self) private var social
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [PublicList] = []
    @State private var followed = false
    @State private var message: String?
    @State private var blocking = false
    @State private var reporting = false
    @State private var viewingPhoto = false
    var body: some View {
        List {
            Section {
                Button { viewingPhoto = true } label: { PersonRow(person: person) }
                    .buttonStyle(.plain).disabled(person.photo == nil).accessibilityHint(person.photo == nil ? "" : "Shows the profile photo")
            }
            if person.ownerID != social.actorID {
                Button(followed ? "Unfollow" : "Follow", systemImage: followed ? "person.badge.minus" : "person.badge.plus") {
                    // The button flips right away; it only flips back if saving fails.
                    let wanted = !followed; followed = wanted
                    Task {
                        await social.perform { try await social.follow(person, enabled: wanted) }
                        if social.error != nil { followed = !wanted }
                    }
                }.disabled(social.busy).accessibilityIdentifier("social.follow")
            }
            if let message { Text(message).foregroundStyle(.secondary) }
            Section("Public wishlists") {
                ForEach(lists) { list in NavigationLink { PublicListView(id: list.id) } label: { PublicListRow(list: list) } }
                if lists.isEmpty { Text("No public wishlists to show.").foregroundStyle(.secondary) }
            }
        }.navigationTitle(person.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if person.ownerID != social.actorID {
                    Menu {
                        Button("Report profile", systemImage: "flag") { reporting = true }
                        Button("Block this person", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { blocking = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("social.person.menu")
                }
            }.sheet(isPresented: $reporting) { ReportView(id: person.id) }
            .sheet(isPresented: $viewingPhoto) { PhotoViewer(person: person) }
            .onAppear {
                if let known = social.followingOwners { followed = known.contains(person.ownerID) }
                if lists.isEmpty { lists = social.ownerListCache[person.ownerID] ?? [] }
            }
            .confirmationDialog("Block \(person.name)?", isPresented: $blocking, titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    context.insert(HiddenPerson(ownerID: person.ownerID))
                    do { try context.save(); social.hidden.insert(person.ownerID); dismiss() }
                    catch { context.rollback(); social.error = error.localizedDescription }
                }.accessibilityIdentifier("social.person.confirmBlock")
            } message: { Text("Their content and interactions will be hidden on your devices. Anything you publish remains public. You can unblock them in Settings.") }
            .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do {
            async let shared = social.lists(owner: person.ownerID)
            async let follows = social.following()
            let (newLists, people) = try await (shared, follows)
            lists = newLists
            // Don't undo a tap that's still saving.
            if !social.busy { followed = people.contains { $0.ownerID == person.ownerID } }
            message = nil
        } catch { lists = []; message = error.localizedDescription }
    }
}

struct PublicListView: View {
    let id: String
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var phase
    @State private var list: PublicList?
    @State private var message: String?
    @State private var reporting = false
    var body: some View {
        Group {
            if let list = list ?? social.listCache[id] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("Public wishlist", systemImage: "globe").font(.caption).foregroundStyle(Theme.green)
                        Text(list.title).font(.system(.largeTitle, design: .serif))
                        ForEach(list.wishes) { wish in
                            NavigationLink { PublicWishView(listID: list.id, wishID: wish.id) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    if wish.fulfilled { Label("Fulfilled", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.caption) }
                                    Text(wish.title).font(.system(.title2, design: .serif))
                                    OptionRows(options: wish.options, interactive: false)
                                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(wish.fulfilled ? Theme.sage : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(.plain)
                        }
                        SocialThreadView(listID: id)
                    }.padding(24).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
                }
            } else if let message { ContentUnavailableView("Wishlist unavailable", systemImage: "lock", description: Text(message)) }
            else { ProgressView() }
        }.background(Theme.background).navigationTitle("Shared wishlist").navigationBarTitleDisplayMode(.inline)
            .toolbar { if let list = list ?? social.listCache[id], list.ownerID != social.actorID { Button("Report", systemImage: "flag") { reporting = true }.accessibilityIdentifier("social.list.report") } }
            .sheet(isPresented: $reporting) { ReportView(id: id) }
            .task { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load() async {
        do { list = try await social.publicList(id); message = list == nil ? "This wishlist is private, removed, or hidden." : nil; social.refreshRevision += 1 }
        catch { list = nil; message = error.localizedDescription }
    }
}

struct PublicWishView: View {
    let listID: String
    let wishID: UUID
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var phase
    @State private var wish: PublicWish?
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let wish = wish ?? social.listCache[listID]?.wishes.first(where: { $0.id == wishID }) {
                    Text(wish.title).font(.system(.largeTitle, design: .serif))
                    if wish.fulfilled { Label("Fulfilled", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                    OptionRows(options: wish.options)
                    SocialThreadView(listID: listID, wishID: wishID)
                } else { ContentUnavailableView("Wish unavailable", systemImage: "lock", description: Text(message ?? "Loading…")) }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Shared wish").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load() async {
        do { wish = try await social.publicList(listID)?.wishes.first { $0.id == wishID }; message = "This wish is no longer public."; social.refreshRevision += 1 }
        catch { wish = nil; message = error.localizedDescription }
    }
}

struct SocialThreadView: View {
    let listID: String
    var wishID: UUID?
    @Environment(SocialStore.self) private var social
    @State private var thread = SocialThread()
    @State private var loaded = false
    @State private var bodyText = ""
    @State private var message: String?
    @State private var deleteID: String?
    @State private var reportID: String?
    @State private var savingLike = false
    @FocusState private var writing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            Button {
                // The heart and count change right away; a failed save puts them back.
                let wanted = !thread.liked
                thread.liked = wanted; thread.likeCount += wanted ? 1 : -1
                savingLike = true
                Task {
                    await social.perform { try await social.setLike(listID: listID, wishID: wishID, liked: wanted) }
                    savingLike = false
                    await load()
                }
            } label: { Label("\(thread.likeCount) \(thread.likeCount == 1 ? "like" : "likes")", systemImage: thread.liked ? "heart.fill" : "heart") }
                // Toggling before the thread loads would act on a placeholder state.
                .disabled(social.busy || social.me == nil || !loaded || thread.paused)
                .accessibilityValue(loaded ? (thread.liked ? "Liked" : "Not liked") : "Loading")
                .accessibilityIdentifier("social.like")
            Text("Comments").font(.system(.title2, design: .serif))
            ForEach(thread.comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        NavigationLink { PublicPersonView(person: comment.author) } label: { Text(comment.author.name).font(.subheadline.weight(.semibold)) }
                        Spacer()
                        Menu {
                            if comment.author.ownerID == social.actorID { Button("Delete comment", role: .destructive) { deleteID = comment.id } }
                            else { Button("Report comment") { reportID = comment.id } }
                        } label: { Image(systemName: "ellipsis") }
                    }
                    Text(comment.text).textSelection(.enabled)
                    Text(comment.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16))
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if thread.paused {
                Text("Comments are paused while this list is private.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("social.thread.paused")
            } else if social.me != nil {
                HStack(alignment: .bottom) {
                    TextField("Write a comment…", text: $bodyText, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).focused($writing).accessibilityIdentifier("social.comment.text")
                    Button("Post", systemImage: "arrow.up.circle.fill") {
                        Task { await social.perform { try await social.comment(listID: listID, wishID: wishID, text: bodyText); bodyText = ""; await load() } }
                    }.labelStyle(.iconOnly).disabled(social.busy || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.count > 500).accessibilityIdentifier("social.comment.post")
                }
                Text("\(bodyText.count)/500").font(.caption2).foregroundStyle(.secondary)
            } else { Text("Turn on Public account in Settings to join the conversation.").font(.caption).foregroundStyle(.secondary) }
        }.onAppear {
            if !loaded, let cached = social.cachedThread(listID: listID, wishID: wishID) { thread = cached; loaded = true }
        }
        .task(id: social.refreshRevision) { await load() }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { writing = false }.accessibilityIdentifier("social.keyboard.done") } }
            .confirmationDialog("Delete your comment?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
                Button("Delete comment", role: .destructive) { if let id = deleteID { Task { await social.perform { try await social.deleteComment(id); deleteID = nil; await load() } } } }
            }
            .sheet(isPresented: Binding(get: { reportID != nil }, set: { if !$0 { reportID = nil } })) { if let id = reportID { ReportView(id: id) } }
    }
    private func load() async {
        do {
            let fresh = try await social.thread(listID: listID, wishID: wishID)
            // A like that's still saving would otherwise flicker back for a moment.
            if !savingLike { thread = fresh }
            message = nil; loaded = true
        } catch { thread = SocialThread(); message = error.localizedDescription; loaded = false }
    }
}

#if DEBUG
@MainActor private final class DemoSocialDatabase: SocialDatabase {
    private let user = "demo-owner"
    private var rows: [String: SocialRow] = [:]
    init() {
        let me = PublicProfile(id: "demo-you", ownerID: user, name: "You", photo: nil)
        let friend = PublicProfile(id: "demo-friend-profile", ownerID: "demo-friend", name: "Tomas", photo: nil)
        let encoder = JSONEncoder()
        for person in [me, friend] {
            rows[person.id] = SocialRow(id: person.id, kind: .profile, creator: person.ownerID, searchTokens: PublicProfile.tokens(for: person.name), payload: (try? encoder.encode(person)) ?? Data())
        }
        let list = WishList(title: "A cozy corner", category: "Home")
        let chair = try? Wish(title: "Reading chair", options: [ShoppingOption(location: "Furniture shop", price: "129"), ShoppingOption(location: "Second option", price: "149")], list: list)
        list.wishes = chair.map { [$0] } ?? []
        let snapshot = PublicList(list: list, profile: friend, id: "demo-list")
        rows[snapshot.id] = SocialRow(id: snapshot.id, kind: .list, creator: friend.ownerID, parent: friend.id, sourceID: snapshot.sourceID.uuidString, payload: (try? encoder.encode(snapshot)) ?? Data())
        rows["demo-follow"] = SocialRow(id: "demo-follow", kind: .follow, creator: user, parent: friend.id, payload: (try? encoder.encode(SocialAction())) ?? Data(), createdAt: Date().addingTimeInterval(-3600))
    }
    func userID() async throws -> String { user }
    func record(_ id: String) async throws -> SocialRow? {
        guard let row = rows[id] else { return nil }
        if row.kind == .report && row.creator != user { throw WishwellError("Report is private.") }
        return row
    }
    func query(_ query: SocialQuery) async throws -> [SocialRow] {
        rows.values.filter {
            $0.kind == query.kind && (query.creator == nil || $0.creator == query.creator) &&
            (query.parent == nil || $0.parent == query.parent) && (query.sourceID == nil || $0.sourceID == query.sourceID) &&
            (query.searchToken == nil || $0.searchTokens.contains(query.searchToken!)) && ($0.kind != .report || $0.creator == user)
        }
    }
    func save(_ value: SocialRow) async throws -> SocialRow {
        if let old = rows[value.id], old.creator != user { throw WishwellError("Only the author may edit this content.") }
        if let parent = value.parent, rows[parent] == nil { throw WishwellError("This shared content was removed.") }
        var row = value; row.creator = user; rows[row.id] = row; return row
    }
    func delete(_ row: SocialRow) async throws {
        guard rows[row.id]?.creator == user else { throw WishwellError("Only the author may delete this content.") }
        rows[row.id] = nil
        var deleted = Set([row.id])
        while true {
            let children = rows.values.filter { $0.parent.map(deleted.contains) ?? false }
            guard !children.isEmpty else { break }
            for child in children { rows[child.id] = nil; deleted.insert(child.id) }
        }
    }
}
#endif

struct ReportView: View {
    let id: String
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var sent = false
    var body: some View {
        NavigationStack {
            Form {
                if sent { Text("Your report has been submitted for review. Thank you.") }
                else {
                    Text("Tell us what’s wrong. Reports are visible to you and Wishwell’s moderation team, not other members.").font(.footnote)
                    TextField("Reason for reporting", text: $reason, axis: .vertical).lineLimit(4...8).accessibilityIdentifier("social.report.reason")
                }
            }.navigationTitle("Report content").toolbar {
                // Submit lives in the bar so the keyboard can't cover it.
                ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() }.disabled(social.busy).accessibilityIdentifier("social.report.done") }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { Task { await social.perform { try await social.report(id, reason: reason); sent = true } } }.disabled(social.busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 1000).accessibilityIdentifier("social.report.submit")
                    }
                }
            }
        }
    }
}

struct ActivityView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query private var readState: [SocialReadState]
    @State private var message: String?
    @State private var loading = false
    private var rows: [SocialActivity] { social.activityRows }
    var body: some View {
        List {
            if let message { Text(message).foregroundStyle(.secondary) }
            if rows.isEmpty && loading { ProgressView().frame(maxWidth: .infinity) }
            else if rows.isEmpty { ContentUnavailableView("You’re all caught up", systemImage: "bell", description: Text("Follows, likes, comments, and new public wishes from your circle appear here.")) }
            ForEach(rows) { row in
                Group {
                    if let list = row.list, let wishID = row.wishID { NavigationLink { PublicWishView(listID: list.id, wishID: wishID).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else if let list = row.list { NavigationLink { PublicListView(id: list.id).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else { NavigationLink { PublicPersonView(person: row.actor).onAppear { markRead([row]) } } label: { activityRow(row) } }
                }.accessibilityValue(readState.contains { $0.id == row.id } ? "Read" : "Unread")
            }
        }.navigationTitle("Notifications")
            .toolbar { Button("Mark shown as read") { markRead(rows) }.disabled(rows.isEmpty).accessibilityIdentifier("social.activity.markRead") }
            .task { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func activityRow(_ row: SocialActivity) -> some View {
        let read = readState.contains { $0.id == row.id }
        return HStack(alignment: .top, spacing: 14) {
            Circle().fill(read ? Color.clear : Theme.green).frame(width: 8, height: 8).padding(.top, 6)
            Image(systemName: row.icon).foregroundStyle(read ? Color.secondary : Theme.green)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.message).fontWeight(read ? .regular : .semibold).foregroundStyle(read ? .secondary : .primary)
                Text(row.date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
    private func load() async {
        guard social.enabled else { message = "Notifications will be available after CloudKit social setup."; return }
        loading = true; defer { loading = false }
        do { social.activityRows = try await social.activity(); message = nil }
        catch { message = error.localizedDescription }
    }
    private func markRead(_ shown: [SocialActivity]) {
        let existing = Set(readState.map(\.id))
        let fresh = shown.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for row in fresh { context.insert(SocialReadState(id: row.id)) }
        do { try context.save() } catch { context.rollback(); social.error = error.localizedDescription }
    }
}

extension SocialStore {
    /// Makes a personal wishlist public or private. Private keeps the public record, so likes and comments return when it's shared again.
    func setPublic(_ list: WishList, _ on: Bool, context: ModelContext) async throws {
        if on {
            guard let me else { throw WishwellError("Turn on your public account in Settings to share wishlists.") }
            publishing.insert(list.id); defer { publishing.remove(list.id) }
            let snapshot = PublicList(list: list, profile: me, id: list.publicRecordName ?? UUID().uuidString)
            list.publicRecordName = try await publish(snapshot, existingID: list.publicRecordName)
        } else {
            if let id = list.publicRecordName { try await pause(id) }
            list.publicRecordName = nil
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

/// The public/private switch shown on a wishlist and when creating one.
struct PublicSwitch: View {
    @Binding var isOn: Bool
    var working = false
    @Environment(SocialStore.self) private var social
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 8) {
                    Label(isOn ? "Public" : "Private", systemImage: isOn ? "globe" : "lock")
                    if working { ProgressView().controlSize(.small) }
                }
            }.tint(Theme.green).disabled(working || social.busy || !social.enabled || social.me == nil).accessibilityIdentifier("list.public")
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var note: String {
        if !social.enabled || social.me == nil { return "Turn on Public account in Settings to share wishlists." }
        return isOn ? "People using Wishwell can see this list, its wishes and prices, and like or comment on it." : "Only you can see this list."
    }
}

/// Likes and comments on one of the current person's own lists, found whether the list is public or private.
struct OwnListThread: View {
    let list: WishList
    var wishID: UUID?
    @Environment(SocialStore.self) private var social
    @State private var recordID: String?
    var body: some View {
        Group { if let recordID { SocialThreadView(listID: recordID, wishID: wishID) } }
            .task(id: list.publicRecordName) {
                guard social.enabled, social.me != nil else { recordID = nil; return }
                if let id = list.publicRecordName { recordID = id; return }
                recordID = try? await social.ownListRecord(source: list.id)?.id
            }
    }
}

#if DEBUG
import CloudKit

/// Runs only when explicitly launched with --social-live-check on a signed device.
struct LiveSocialCheckView: View {
    @State private var messages: [String] = []
    @State private var running = false
    private let database = CloudSocialDatabase()
    var body: some View {
        NavigationStack {
            List {
                Text("Development CloudKit checks").font(.headline)
                Text("Uses synthetic public records only. Your private library is not opened.")
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in Text(message).font(.caption.monospaced()) }
                if running { ProgressView("Checking your account…") }
            }.navigationTitle("Wishwell test")
        }.task { await run() }
    }
    private func note(_ message: String) {
        messages.append(message)
        print("WISHWELL_LIVE_CHECK: \(message)")
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("social-live-check-results.txt")
        try? messages.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
    }
    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw WishwellError(message) }
    }
    /// Lists this account's synthetic fixtures; deletes them only with --confirm-delete.
    @MainActor private func cleanupFixtures(user: String, delete: Bool) async throws {
        var found: [SocialRow] = []
        // Children first, so a cascade never races the explicit deletes that follow.
        for kind in [SocialKind.like, .comment, .follow, .report, .list, .profile] {
            found += try await database.query(SocialQuery(kind: kind, creator: user)).filter { $0.creator == user && SocialStore.isDiagnosticFixture($0.id) }
        }
        note("Found \(found.count) synthetic records owned by this account")
        for row in found { note("- \(row.kind.rawValue) \(row.id)") }
        guard delete else { note("DRY RUN: nothing deleted. Relaunch with --confirm-delete to remove exactly these records."); return }
        for row in found {
            do { try await database.delete(row) } catch let error as CKError where error.code == .unknownItem { }
        }
        var remaining: [String] = []
        for row in found { if try await database.record(row.id) != nil { remaining.append(row.id) } }
        try require(remaining.isEmpty, "Still present: \(remaining.joined(separator: ", "))")
        note("COMPLETE: removed \(found.count) synthetic records owned by this account.")
    }
    /// Reads another account's synthetic report. Succeeds only for an account holding the Moderator role.
    @MainActor private func moderatorCheck(user: String, reportID: String) async throws {
        try require(SocialStore.isDiagnosticFixture(reportID), "Only synthetic reports may be checked.")
        let report: SocialRow?
        do { report = try await database.record(reportID) }
        catch let error as CKError where error.code == .permissionFailure { report = nil }
        guard let report else {
            note("NOT READABLE: this account cannot read the report. Expected unless it holds the Moderator role.")
            return
        }
        try require(report.kind == .report && report.creator != user, "Use a report created by another account.")
        let listed = try await database.query(SocialQuery(kind: .report, creator: report.creator))
        try require(listed.contains { $0.id == reportID }, "Report was fetched but not returned by a creator query.")
        note("PASS: this account can read and query another account's report (Moderator access).")
    }
    @MainActor private func cascadeCheck(user: String) async throws -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--cleanup-fixtures") {
            try await cleanupFixtures(user: user, delete: arguments.contains("--confirm-delete"))
            return true
        }
        if let index = arguments.firstIndex(of: "--moderator-check"), arguments.indices.contains(index + 1) {
            try await moderatorCheck(user: user, reportID: arguments[index + 1])
            return true
        }
        if let index = arguments.firstIndex(of: "--unpublish-fixture"), arguments.indices.contains(index + 1) {
            let id = arguments[index + 1]
            try require(id.hasPrefix("wishwell-check-"), "Only synthetic fixtures may be unpublished.")
            guard let row = try await database.record(id), row.kind == .list, row.creator == user else {
                throw WishwellError("The synthetic list must belong to the current account.")
            }
            try await database.delete(row)
            do {
                _ = try await database.save(row)
                throw WishwellError("A stale save recreated the unpublished test list.")
            } catch let error as CKError where error.code == .unknownItem || error.code == .serverRecordChanged { }
            note("COMPLETE: synthetic list unpublished; stale recreation rejected by server.")
            return true
        }
        if let index = arguments.firstIndex(of: "--verify-cascade"), arguments.indices.contains(index + 3) {
            let ids = Array(arguments[(index + 1)...(index + 3)])
            try require(ids.allSatisfy { $0.hasPrefix("wishwell-check-") }, "Only synthetic fixtures may be checked.")
            for attempt in 0..<30 {
                var remaining = 0
                for id in ids { if try await database.record(id) != nil { remaining += 1 } }
                if remaining == 0 {
                    note("COMPLETE: unpublished root and the other account's like/comment are absent on Apple's service.")
                    return true
                }
                if attempt == 0 { note("Waiting for asynchronous CloudKit cascade…") }
                try await Task.sleep(for: .seconds(1))
            }
            throw WishwellError("Cascade did not finish within this check; do not assume dependent deletion is complete.")
        }
        return false
    }

    @MainActor private func crossAccountChecks(user: String, prefix: String) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--peer-profile"), arguments.indices.contains(index + 3) else {
            note("COMPLETE: first-account checks passed. Cross-account permissions are still unverified.")
            return
        }
        let profileID = arguments[index + 1], listID = arguments[index + 2], reportID = arguments[index + 3]
        try require([profileID, listID, reportID].allSatisfy { $0.hasPrefix("wishwell-check-") }, "Only synthetic fixtures may be tested.")
        guard let peer = try await database.record(profileID), peer.kind == .profile,
              let list = try await database.record(listID), list.kind == .list else { throw WishwellError("Peer synthetic records are unavailable.") }
        try require(peer.creator != user && list.creator == peer.creator, "Two distinct Apple accounts are required.")
        note("PASS: distinct Apple accounts and public profile/list reads")
        let matches = try await database.query(SocialQuery(kind: .profile, creator: peer.creator))
        try require(matches.contains { $0.id == profileID }, "Creator query did not return the peer profile.")
        note("PASS: public creator query")
        let encoder = JSONEncoder()
        for foreign in [peer, list] {
            do {
                _ = try await database.save(foreign)
                throw WishwellError("Server permitted an update to another account's synthetic record.")
            } catch let error as CKError where error.code == .permissionFailure { }
            do {
                try await database.delete(foreign)
                throw WishwellError("Server permitted deletion of another account's synthetic record.")
            } catch let error as CKError where error.code == .permissionFailure { }
        }
        note("PASS: server denies foreign profile/list updates and deletion")
        do {
            let report = try await database.record(reportID)
            try require(report == nil, "Another account's report was readable.")
        } catch let error as CKError where error.code == .permissionFailure { }
        let reports = try await database.query(SocialQuery(kind: .report, creator: peer.creator))
        try require(reports.isEmpty, "Report query exposed another account's reports.")
        note("PASS: foreign report hidden from direct fetch and creator query")
        _ = try await database.save(SocialRow(id: prefix + "-peer-follow", kind: .follow, parent: profileID, payload: encoder.encode(SocialAction())))
        let like = try await database.save(SocialRow(id: prefix + "-peer-like", kind: .like, parent: listID, payload: encoder.encode(SocialAction())))
        let comment = try await database.save(SocialRow(id: prefix + "-peer-comment", kind: .comment, parent: listID, payload: encoder.encode(SocialAction(text: "Synthetic cross-account comment"))))
        try require(like.creator == user && comment.creator == user, "Interaction creator metadata did not match.")
        try require(try await database.record(comment.id) != nil, "Own comment on peer list could not be read.")
        try await database.delete(comment)
        try await database.delete(like)
        note("PASS: follow, like/comment on peer list, and delete own interactions")
        _ = try await database.save(SocialRow(id: prefix + "-cascade-like", kind: .like, parent: listID, payload: encoder.encode(SocialAction())))
        _ = try await database.save(SocialRow(id: prefix + "-cascade-comment", kind: .comment, parent: listID, payload: encoder.encode(SocialAction(text: "Synthetic cascade check"))))
        note("Prepared synthetic interactions for cross-account cascade verification")
        note("COMPLETE: first-account and cross-account checks passed. Reciprocal checks and cascade removal remain.")
    }

    @MainActor private func run() async {
        guard !running, messages.isEmpty else { return }
        running = true; defer { running = false }
        do {
            #if targetEnvironment(simulator)
            throw WishwellError("Use a signed physical device for this check.")
            #else
            let encoder = JSONEncoder()
            if ProcessInfo.processInfo.arguments.contains("--initialize-cloudkit-schema") {
                var failure: NSError?
                do { try await CloudStore.initializeCloudKitSchema() } catch let error as NSError { failure = error }
                let removed = try await CloudStore.removeSchemaPlaceholders()
                note("PASS: removed \(removed) schema placeholder records.")
                if let failure { note("FAIL: \(failure.domain) \(failure.code) \(failure.userInfo)"); return }
                note("COMPLETE: private SwiftData record types and fields initialized in development.")
                return
            }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--alert-probe") {
                // Unfiltered comment subscription, to tell a filter problem from a delivery problem.
                let database = CKContainer(identifier: CloudStore.containerID).publicCloudDatabase
                let id = "ww-probe-comment"
                if ProcessInfo.processInfo.arguments.dropFirst(index + 1).first == "off" {
                    _ = try await database.deleteSubscription(withID: id)
                    note("COMPLETE: probe subscription removed.")
                } else {
                    let probe = CKQuerySubscription(recordType: SocialKind.comment.rawValue, predicate: NSPredicate(value: true), subscriptionID: id, options: .firesOnRecordCreation)
                    probe.zoneID = CKRecordZone.default().zoneID
                    let info = CKSubscription.NotificationInfo(); info.alertBody = "Probe: a comment was created."; info.soundName = "default"
                    probe.notificationInfo = info
                    _ = try await database.save(probe)
                    note("COMPLETE: probe subscription saved.")
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--remove-schema-placeholders") {
                note("COMPLETE: removed \(try await CloudStore.removeSchemaPlaceholders()) schema placeholder records.")
                return
            }
            let user = try await database.userID()
            note("PASS: signed-in CloudKit identity, user record \(user)")
            if try await cascadeCheck(user: user) { return }
            let prefix = "wishwell-check-\(UUID().uuidString)"
            let profileID = prefix + "-profile", listID = prefix + "-list", reportID = prefix + "-report"
            let manifest = ["profileID": profileID, "listID": listID, "reportID": reportID]
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("social-live-check-fixture.json")
            try encoder.encode(manifest).write(to: file, options: .atomic)
            let profile = PublicProfile(id: profileID, ownerID: user, name: "Wishwell permission test", photo: nil)
            let savedProfile = try await database.save(SocialRow(id: profileID, kind: .profile, sourceID: prefix, searchTokens: PublicProfile.tokens(for: profile.name), payload: encoder.encode(profile)))
            try require(savedProfile.creator == user, "Creator metadata did not match this account.")
            note("PASS: create profile and server-derived authorship")
            guard var fetched = try await database.record(profileID) else { throw WishwellError("Created profile could not be read.") }
            fetched.payload = try encoder.encode(profile)
            _ = try await database.save(fetched)
            note("PASS: read and update own profile")
            let source = WishList(title: "Wishwell permission test — synthetic")
            let snapshot = PublicList(list: source, profile: profile, id: listID)
            let list = try await database.save(SocialRow(id: listID, kind: .list, parent: profileID, sourceID: source.id.uuidString, payload: encoder.encode(snapshot)))
            try require(list.creator == user, "List creator metadata did not match.")
            note("PASS: publish synthetic list")
            _ = try await database.save(SocialRow(id: prefix + "-like", kind: .like, parent: listID, payload: encoder.encode(SocialAction())))
            _ = try await database.save(SocialRow(id: prefix + "-comment", kind: .comment, parent: listID, payload: encoder.encode(SocialAction(text: "Synthetic permission check"))))
            note("PASS: create own like and comment")
            _ = try await database.save(SocialRow(id: reportID, kind: .report, payload: encoder.encode(["target": listID, "reason": "Synthetic permission test; no moderation action needed"])))
            try require(try await database.record(reportID) != nil, "Own report could not be read.")
            note("PASS: create and read own report")
            let temporary = try await database.save(SocialRow(id: prefix + "-stale", kind: .list, parent: profileID, payload: encoder.encode(snapshot)))
            try await database.delete(temporary)
            do {
                _ = try await database.save(temporary)
                throw WishwellError("A stale save recreated a deleted root.")
            } catch let error as CKError where error.code == .unknownItem || error.code == .serverRecordChanged {
                note("PASS: server rejects stale save after unpublish")
            }
            try await crossAccountChecks(user: user, prefix: prefix)
            #endif
        } catch { note("FAIL: \(error.localizedDescription)") }
    }
}
#endif
