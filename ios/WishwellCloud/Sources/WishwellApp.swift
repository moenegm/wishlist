import SwiftUI
import UserNotifications
import SwiftData
import CryptoKit
import BackgroundTasks

/// Receives the push token CloudKit needs for follow, like and comment alerts.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    /// Shows alerts while the app is open too, so a follow, like or comment is never silently dropped.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        #if DEBUG
        print("Wishwell alerts: received \(notification.request.content.body)")
        #endif
        return [.banner, .list, .sound]
    }
    /// Tapping a Wishwell banner opens the app on its Notifications tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationCenter.default.post(name: .openWishwellNotifications, object: nil) }
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await PushService.save(token: token) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Wishwell alerts: push registration failed: \(error)")
    }
}

/// Connects this phone to the website, which sends Wishwell's notifications through Apple.
/// The website checks every reported record in iCloud and writes the message itself.
@MainActor enum PushService {
    private static let base = URL(string: "https://nujoomdigital.com/wishwell/push")!
    private static let tokenKey = "WishwellPushToken", userKey = "WishwellPushUser"
    /// Xcode builds use Apple's sandbox and iCloud's development data; App Store builds use production for both.
    static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
    static var registered: Bool { UserDefaults.standard.string(forKey: tokenKey) != nil }
    static func save(token: String) async {
        UserDefaults.standard.set(token, forKey: tokenKey)
        if let user = UserDefaults.standard.string(forKey: userKey) { await register(user: user) }
    }
    /// Called once the public account is known; does nothing until the phone has a push token.
    static func register(user: String) async {
        UserDefaults.standard.set(user, forKey: userKey)
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        await send("devices", method: "POST", ["token": token, "user": user, "environment": environment])
    }
    /// Keeps the number the website puts on the app icon in step with what's unread in the app.
    static func updateBadge(_ unread: Int) async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey), let user = UserDefaults.standard.string(forKey: userKey) else { return }
        await send("devices", method: "POST", ["token": token, "user": user, "environment": environment, "unread": String(unread)])
    }
    /// When the public account is turned off, this phone stops getting notifications.
    static func unregister() async {
        UserDefaults.standard.removeObject(forKey: userKey)
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        await send("devices", method: "DELETE", ["token": token])
    }
    /// Called just before wishes leave a shared list (deleted, or the whole list deleted) or after one is marked
    /// fulfilled, while the website can still see who was getting them. It tells them once the change is confirmed.
    static func reportRemoval(list: String, wishes: [UUID]) async {
        guard !wishes.isEmpty else { return }
        var request = URLRequest(url: base.appending(path: "removals"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["list": list, "environment": environment, "wishes": wishes.map(\.uuidString)])
        request.timeoutInterval = 10
        do { _ = try await URLSession.shared.data(for: request) } catch { print("Wishwell push removals failed: \(error.localizedDescription)") }
    }
    static func report(record: String, profile: String?) async {
        var body = ["record": record, "environment": environment]
        if let profile { body["profile"] = profile }
        await send("events", method: "POST", body)
    }
    private static func send(_ path: String, method: String, _ body: [String: String]) async {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            #if DEBUG
            print("Wishwell push \(path): \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            #endif
        } catch { print("Wishwell push \(path) failed: \(error.localizedDescription)") }
    }
}

/// Checks for new follows, likes and comments while Wishwell is closed, using iOS background refresh,
/// and shows them as banners with a count on the app icon. iOS decides when this runs, so alerts can be
/// minutes or hours late; it's a backup for iCloud's own push alerts.
@MainActor enum BackgroundActivity {
    static let taskID = "com.nujoomdigital.wishwell.activity"
    private static let knownKey = "WishwellKnownActivity", badgeKey = "WishwellBadge"
    private static let enabledKey = "WishwellBackgroundActivity", hiddenKey = "WishwellHiddenPeople"
    static func schedule() {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) } catch { print("Wishwell background check not scheduled: \(error)") }
    }
    /// Called with what the app is showing, so nothing already seen comes back as a banner.
    static func remember(_ rows: [SocialActivity], unread: Int, hidden: Set<String>, publicAccount: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(publicAccount, forKey: enabledKey)
        defaults.set(Array(hidden), forKey: hiddenKey)
        defaults.set(unread, forKey: badgeKey)
        known(adding: rows.map(\.id))
    }
    /// IDs already shown in the app or as a banner, newest last.
    @discardableResult private static func known(adding ids: [String] = []) -> Set<String> {
        var list = UserDefaults.standard.stringArray(forKey: knownKey) ?? []
        let existing = Set(list)
        list += ids.filter { !existing.contains($0) }
        list = Array(list.suffix(500))
        UserDefaults.standard.set(list, forKey: knownKey)
        return Set(list)
    }
    static func check() async {
        schedule()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let social = SocialStore()
        guard social.enabled else { return }
        social.hidden = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
        do {
            try await social.connect()
            guard social.me != nil else { return }
            let seen = known()
            let fresh = try await social.activity().filter { !seen.contains($0.id) }
            guard !fresh.isEmpty else { return }
            // Once the website sends notifications, this check only keeps the app icon's count current.
            for row in fresh.prefix(5) where !PushService.registered {
                let content = UNMutableNotificationContent()
                content.body = row.message; content.sound = .default
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ww-activity-\(row.id)", content: content, trigger: nil))
            }
            known(adding: fresh.map(\.id))
            let badge = defaults.integer(forKey: badgeKey) + fresh.count
            defaults.set(badge, forKey: badgeKey)
            try? await UNUserNotificationCenter.current().setBadgeCount(badge)
        } catch { print("Wishwell background check failed: \(error)") }
    }
}

extension Notification.Name {
    static let openWishwellNotifications = Notification.Name("WishwellOpenNotifications")
}

@main struct WishwellCloudApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var cloud = CloudStore()
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
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
            .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
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
        .backgroundTask(.appRefresh(BackgroundActivity.taskID)) { await BackgroundActivity.check() }
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
                TabView(selection: $area) {
                    ForEach(LibraryArea.allCases) { item in section(item).tabItem { Label(item.rawValue, systemImage: item.icon) }.badge(item == .activity ? unreadCount : 0).tag(Optional(item)) }
                }
            }
        }
        .environment(social)
        .task {
            social.hidden = Set(hidden.map(\.ownerID))
            if cloud.localOnly && !social.isDemo && !social.isLiveTest { social.enabled = false }
            if social.enabled {
                do {
                    if !social.isDemo { social.didSave = { record, profile in await PushService.report(record: record, profile: profile) } }
                    await showDeliveredNotifications()
                    try await social.connect()
                    Task { await social.warmCircle() }
                    if social.me != nil, let user = social.actorID {
                        await PushService.register(user: user)
                        // The icon may still show notifications already read on another device.
                        await PushService.updateBadge(unreadCount)
                    }
                    social.activityRows = try await social.activity()
                    if social.me != nil && AlertPermission.allowed(for: social) { await AlertPermission.registerIfAllowed() }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--dump-social") { await dumpSocial() }
                    #endif
                }
                catch { social.error = error.localizedDescription }
            }
        }
        .onChange(of: hidden.map(\.ownerID)) { _, values in social.hidden = Set(values) }
        .onReceive(NotificationCenter.default.publisher(for: .openWishwellNotifications)) { _ in area = .activity }
        // New follows, likes and comments show up while the app is open, not only when it comes back to the front.
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, social.enabled, social.me != nil, !social.busy else { continue }
                if let rows = try? await social.activity() { social.activityRows = rows }
            }
        }
        .onChange(of: unreadCount) { _, count in
            UNUserNotificationCenter.current().setBadgeCount(count)
            Task { await PushService.updateBadge(count) }
        }
        .onChange(of: social.activityRows.map(\.id)) { _, _ in
            #if DEBUG
            // --check-activity runs the background check in the foreground, so what's on screen mustn't count as seen first.
            if ProcessInfo.processInfo.arguments.contains("--check-activity") { return }
            #endif
            BackgroundActivity.remember(social.activityRows, unread: unreadCount, hidden: social.hidden, publicAccount: social.me != nil)
        }
        .onChange(of: social.me?.id) { _, _ in BackgroundActivity.remember(social.activityRows, unread: unreadCount, hidden: social.hidden, publicAccount: social.me != nil) }
        .onChange(of: phase) { _, value in if value == .background { BackgroundActivity.schedule() } }
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("--check-activity") { try? await Task.sleep(for: .seconds(3)); await BackgroundActivity.check() } }
        #endif
        .task(id: publicationFingerprint) { await updatePublicCopies() }
        .onChange(of: phase) { _, value in if value == .active { Task {
            await showDeliveredNotifications()
            await updatePublicCopies()
            if social.enabled { do { social.activityRows = try await social.activity() } catch { social.publicationMessage = error.localizedDescription } }
        } } }
        .alert("Wishwell", isPresented: Binding(get: { social.error != nil }, set: { if !$0 { social.error = nil } })) { Button("OK") { social.error = nil } } message: { Text(social.error ?? "") }
    }
    #if DEBUG
    /// Development only: prints what iCloud holds for this person's lists, to compare with what the screens show.
    private func dumpSocial() async {
        func line(_ text: String) { print("WISHWELL_DUMP: \(text)") }
        line("me=\(social.me?.name ?? "none") actor=\(social.actorID ?? "?")")
        for list in lists {
            let record: String?
            if let id = list.publicRecordName { record = id } else { record = try? await social.ownListRecord(source: list.id)?.id }
            line("list '\(list.title)' local=\(list.id) record=\(record ?? "none") public=\(list.publicRecordName != nil)")
            guard let record else { continue }
            do {
                let claims = try await social.claims(listID: record)
                for wish in list.sortedWishes { line("  wish '\(wish.title)' \(wish.id): claim=\(claims[wish.id].map { "\($0)" } ?? "none")") }
            } catch { line("  error: \(error)") }
        }
        line("activity: \(social.activityRows.map(\.message))")
        line("done")
    }
    #endif
    private var unreadCount: Int {
        let read = Set(readState.map(\.id))
        return (social.deliveredRows + social.activityRows).filter { !read.contains($0.id) }.count
    }
    /// Notifications that already arrived as banners, so the Notifications screen shows them the moment it opens.
    private func showDeliveredNotifications() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let known = Set(social.activityRows.map(\.message))
        social.deliveredRows = delivered.compactMap { notification in
            let body = notification.request.content.body
            guard !body.isEmpty, !known.contains(body) else { return nil }
            // The website says which wish or person each notification is about, so this copy opens it straight away.
            let link = notification.request.content.userInfo["wishwell"] as? [String: Any]
            var row = SocialActivity(id: "banner-\(notification.request.identifier)", actor: nil, message: body, date: notification.date, icon: "bell.fill")
            row.linkListID = link?["list"] as? String
            row.wishID = (link?["wish"] as? String).flatMap(UUID.init(uuidString:))
            row.linkProfileID = link?["profile"] as? String
            return row
        }
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
