import SwiftUI

@main struct WishwellApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(Theme.green)
        }
    }
}

enum Theme {
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.48, green: 0.68, blue: 0.51, alpha: 1) : UIColor(red: 0.24, green: 0.36, blue: 0.27, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let peach = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.27, blue: 0.22, alpha: 1) : UIColor(red: 0.96, green: 0.86, blue: 0.79, alpha: 1)
    })
    static let sage = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.23, blue: 0.17, alpha: 1) : UIColor(red: 0.88, green: 0.93, blue: 0.87, alpha: 1)
    })
}

enum Area: String, CaseIterable, Identifiable {
    case lists = "My Lists", circle = "Circle", activity = "Notifications", profile = "Profile"
    var id: String { rawValue }
    var icon: String {
        switch self { case .lists: "heart.text.clipboard"; case .circle: "person.2"; case .activity: "bell"; case .profile: "person.crop.circle" }
    }
}
enum Destination: Hashable { case list(Int), person(Int), wish(WishRecord) }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase
    @State private var area: Area? = .lists
    @State private var selectedTab: Area = .lists

    var body: some View {
        @Bindable var store = store
        Group {
            if store.restoring { ProgressView("Opening Wishwell…") }
            else if store.user == nil { AuthenticationView() }
            else if sizeClass == .regular {
                NavigationSplitView {
                    List(Area.allCases, selection: $area) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                    .navigationTitle("Wishwell")
                    .safeAreaInset(edge: .bottom) {
                        Text("A little room for what you love.").font(.footnote).foregroundStyle(.secondary).padding()
                    }
                } detail: { section(area ?? .lists).id(area) }
            } else {
                TabView(selection: $selectedTab) {
                    ForEach(Area.allCases) { item in
                        section(item).tabItem { Label(item.rawValue, systemImage: item.icon) }
                            .tag(item).badge(item == .activity ? store.unreadCount : 0)
                    }
                }
            }
        }
        .task { await store.restore() }
        .onChange(of: phase) { _, new in
            if new == .active && store.user != nil { Task { await store.perform { try await store.reload() } } }
        }
        .alert("Wishwell", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    @ViewBuilder private func section(_ item: Area) -> some View {
        NavigationStack {
            Group {
                switch item {
                case .lists: MyListsView()
                case .circle: CircleView()
                case .activity: ActivityView()
                case .profile: AccountView()
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .list(let id): WishlistDetailView(id: id)
                case .person(let id): PersonView(id: id)
                case .wish(let wish): WishDetailView(initial: wish)
                }
            }
        }
    }
}

struct AvatarView: View {
    let person: Person
    var size: CGFloat = 48
    var body: some View {
        AsyncImage(url: URL(string: person.avatarUrl ?? "")) { image in image.resizable().scaledToFill() } placeholder: {
            Text(person.initials.isEmpty ? "W" : person.initials).font(.system(.title3, design: .serif)).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.peach)
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct ListCard: View {
    let list: WishlistRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: list.isPublic ? "globe" : "lock").foregroundStyle(Theme.green)
                Spacer()
                Text(list.category.isEmpty ? "WISHLIST" : list.category.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(list.title).font(.system(.title2, design: .serif)).foregroundStyle(.primary)
            HStack {
                Text("\(list.wishesCount) \(list.wishesCount == 1 ? "wish" : "wishes")").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sage.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MyListsView: View {
    @Environment(AppStore.self) private var store
    @State private var creating = false
    @State private var loaded = false
    @State private var page = 1
    @State private var more = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A LITTLE ROOM FOR WHAT YOU LOVE").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.green)
                    Text("Keep a little\nwonder close.").font(.system(size: 38, weight: .regular, design: .serif))
                    Text("Big dreams, small joys, and everything in between.").foregroundStyle(.secondary)
                }.padding(.top, 12)
                if !loaded && store.lists.isEmpty { ProgressView() }
                else if store.lists.isEmpty {
                    ContentUnavailableView("Your first wish starts here", systemImage: "sparkles", description: Text("Create a wishlist to collect the things you’re hoping for."))
                    Button("Create a wishlist") { creating = true }.buttonStyle(.borderedProminent)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(store.lists) { list in
                            NavigationLink(value: Destination.list(list.id)) { ListCard(list: list) }.buttonStyle(.plain)
                        }
                    }
                    if more { Button("Load more lists") { Task { await loadMore() } }.disabled(store.busy) }
                }
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Theme.background).navigationTitle("Wishwell")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("New list", systemImage: "plus") { creating = true } } }
        .sheet(isPresented: $creating) { WishlistEditor { _ in Task { await refresh() } } }
        .task { await refresh() }
        .refreshable { await refresh() }
    }
    private func refresh() async {
        await store.perform { try await store.reload(); page = 1; more = store.lists.count == 40 }
        loaded = true
    }
    private func loadMore() async {
        await store.perform {
            let next: [WishlistRecord] = try await store.fetch("wlists?page=\(page + 1)")
            store.lists += next; page += 1; more = next.count == 40
        }
    }
}

struct AuthenticationView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var first = ""
    @State private var last = ""
    @State private var registering = false
    @State private var recovery = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "heart.fill").font(.system(size: 30)).foregroundStyle(Theme.green).padding(20).background(Theme.sage, in: RoundedRectangle(cornerRadius: 22))
                    Text("Wishwell").font(.system(size: 48, design: .serif))
                    Text(registering ? "Make room for your wishes." : "Your wishes.\nA little closer.").font(.system(.largeTitle, design: .serif))
                    Text("Collect the things you love and share a little inspiration with your circle.").foregroundStyle(.secondary)
                    VStack(spacing: 14) {
                        if registering {
                            TextField("First name", text: $first).textContentType(.givenName)
                            TextField("Last name", text: $last).textContentType(.familyName)
                        }
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password)
                    }.textFieldStyle(.roundedBorder)
                    Button { Task { await store.perform { try await store.authenticate(email: email, password: password, first: first, last: last, register: registering) } } } label: {
                        HStack { Spacer(); if store.busy { ProgressView() } else { Text(registering ? "Create account" : "Sign in") }; Spacer() }.padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent).disabled(store.busy || email.isEmpty || password.isEmpty)
                    Button(registering ? "Already a member? Sign in" : "New to Wishwell? Create an account") { registering.toggle() }
                    if !registering { Button("Forgot password?") { recovery = true }.font(.footnote) }
                    #if DEBUG
                    Text(store.baseURL.host == "wishwell-22rh.onrender.com" ? "Live Wishwell" : "Development preview").font(.caption2).foregroundStyle(.secondary)
                    #endif
                }.padding(32).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(Theme.background)
            .alert("Reset password", isPresented: $recovery) {
                TextField("Email", text: $email)
                Button("Send instructions") { Task { await store.perform { _ = try await store.request("password_recovery", method: "POST", body: ["email": email]); store.error = "If that account exists, recovery instructions will be sent." } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("We’ll email you a link to choose a new password.") }
        }
    }
}
