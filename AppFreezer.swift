// AppFreezer: pause (SIGSTOP) and resume (SIGCONT) running apps,
// like `killall -STOP "App"` / `killall -CONT "App"`, but covering every
// process the app runs from inside its bundle (e.g. Chrome/Electron helpers).
import AppKit
import Combine
import Darwin
import SwiftUI

// MARK: - Process helpers

/// Reads the real process state from the kernel, so the UI stays correct
/// even if the app was stopped/continued from Terminal.
func isStopped(_ pid: pid_t) -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return false }
    return Int32(info.kp_proc.p_stat) == SSTOP
}

/// Executable path of every process we can see.
func allProcessPaths() -> [(pid: pid_t, path: String)] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
    let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard count > 0 else { return [] }
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    var result: [(pid: pid_t, path: String)] = []
    for pid in pids.prefix(Int(count)) where pid > 1 {
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            result.append((pid, String(cString: buffer)))
        }
    }
    return result
}

// MARK: - Appearance

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Model

struct AppRow: Identifiable {
    let id: pid_t            // main process
    let name: String
    let icon: NSImage?
    let menuIcon: NSImage?
    let pids: [pid_t]        // main process + helpers inside the bundle
    let paused: Bool
}

final class Model: ObservableObject {
    static let shared = Model()

    @Published var apps: [AppRow] = []
    @Published var error: String?
    @Published var search = ""
    @Published var hovered: pid_t?
    @Published var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }
    /// PIDs this app paused; resumed automatically when AppFreezer quits.
    private var pausedByUs = Set<pid_t>()
    private var timer: Timer?

    var pausedCount: Int { apps.filter(\.paused).count }

    init() {
        refresh()
        // .common mode keeps it ticking while the menu bar menu is open.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        let processes = allProcessPaths()
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .map { app in
                let pid = app.processIdentifier
                var pids = [pid]
                if let bundle = app.bundleURL?.resolvingSymlinksInPath().path {
                    let prefix = bundle + "/"
                    pids += processes.filter { $0.pid != pid && $0.pid != me && $0.path.hasPrefix(prefix) }
                        .map(\.pid)
                }
                let menuIcon = app.icon?.copy() as? NSImage
                menuIcon?.size = NSSize(width: 16, height: 16)
                return AppRow(id: pid,
                              name: app.localizedName ?? "pid \(pid)",
                              icon: app.icon,
                              menuIcon: menuIcon,
                              pids: pids,
                              paused: isStopped(pid))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let alive = Set(apps.flatMap(\.pids))
        pausedByUs.formIntersection(alive)
    }

    func setHover(_ id: pid_t, _ inside: Bool) {
        if inside { hovered = id } else if hovered == id { hovered = nil }
    }

    func toggle(_ app: AppRow) {
        app.paused ? resume(app) : pause(app)
        refresh()
    }

    func resumeAll() {
        for app in apps where app.paused { resume(app) }
        refresh()
    }

    /// Called on quit: never leave an app frozen after AppFreezer exits.
    func resumeOurs() {
        for pid in pausedByUs { kill(pid, SIGCONT) }
        pausedByUs.removeAll()
    }

    private func pause(_ app: AppRow) {
        // Helpers first, then the main process.
        for pid in app.pids.reversed() where kill(pid, SIGSTOP) == 0 {
            pausedByUs.insert(pid)
        }
        report(app, ok: isStopped(app.id))
    }

    private func resume(_ app: AppRow) {
        // Main process first, so the app is never waiting on a frozen parent.
        for pid in app.pids where kill(pid, SIGCONT) == 0 {
            pausedByUs.remove(pid)
        }
        report(app, ok: !isStopped(app.id))
    }

    private func report(_ app: AppRow, ok: Bool) {
        error = ok ? nil : "\(app.name): \(String(cString: strerror(errno)))"
    }
}

// MARK: - Main window

struct ContentView: View {
    @ObservedObject var model = Model.shared
    private var search: String { model.search }

    private var filtered: [AppRow] {
        search.isEmpty ? model.apps
            : model.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                CardsView(apps: filtered)
            }
            if let error = model.error {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .background(.background)
        .frame(minWidth: 560, minHeight: 480)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "snowflake")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AppFreezer").font(.title3.bold())
                    Text(model.pausedCount == 0
                         ? "\(model.apps.count) apps running"
                         : "\(model.pausedCount) of \(model.apps.count) apps frozen")
                        .font(.callout)
                        .foregroundStyle(model.pausedCount == 0 ? Color.secondary : Color.cyan)
                }
                Spacer()
                Menu {
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: model.appearance.icon)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Appearance: \(model.appearance.title)")
                Button {
                    model.resumeAll()
                } label: {
                    Label("Resume All", systemImage: "play.fill")
                }
                .controlSize(.large)
                .disabled(model.pausedCount == 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $model.search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
    }
}

// MARK: - Shared pieces

func processCount(_ app: AppRow) -> String {
    app.pids.count == 1 ? "1 process" : "\(app.pids.count) processes"
}

struct AppIconView: View {
    let app: AppRow
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
                    .saturation(app.paused ? 0 : 1)
                    .opacity(app.paused ? 0.55 : 1)
            }
            if app.paused {
                Image(systemName: "snowflake.circle.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white, .cyan)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

// MARK: - App grid: two columns of cards; clicking a card toggles it

struct CardsView: View {
    let apps: [AppRow]
    @ObservedObject var model = Model.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(apps) { AppCard(app: $0, hovered: model.hovered == $0.id) }
            }
            .padding(12)
        }
    }
}

struct AppCard: View {
    let app: AppRow
    let hovered: Bool

    var body: some View {
        Button {
            Model.shared.toggle(app)
        } label: {
            HStack(spacing: 10) {
                AppIconView(app: app, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(app.paused ? "Frozen · \(processCount(app))" : processCount(app))
                        .font(.caption)
                        .foregroundStyle(app.paused ? Color.cyan : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                glyph.font(.system(size: 20)).frame(width: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { Model.shared.setHover(app.id, $0) }
        .help(app.paused ? "Click to resume \(app.name)" : "Click to freeze \(app.name)")
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder private var glyph: some View {
        if hovered {
            Image(systemName: app.paused ? "play.circle.fill" : "pause.circle.fill")
                .foregroundStyle(.white, app.paused ? Color.green : Color.accentColor)
        } else if app.paused {
            Image(systemName: "snowflake").foregroundStyle(.cyan)
        } else {
            Color.clear
        }
    }

    private var fill: Color {
        app.paused ? .cyan.opacity(hovered ? 0.22 : 0.13) : .primary.opacity(hovered ? 0.09 : 0.04)
    }

    private var stroke: Color {
        if app.paused { return .cyan.opacity(0.5) }
        return hovered ? Color.accentColor.opacity(0.6) : .primary.opacity(0.06)
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @ObservedObject var model = Model.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.pausedCount == 0 ? "No apps frozen" : "\(model.pausedCount) frozen · click to toggle")
        ForEach(model.apps) { app in
            Toggle(isOn: Binding(get: { app.paused }, set: { _ in model.toggle(app) })) {
                if let icon = app.menuIcon {
                    Label { Text(app.name) } icon: { Image(nsImage: icon) }
                } else {
                    Text(app.name)
                }
            }
        }
        Divider()
        Button("Resume All") { model.resumeAll() }
            .disabled(model.pausedCount == 0)
        Button("Open AppFreezer…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit AppFreezer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { Model.shared.applyAppearance() }
    // Keep running in the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { Model.shared.resumeOurs() }
}

@main
struct AppFreezerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var model = Model.shared

    var body: some Scene {
        Window("AppFreezer", id: "main") { ContentView() }
            .defaultSize(width: 620, height: 620)
            .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: model.pausedCount == 0 ? "snowflake" : "snowflake.circle.fill")
        }
    }
}
