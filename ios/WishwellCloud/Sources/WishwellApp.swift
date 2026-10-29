import SwiftUI
import SwiftData

@main struct WishwellCloudApp: App {
    @State private var cloud = CloudStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = cloud.container {
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
                let local = ProcessInfo.processInfo.arguments.contains("--local-preview")
                #else
                let local = false
                #endif
                await cloud.open(local: local)
            }
        }
    }
}

enum LibraryArea: String, CaseIterable, Identifiable {
    case lists = "My Lists", circle = "Circle", settings = "Settings"
    var id: String { rawValue }
    var icon: String { switch self { case .lists: "heart.text.clipboard"; case .circle: "person.2"; case .settings: "gearshape" } }
}

struct LibraryRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var area: LibraryArea? = .lists
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(LibraryArea.allCases, selection: $area) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }
                        .navigationTitle("Wishwell")
                } detail: { section(area ?? .lists).id(area) }
            } else {
                TabView {
                    ForEach(LibraryArea.allCases) { item in section(item).tabItem { Label(item.rawValue, systemImage: item.icon) } }
                }
            }
        }
    }
    private func section(_ item: LibraryArea) -> some View {
        NavigationStack {
            switch item {
            case .lists: LibraryView()
            case .circle: CircleSetupView()
            case .settings: SettingsView()
            }
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
