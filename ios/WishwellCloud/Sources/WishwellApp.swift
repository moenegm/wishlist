import SwiftUI
import SwiftData
import CryptoKit

@main struct WishwellCloudApp: App {
    @State private var cloud = CloudStore()
    private var liveSocialCheck: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--social-live-check")
        #else
        false
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if liveSocialCheck {
                    #if DEBUG
                    LiveSocialCheckView()
                    #endif
                } else if let container = cloud.container {
                    LibraryRoot().modelContainer(container).id(ObjectIdentifier(container))
                } else {
                    VStack(spacing: 22) {
                        Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(Theme.green)
                        Text("Wishwell").font(.system(size: 48, design: .serif))
                        Text("A little room for what you love.").foregroundStyle(.secondary)
                        if cloud.loading { ProgressView("Opening your library…") }
                        if let error = cloud.error { Text(error).font(.callout).multilineTextAlignment(.center) }
                        Button("Connect to iCloud") { Task { await cloud.open() } }.buttonStyle(.borderedProminent).disabled(cloud.loading)
                        Button("Use on this device") { Task { await cloud.open(local: true) } }.disabled(cloud.loading)
                        Text("Your on-device library stays separate from iCloud. Use backup and import to transfer wishes when you choose.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(32).frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                }
            }
            .environment(cloud).tint(Theme.green)
            .task {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                let liveUI = arguments.contains("--social-live-ui")
                let local = liveUI || arguments.contains("--local-preview") || arguments.contains("--social-preview")
                // Live social UI tests use a synthetic library that is never mixed with personal wishes.
                let library: String? = liveUI ? "social-live-test" : nil
                #else
                let local = false
                let library: String? = nil
                #endif
                if !liveSocialCheck { await cloud.open(local: local, library: library) }
            }
        }
    }
}

enum LibraryArea: String, CaseIterable, Identifiable {
    case lists = "My Lists", circle = "Circle", activity = "Notifications", settings = "Settings"
    var id: String { rawValue }
    var icon: String { switch self { case .lists: "heart.text.clipboard"; case .circle: "person.2"; case .activity: "bell"; case .settings: "gearshape" } }
}

struct LibraryRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @Environment(CloudStore.self) private var cloud
    @Environment(\.scenePhase) private var phase
    @Query private var hidden: [HiddenPerson]
    @Query private var readState: [SocialReadState]
    @Query(sort: \WishList.createdAt) private var lists: [WishList]
    @State private var social = SocialStore.makeForApp()
    @State private var area: LibraryArea? = .lists
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(LibraryArea.allCases, selection: $area) { item in
                        NavigationLink(value: item) { Label(item.rawValue, systemImage: item.icon) }
                            .badge(item == .activity ? unreadCount : 0)
                            .accessibilityIdentifier("nav.\(item.rawValue)")
                    }
                        .navigationTitle("Wishwell")
                } detail: { section(area ?? .lists).id(area) }
            } else {
                TabView {
                    ForEach(LibraryArea.allCases) { item in section(item).tabItem { Label(item.rawValue, systemImage: item.icon) }.badge(item == .activity ? unreadCount : 0) }
                }
            }
        }
        .environment(social)
        .task {
            social.hidden = Set(hidden.map(\.ownerID))
            if cloud.localOnly && !social.isDemo && !social.isLiveTest { social.enabled = false }
            if social.enabled {
                do {
                    try await social.connect(); social.activityRows = try await social.activity()
                    if social.me != nil && !social.isLiveTest { await AlertPermission.registerIfAllowed() }
                }
                catch { social.error = error.localizedDescription }
            }
        }
        .onChange(of: hidden.map(\.ownerID)) { _, values in social.hidden = Set(values) }
        .task(id: publicationFingerprint) { await updatePublicCopies() }
        .onChange(of: phase) { _, value in if value == .active { Task {
            await updatePublicCopies()
            if social.enabled { do { social.activityRows = try await social.activity() } catch { social.publicationMessage = error.localizedDescription } }
        } } }
        .alert("Wishwell", isPresented: Binding(get: { social.error != nil }, set: { if !$0 { social.error = nil } })) { Button("OK") { social.error = nil } } message: { Text(social.error ?? "") }
    }
    private var unreadCount: Int {
        let read = Set(readState.map(\.id))
        return social.activityRows.filter { !read.contains($0.id) }.count
    }
    private func section(_ item: LibraryArea) -> some View {
        NavigationStack {
            switch item {
            case .lists: LibraryView()
            case .circle: CircleView()
            case .activity: ActivityView()
            case .settings: SettingsView()
            }
        }
    }
    private var publicationFingerprint: String {
        guard let me = social.me else { return "" }
        let snapshots = lists.filter { $0.publicRecordName != nil }.map { PublicList(list: $0, profile: me, id: $0.publicRecordName!) }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(snapshots)) ?? Data()
        return SHA256.hash(data: data).description
    }
    private func updatePublicCopies() async {
        guard social.enabled, let me = social.me else { return }
        do {
            try await Task.sleep(for: .milliseconds(700)); try Task.checkCancellation()
            for list in lists {
                guard let id = list.publicRecordName else { continue }
                guard try await social.publicList(id) != nil else {
                    list.publicRecordName = nil; try context.save(); continue
                }
                let snapshot = PublicList(list: list, profile: me, id: id)
                _ = try await social.publish(snapshot, existingID: id)
            }
            social.publicationMessage = nil
        } catch is CancellationError { }
        catch { social.publicationMessage = "Your personal changes are saved. Updating the public copy needs attention: \(error.localizedDescription)" }
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
