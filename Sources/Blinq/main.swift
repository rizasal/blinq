import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("workMin") var workMin = 20
    @AppStorage("breakSec") var breakSec = 20
    @AppStorage("idleMin") var idleMin = 5
    @AppStorage("skipMin") var skipMin = 10
    @AppStorage("snoozeMin") var snoozeMin = 5
    @State var login = Bundle.main.bundleIdentifier != nil && SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "eye.circle.fill").font(.system(size: 40)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blinq").font(.title2.weight(.semibold))
                        Text("A break every \(workMin) min, for \(dur(breakSec))").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
            Section("Breaks") {
                Row("timer", .teal, "Work interval", "\(workMin) min") { Stepper("", value: $workMin, in: 1...180).labelsHidden() }
                Row("hourglass", .indigo, "Break length", dur(breakSec)) { Stepper("", value: $breakSec, in: 5...600, step: 5).labelsHidden() }
            }
            Section("Reminders") { ForEach(NudgeKind.all, id: \.key) { NudgeSettings($0) } }
            Section("Sounds") { ForEach(Sounds.events, id: \.key) { SoundRow($0) } }
            Section("Snooze & skip") {
                Row("clock.arrow.circlepath", .orange, "Snooze length", "\(snoozeMin) min") { Stepper("", value: $snoozeMin, in: 1...60).labelsHidden() }
                Row("forward.end.fill", .pink, "Next break after skip", "\(skipMin) min") { Stepper("", value: $skipMin, in: 1...180).labelsHidden() }
            }
            Section {
                Row("moon.zzz.fill", .purple, "Reset after idle for", "\(idleMin) min") { Stepper("", value: $idleMin, in: 1...60).labelsHidden() }
                Row("power", .green, "Launch at login", nil) {
                    Toggle("", isOn: $login).toggleStyle(.switch).labelsHidden().disabled(Bundle.main.bundleIdentifier == nil)
                }
            } header: { Text("General") } footer: {
                Text("Breaks pause automatically during Meet, Slack and Teams calls.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .frame(height: min(760, (NSScreen.main?.visibleFrame.height ?? 800) - 80))  // scrolls on small screens
        .onChange(of: login) { _, on in
            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
            login = SMAppService.mainApp.status == .enabled
        }
    }
    func dur(_ s: Int) -> String { s >= 60 ? (s % 60 == 0 ? "\(s / 60) min" : "\(s / 60)m \(s % 60)s") : "\(s) sec" }
}

struct Row<C: View>: View {
    let icon: String, color: Color, title: String, value: String?
    @ViewBuilder let control: () -> C
    init(_ icon: String, _ color: Color, _ title: String, _ value: String?, @ViewBuilder control: @escaping () -> C) {
        self.icon = icon; self.color = color; self.title = title; self.value = value; self.control = control
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
            Spacer()
            if let value { Text(value).monospacedDigit().foregroundStyle(.secondary) }
            control()
        }
    }
}

private let scheduler = BreakScheduler()

/// Menu bar label: the only part that re-renders every second.
struct MenuLabel: View {
    @ObservedObject var s: BreakScheduler
    var icon: String {
        switch s.state {
        case .inCall: return "phone.fill"
        case .paused: return "pause.circle"
        case .onBreak: return "eye.slash"
        default: return "eye"
        }
    }
    var body: some View { HStack(spacing: 4) { Image(systemName: icon); Text(s.label).monospacedDigit() } }
}

/// Menu contents rebuild only when the state changes, so open submenus don't collapse on every tick.
struct MenuContent: View {
    let s: BreakScheduler
    @State private var state = BState.working
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Group {
            Text(state == .inCall ? "Paused for call" : state == .paused ? "Paused" : state == .onBreak ? "On a break" : "Working")
            Divider()
            Button("Take break now", systemImage: "cup.and.saucer") { s.startBreak() }
            if state == .paused { Button("Resume", systemImage: "play") { s.resume() } }
            else {
                Button("Pause for 30 min", systemImage: "pause") { s.pause(30) }
                Button("Pause for 1 hour", systemImage: "pause") { s.pause(60) }
            }
            Divider()
            Text(s.stats)
            Divider()
            Menu("Test", systemImage: "wrench.and.screwdriver") {
                Button("Break warning (10s)") { s.workSecs = s.interval - HeadsUp.lead; s.state = .working }
                Button("Full break") { s.startBreak() }
                ForEach(NudgeKind.all, id: \.key) { k in Button(k.name) { s.nudges.fire(k) } }
            }
            Divider()
            Button("Settings…", systemImage: "gearshape") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut(",")
            Button("Quit Blinq", systemImage: "power") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .onReceive(s.$state.removeDuplicates()) { state = $0 }
    }
}

struct BlinqApp: App {
    init() { NSApplication.shared.setActivationPolicy(.accessory) }
    var body: some Scene {
        MenuBarExtra { MenuContent(s: scheduler) } label: { MenuLabel(s: scheduler) }
        Window("Blinq Settings", id: "settings") { SettingsView() }.windowResizability(.contentSize)
    }
}
BlinqApp.main()
