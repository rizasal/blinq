import SwiftUI
import AppKit

// Lightweight reminders (no blackout): a toast at the top of the screen.
struct NudgeKind {
    let key: String, name: String, icon: String, color: Color, defaultMin: Int, messages: [String]
    static let all = [
        NudgeKind(key: "posture", name: "Sit up straight", icon: "figure.stand", color: .orange, defaultMin: 15, messages: [
            "Sit up straight — shoulders back, chin level",
            "Check your posture: feet flat, back supported",
            "Unclench your jaw and drop your shoulders",
            "Straighten up — screen at eye level",
        ]),
        NudgeKind(key: "blink", name: "Blink your eyes", icon: "eye", color: .cyan, defaultMin: 10, messages: [
            "Blink slowly 10 times",
            "Close your eyes for a moment",
            "Blink — your eyes will thank you",
            "Soft blinks: close, squeeze gently, open",
        ]),
    ]
    var d: UserDefaults { .standard }
    var on: Bool { d.object(forKey: key + "On") as? Bool ?? true }
    var minutes: Int { let m = d.integer(forKey: key + "Min"); return m > 0 ? m : defaultMin }
    var message: String {
        let custom = (d.string(forKey: key + "Msg") ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? messages.randomElement()! : custom
    }
}

final class Nudges {
    private var secs: [String: Int] = [:]
    private let toast = Toast()
    /// Called once per active-work second.
    func tick() {
        for k in NudgeKind.all where k.on {
            let n = (secs[k.key] ?? 0) + 1
            if n >= k.minutes * 60, !toast.visible { secs[k.key] = 0; toast.show(k) } else { secs[k.key] = n }
        }
    }
    func fire(_ k: NudgeKind) { secs[k.key] = 0; toast.hide(); toast.show(k) }
    func reset() { secs = [:] }
    func left(_ k: NudgeKind) -> Int { max(0, k.minutes * 60 - (secs[k.key] ?? 0)) }
}

final class Toast {
    private let bar = TopBar()
    private var gen = 0
    var visible: Bool { bar.visible }
    func show(_ k: NudgeKind) {
        let msg = k.message
        Sounds.play(k.key)
        bar.show(size: NSSize(width: 484, height: 84)) { ToastView(kind: k, message: msg) { [weak self] in self?.hide() } }
        gen += 1; let g = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in if self?.gen == g { self?.hide() } }
    }
    func hide() { bar.hide() }
}

struct ToastView: View {
    let kind: NudgeKind, message: String, dismiss: () -> Void
    @State private var bounce = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.icon).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white).frame(width: 38, height: 38).background(kind.color.opacity(0.85).gradient, in: Circle())
                .scaleEffect(bounce ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.name).font(.system(size: 12, weight: .semibold)).opacity(0.65).textCase(.uppercase)
                Text(message).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
            }
            Spacer(minLength: 0)
            BarButton(title: "Skip", filled: false, action: dismiss)
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(width: 460, height: 60)
        .background {
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .light)
            Capsule().fill(.white.opacity(0.7))
        }
        .overlay(Capsule().stroke(.black.opacity(0.06)))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 4)
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true)) { bounce = true } }
    }
}

struct NudgeSettings: View {
    let kind: NudgeKind
    @AppStorage var on: Bool
    @AppStorage var minutes: Int
    @AppStorage var msg: String
    init(_ k: NudgeKind) {
        kind = k
        _on = AppStorage(wrappedValue: true, k.key + "On")
        _minutes = AppStorage(wrappedValue: k.defaultMin, k.key + "Min")
        _msg = AppStorage(wrappedValue: "", k.key + "Msg")
    }
    var body: some View {
        Row(kind.icon, kind.color, kind.name, nil) { Toggle("", isOn: $on).toggleStyle(.switch).labelsHidden() }
        if on {
            Row("repeat", kind.color.opacity(0.6), "Every", "\(minutes) min") { Stepper("", value: $minutes, in: 1...120).labelsHidden() }
            TextField("Message", text: $msg, prompt: Text("Custom message (blank = rotating tips)"))
        }
    }
}
