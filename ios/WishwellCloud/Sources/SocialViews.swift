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
        print("Wishwell alerts: permission \(settings.authorizationStatus.rawValue) alert \(settings.alertSetting.rawValue) center \(settings.notificationCenterSetting.rawValue) lock \(settings.lockScreenSetting.rawValue) style \(settings.alertStyle.rawValue) badge \(settings.badgeSetting.rawValue)")
        #endif
        guard settings.authorizationStatus == .authorized else { return }
        // People who allowed alerts before badges were asked for never got the app icon's number.
        // Asking again doesn't show a prompt once alerts are allowed; it adds badges to Wishwell's settings.
        if settings.badgeSetting != .enabled { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// The people you've added, as a grid of photos. Tap someone to see their wishlists.
struct CircleView: View {
    @Environment(SocialStore.self) private var social
    @Environment(CloudStore.self) private var cloud
    @State private var query = ""
    @State private var results: [PublicProfile] = []
    @State private var searching = false
    @State private var message: String?
    private var people: [PublicProfile] { social.circleCache["following"] ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if social.isLiveTest { Text("Live social test · Development CloudKit\(cloud.localOnly ? " with a separate test library" : "")").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("social.liveTestBanner") }
                if !social.enabled {
                    ContentUnavailableView("Your circle is being prepared", systemImage: "person.2", description: Text("Your private library is ready to use."))
                } else if social.me == nil {
                    ContentUnavailableView("Let your people find you", systemImage: "person.crop.circle.badge.plus", description: Text("Turn on Public account in Settings to add people to your circle and see their wishlists."))
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if searching && results.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    else if results.isEmpty { Text("No one by that name yet.").foregroundStyle(.secondary) }
                    ForEach(results) { person in
                        NavigationLink { PublicPersonView(person: person) } label: {
                            HStack(spacing: 14) { PublicAvatar(person: person, size: 52); Text(person.name).foregroundStyle(.primary); Spacer()
                                if social.followingOwners?.contains(person.ownerID) == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green) } }
                        }.buttonStyle(.plain)
                    }
                } else if people.isEmpty {
                    ContentUnavailableView("Your circle is empty", systemImage: "person.2", description: Text("Search for someone by name to add them. Then you can see their wishlists whenever you’re looking for a gift."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 18)], spacing: 22) {
                        ForEach(people) { person in
                            NavigationLink { PublicPersonView(person: person) } label: {
                                VStack(spacing: 8) {
                                    PublicAvatar(person: person, size: 84)
                                    Text(person.name).font(.subheadline).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.primary)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("circle.person")
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Your circle").searchable(text: $query, prompt: "Find people by name")
            .task(id: query) {
                let term = query.trimmingCharacters(in: .whitespaces)
                guard !term.isEmpty else { results = []; return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                searching = true; defer { searching = false }
                do { results = try await social.search(term).filter { $0.ownerID != social.actorID }; message = nil }
                catch { if !Task.isCancelled { message = error.localizedDescription } }
            }
            .task(id: social.me?.id) { await refresh() }
            .refreshable { await refresh() }
    }
    private func refresh() async {
        guard social.enabled, social.me != nil else { return }
        do { _ = try await social.following(); message = nil } catch { message = error.localizedDescription }
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
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let data = person.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Text(String(person.name.prefix(1))).font(.system(size: size * 0.42, design: .serif)).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.peach) }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}
/// Opens someone's profile when only its record name is known, as with a notification that just arrived.
struct PersonLoader: View {
    let id: String
    @Environment(SocialStore.self) private var social
    @State private var person: PublicProfile?
    @State private var missing = false
    var body: some View {
        Group {
            if let person { PublicPersonView(person: person) }
            else if missing { ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.xmark") }
            else { ProgressView() }
        }.task {
            person = try? await social.person(id)
            missing = person == nil
        }
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

/// Who's getting a wish, as each person is allowed to see it.
struct ClaimBadge: View {
    let state: ClaimState?
    var body: some View {
        switch state {
        case .mine: Label("You’re getting this", systemImage: "gift.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
        case .other(let name): Label("\(name) is getting this", systemImage: "gift.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .someone: Label("Someone might be getting this", systemImage: "gift").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
        case nil: EmptyView()
        }
    }
}

/// "I'm getting this" for someone else's wish. It changes at once and goes back if saving fails.
struct GetThisButton: View {
    let listID: String
    let wishID: UUID
    @Binding var state: ClaimState?
    @Environment(SocialStore.self) private var social
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .other(let name):
                Label("\(name) is getting this", systemImage: "gift.fill").foregroundStyle(.secondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
            case .mine:
                Label("You’re getting this", systemImage: "gift.fill").font(.headline).foregroundStyle(Theme.green)
                Button("I’m not getting it anymore") { set(false) }.disabled(saving).accessibilityIdentifier("claim.undo")
            default:
                Button { set(true) } label: { Label("I’m getting this", systemImage: "gift").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(saving || social.me == nil).accessibilityIdentifier("claim.get")
                Text(social.me == nil ? "Turn on Public account in Settings to mark gifts you’re getting." : "Others will see you’re getting it, so nobody buys it twice. The person who wished for it won’t see who.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
    }
    private func set(_ on: Bool) {
        let before = state
        state = on ? .mine : nil; saving = true; message = nil
        Task {
            do { try await social.setClaim(listID: listID, wishID: wishID, on: on) }
            catch { state = before; message = error.localizedDescription }
            saving = false
        }
    }
}

struct PublicListRow: View {
    let list: PublicList
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(list.title).font(.system(.title3, design: .serif))
            Label(list.wishes.count == 1 ? "1 wish" : "\(list.wishes.count) wishes", systemImage: "globe").font(.caption).foregroundStyle(.secondary)
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
                VStack(spacing: 12) {
                    Button { viewingPhoto = true } label: { PublicAvatar(person: person, size: 110) }
                        .buttonStyle(.plain).disabled(person.photo == nil).accessibilityLabel("Profile photo").accessibilityHint(person.photo == nil ? "" : "Shows the photo full size")
                    Text(person.name).font(.system(.title2, design: .serif))
                }.frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            if person.ownerID != social.actorID {
                // Removing someone lives in the ••• menu, so a stray tap here never drops them.
                if followed { Label("In your circle", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).accessibilityIdentifier("social.inCircle") }
                else { Button("Add to my circle", systemImage: "person.badge.plus") { toggleCircle() }.accessibilityIdentifier("social.follow") }
            }
            if let message { Text(message).foregroundStyle(.secondary) }
            Section("Wishlists") {
                ForEach(lists) { list in NavigationLink { PublicListView(id: list.id) } label: { PublicListRow(list: list) } }
                if lists.isEmpty { Text("\(person.name) hasn’t shared any wishlists yet.").foregroundStyle(.secondary) }
            }
        }.navigationTitle(person.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if person.ownerID != social.actorID {
                    Menu {
                        Button("Report profile", systemImage: "flag") { reporting = true }
                        if followed { Button("Remove from my circle", systemImage: "person.badge.minus") { toggleCircle() } }
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
                    catch { context.rollback(); social.error = error.localizedDescription; return }
                    let id = person.id
                    Task { try? await social.report(id, reason: "Blocked by a member") }
                }.accessibilityIdentifier("social.person.confirmBlock")
            } message: { Text("Their profile and lists will be hidden from you, and we'll be told so we can check their content. You can unblock them in Settings.") }
            .task { await load() }.refreshable { await load() }
    }
    /// Changes at once; goes back only if saving fails.
    private func toggleCircle() {
        let wanted = !followed; followed = wanted
        Task {
            do {
                try await social.follow(person, enabled: wanted)
                var people = social.circleCache["following"] ?? []
                if wanted { if !people.contains(where: { $0.ownerID == person.ownerID }) { people.append(person) } }
                else { people.removeAll { $0.ownerID == person.ownerID } }
                social.circleCache["following"] = people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch { followed = !wanted; message = error.localizedDescription }
        }
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
    @State private var claims: [UUID: ClaimState] = [:]
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
                                    ClaimBadge(state: claims[wish.id])
                                }.opacity(isTaken(claims[wish.id]) ? 0.55 : 1).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(wish.fulfilled ? Theme.sage : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(.plain)
                        }
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
        if claims.isEmpty { claims = social.claimCache[id] ?? [:] }
        do {
            async let fresh = social.publicList(id)
            async let taken = social.claims(listID: id)
            list = try await fresh
            claims = (try? await taken) ?? claims
            message = list == nil ? "This wishlist is private, removed, or hidden." : nil
        } catch { list = nil; message = error.localizedDescription }
    }
    private func isTaken(_ state: ClaimState?) -> Bool { if case .other = state { true } else { false } }
}

struct PublicWishView: View {
    let listID: String
    let wishID: UUID
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var phase
    @State private var wish: PublicWish?
    @State private var claim: ClaimState?
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let wish = wish ?? social.listCache[listID]?.wishes.first(where: { $0.id == wishID }) {
                    Text(wish.title).font(.system(.largeTitle, design: .serif))
                    if wish.fulfilled { Label("Fulfilled", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                    OptionRows(options: wish.options)
                    if social.listCache[listID]?.ownerID == social.actorID { ClaimBadge(state: claim) }
                    else if !wish.fulfilled { GetThisButton(listID: listID, wishID: wishID, state: $claim) }
                } else { ContentUnavailableView("Wish unavailable", systemImage: "lock", description: Text(message ?? "Loading…")) }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Shared wish").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load() async {
        if claim == nil { claim = social.claimCache[listID]?[wishID] }
        do {
            async let fresh = social.publicList(listID)
            async let taken = social.claims(listID: listID)
            wish = try await fresh?.wishes.first { $0.id == wishID }
            if let states = try? await taken { claim = states[wishID] }
            message = "This wish is no longer public."
        } catch { wish = nil; message = error.localizedDescription }
    }
}

#if DEBUG
@MainActor private final class DemoSocialDatabase: SocialDatabase {
    private let user = "demo-owner"
    private var rows: [String: SocialRow] = [:]
    init() {
        let encoder = JSONEncoder()
        func add(_ row: SocialRow) { rows[row.id] = row }
        let me = PublicProfile(id: "demo-you", ownerID: user, name: "You", photo: nil)
        add(SocialRow(id: me.id, kind: .profile, creator: user, searchTokens: PublicProfile.tokens(for: me.name), payload: (try? encoder.encode(me)) ?? Data()))
        // Made-up people for trying the circle: everyone is in your circle and has you in theirs.
        let people: [(id: String, name: String, hue: CGFloat, lists: [(String, String, [(String, [(String, String)])])])] = [
            ("friend", "Tomas", 0.08, [("A cozy corner", "Home", [("Reading chair", [("Furniture shop", "129"), ("Second option", "149")]), ("Linen throw blanket", [("https://www.target.com/s?searchTerm=linen+throw+blanket", "45")])])]),
            ("layla", "Layla Haddad", 0.92, [("Birthday", "Celebrations", [("Silver hoop earrings", [("etsy.com/search?q=silver+hoop+earrings", "68")]), ("Pottery class for two", [("Clay studio", "120")]), ("Rose candle", [("https://www.amazon.com/s?k=rose+candle", "24"), ("Candle shop", "28")])]),
                                             ("Kitchen", "Home", [("Stand mixer", [("https://www.kitchenaid.com", "349"), ("https://www.amazon.com/s?k=stand+mixer", "329")])])]),
            ("omar", "Omar Saleh", 0.58, [("Running", "Sport", [("Trail running shoes", [("https://www.rei.com/search?q=trail+running+shoes", "140")]), ("Wireless earbuds", [("https://www.bestbuy.com/site/searchpage.jsp?st=wireless+earbuds", "199")])])]),
            ("nadia", "Nadia Karim", 0.35, [("Books to read", "Books", [("The Overstory", [("https://bookshop.org/search?keywords=the+overstory", "18")]), ("Braiding Sweetgrass", [("Local bookshop", "20")])]),
                                             ("Garden", "Outdoors", [("Herb planter", [("Garden centre", "35")])])]),
            ("yusuf", "Yusuf Amin", 0.75, [("Desk setup", "Work", [("Mechanical keyboard", [("https://www.amazon.com/s?k=mechanical+keyboard", "110")]), ("Desk lamp", [("ikea.com/us/en/search/?q=desk+lamp", "60")])])]),
        ]
        var firstWish: [String: UUID] = [:]
        for (index, person) in people.enumerated() {
            let owner = "demo-\(person.id)"
            let profile = PublicProfile(id: "demo-\(person.id)-profile", ownerID: owner, name: person.name, photo: Self.portrait(person.name, hue: person.hue))
            add(SocialRow(id: profile.id, kind: .profile, creator: owner, searchTokens: PublicProfile.tokens(for: person.name), payload: (try? encoder.encode(profile)) ?? Data()))
            add(SocialRow(id: "demo-follow-\(person.id)", kind: .follow, creator: user, parent: profile.id, payload: (try? encoder.encode(SocialAction())) ?? Data(), createdAt: Date().addingTimeInterval(-86_400)))
            add(SocialRow(id: "demo-follows-you-\(person.id)", kind: .follow, creator: owner, parent: me.id, payload: (try? encoder.encode(SocialAction())) ?? Data(), createdAt: Date().addingTimeInterval(Double(-3600 * (index + 1)))))
            for (listIndex, entry) in person.lists.enumerated() {
                let list = WishList(title: entry.0, category: entry.1)
                list.wishes = entry.2.compactMap { wish in try? Wish(title: wish.0, options: wish.1.map { ShoppingOption(location: $0.0, price: $0.1) }, list: list) }
                let id = person.id == "friend" ? "demo-list" : "demo-\(person.id)-list-\(listIndex)"
                let snapshot = PublicList(list: list, profile: profile, id: id)
                if firstWish[person.id] == nil { firstWish[person.id] = snapshot.wishes.first?.id }
                add(SocialRow(id: id, kind: .list, creator: owner, parent: profile.id, sourceID: snapshot.sourceID.uuidString, payload: (try? encoder.encode(snapshot)) ?? Data()))
            }
        }
        // Omar is already getting Layla's earrings, so that wish shows as taken.
        if let earrings = firstWish["layla"] {
            add(SocialRow(id: "demo-claim-earrings", kind: .claim, creator: "demo-omar", parent: "demo-layla-list-0", payload: (try? encoder.encode(GiftClaim(wishID: earrings, active: true))) ?? Data()))
        }
    }
    /// A soft coloured circle with initials, standing in for a profile photo.
    private static func portrait(_ name: String, hue: CGFloat) -> Data? {
        let size = CGSize(width: 300, height: 300)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1).cgColor, UIColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let initials = name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 110, weight: .semibold), .foregroundColor: UIColor.white]
            let text = initials as NSString, textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
        return image.jpegData(compressionQuality: 0.8)
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
        var row = value; row.creator = user; row.modifiedAt = Date(); rows[row.id] = row; return row
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
    /// Banners that arrived show first, until the full details from iCloud replace them.
    private var rows: [SocialActivity] { (social.deliveredRows + social.activityRows).sorted { $0.date > $1.date } }
    var body: some View {
        List {
            if let message { Text(message).foregroundStyle(.secondary) }
            if rows.isEmpty && loading { ProgressView().frame(maxWidth: .infinity) }
            else if rows.isEmpty { ContentUnavailableView("You’re all caught up", systemImage: "bell", description: Text("When someone adds you to their circle, might be getting one of your wishes, or adds a new wish, it shows up here.")) }
            ForEach(rows) { row in
                Group {
                    if let list = row.list, let wishID = row.wishID { NavigationLink { PublicWishView(listID: list.id, wishID: wishID).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else if let list = row.list { NavigationLink { PublicListView(id: list.id).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else if let actor = row.actor { NavigationLink { PublicPersonView(person: actor).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else if let listID = row.linkListID, let wishID = row.wishID { NavigationLink { PublicWishView(listID: listID, wishID: wishID).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else if let profileID = row.linkProfileID { NavigationLink { PersonLoader(id: profileID).onAppear { markRead([row]) } } label: { activityRow(row) } }
                    else { activityRow(row) }
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
            if let id = list.publicRecordName { try await pause(id, wishIDs: (list.wishes ?? []).map(\.id)) }
            list.publicRecordName = nil
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

/// Called when a wish leaves one of this person's lists (deleted or moved), so anyone getting it can be told.
/// A private list's record is kept in step too, since the website can't see the list itself.
@MainActor func reportWishLeaving(_ wishID: UUID, from list: WishList, social: SocialStore) {
    guard !social.isDemo, social.enabled, social.me != nil else { return }
    let known = list.publicRecordName, source = list.id
    let remaining = (list.wishes ?? []).map(\.id).filter { $0 != wishID }
    Task {
        if let known { return await PushService.reportRemoval(list: known, wishes: [wishID]) }
        guard let record = try? await social.ownListRecord(source: source)?.id else { return }
        await PushService.reportRemoval(list: record, wishes: [wishID])
        try? await social.updatePaused(record, wishIDs: remaining)
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
        return isOn ? "People using Wishwell can see this list, its wishes and prices, and say when they're getting you something." : "Only you can see this list."
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
        for kind in [SocialKind.claim, .follow, .report, .list, .profile] {
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
                    note("COMPLETE: unpublished root and the other account's claim is absent on Apple's service.")
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
        let like = try await database.save(SocialRow(id: prefix + "-peer-like", kind: .claim, parent: listID, payload: encoder.encode(SocialAction())))
        try require(like.creator == user, "Interaction creator metadata did not match.")
        try require(try await database.record(like.id) != nil, "Own claim on peer list could not be read.")
        try await database.delete(like)
        note("PASS: follow, claim on peer list, and delete own interactions")
        _ = try await database.save(SocialRow(id: prefix + "-cascade-like", kind: .claim, parent: listID, payload: encoder.encode(SocialAction())))
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
            _ = try await database.save(SocialRow(id: prefix + "-like", kind: .claim, parent: listID, payload: encoder.encode(SocialAction())))
            note("PASS: create own claim")
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
