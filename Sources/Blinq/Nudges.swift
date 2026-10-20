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
    var style: NudgeStyle { NudgeStyle(rawValue: d.string(forKey: key + "Style") ?? "") ?? .bar }
    var seconds: Int { let s = d.integer(forKey: key + "Secs"); return s > 0 ? s : 6 }
    var message: String {
        let custom = (d.string(forKey: key + "Msg") ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? messages.randomElement()! : custom
    }
}

enum NudgeStyle: String, CaseIterable {
    case bar = "Bar", card = "Card", full = "Full screen"
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
    private let panels = ScreenPanels()
    private var gen = 0
    var visible: Bool { bar.visible || panels.visible }
    func show(_ k: NudgeKind) {
        hide()
        let msg = k.message, secs = k.seconds
        let close: () -> Void = { [weak self] in self?.hide() }
        Sounds.play(k.key)
        switch k.style {
        case .bar: bar.show(size: NSSize(width: 484, height: 84)) { ToastView(kind: k, message: msg, secs: secs, dismiss: close) }
        case .card: panels.show(full: false) { NudgeCardView(kind: k, message: msg, secs: secs, dismiss: close) }
        case .full: panels.show(full: true) { NudgeFullView(kind: k, message: msg, secs: secs, dismiss: close) }
        }
        gen += 1; let g = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(secs)) { [weak self] in if self?.gen == g { self?.hide() } }
    }
    func hide() { bar.hide(); panels.hide() }
}

/// Centred card or full-screen panels on every screen. Non-activating, so typing isn't interrupted.
final class ScreenPanels {
    private var panels: [NSPanel] = []
    var visible: Bool { !panels.isEmpty }
    func show<V: View>(full: Bool, _ view: @escaping () -> V) {
        hide()
        for sc in NSScreen.screens {
            let size = full ? sc.frame.size : NSSize(width: 460, height: 320)
            let f = full ? sc.frame : NSRect(x: sc.visibleFrame.midX - size.width / 2, y: sc.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
            let p = NSPanel(contentRect: f, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.level = full ? .screenSaver : .statusBar; p.hasShadow = false
            p.isOpaque = false; p.backgroundColor = .clear
            p.isReleasedWhenClosed = false; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: view()); host.sizingOptions = []
            if full {
                let blur = NSVisualEffectView(); blur.material = .hudWindow; blur.blendingMode = .behindWindow; blur.state = .active
                host.frame = blur.bounds; host.autoresizingMask = [.width, .height]; blur.addSubview(host)
                p.contentView = blur
            } else { p.contentView = host }
            p.setFrame(f, display: false); p.alphaValue = 0
            p.orderFrontRegardless(); p.fade(to: 1); panels.append(p)
        }
    }
    func hide() {
        let ps = panels; panels = []
        ps.forEach { p in p.fade(to: 0) { p.orderOut(nil) } }
    }
}

/// Bar that drains over the nudge's on-screen time.
struct DrainBar: View {
    let secs: Int, color: Color
    @State private var p = 1.0
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.primary.opacity(0.08)).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: g.size.width * p)
            }
        }
        .frame(height: 4)
        .onAppear { withAnimation(.linear(duration: Double(secs))) { p = 0 } }
    }
}

struct NudgeCardView: View {
    let kind: NudgeKind, message: String, secs: Int, dismiss: () -> Void
    @State private var appear = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: kind.icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 72, height: 72).background(kind.color.gradient, in: Circle())
                .shadow(color: kind.color.opacity(0.4), radius: 10, y: 4)
            VStack(spacing: 6) {
                Text(kind.name).font(.system(size: 13, weight: .semibold)).textCase(.uppercase).opacity(0.55)
                Text(message).font(.system(size: 20, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DrainBar(secs: secs, color: kind.color).padding(.horizontal, 30)
            BarButton(title: "Skip", filled: false, action: dismiss)
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(26)
        .frame(width: 420)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial).environment(\.colorScheme, .light)
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white.opacity(0.7))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .scaleEffect(appear ? 1 : 0.9).opacity(appear ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.spring(duration: 0.45)) { appear = true } }
    }
}

struct NudgeFullView: View {
    let kind: NudgeKind, message: String, secs: Int, dismiss: () -> Void
    @State private var appear = false
    @State private var breathe = false
    var body: some View {
        ZStack {
            RadialGradient(colors: [kind.color.opacity(0.35), .black.opacity(0.35)], center: .center, startRadius: 40, endRadius: 900).ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: kind.icon).font(.system(size: 64, weight: .light))
                    .frame(width: 150, height: 150)
                    .background(Circle().fill(kind.color.opacity(0.3)))
                    .scaleEffect(breathe ? 1.08 : 0.96)
                VStack(spacing: 10) {
                    Text(kind.name).font(.system(size: 16, weight: .semibold)).textCase(.uppercase).opacity(0.7)
                    Text(message).font(.system(size: 40, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                }
                DrainBar(secs: secs, color: .white).frame(width: 320)
                PillButton(title: "Skip", icon: "forward.end", action: dismiss)
            }
            .foregroundStyle(.white)
            .scaleEffect(appear ? 1 : 0.94).opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6)) { appear = true }
            withAnimation(.easeInOut(duration: 2).repeatForever()) { breathe = true }
        }
    }
}

struct ToastView: View {
    let kind: NudgeKind, message: String, secs: Int, dismiss: () -> Void
    @State private var bounce = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.icon).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white).frame(width: 38, height: 38).background(kind.color.opacity(0.85).gradient, in: Circle())
                .scaleEffect(bounce ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.name).font(.system(size: 12, weight: .semibold)).opacity(0.65).textCase(.uppercase)
                Text(message).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                DrainBar(secs: secs, color: kind.color).frame(width: 220).padding(.top, 4)
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
    @AppStorage var style: String
    @AppStorage var secs: Int
    init(_ k: NudgeKind) {
        kind = k
        _on = AppStorage(wrappedValue: true, k.key + "On")
        _minutes = AppStorage(wrappedValue: k.defaultMin, k.key + "Min")
        _msg = AppStorage(wrappedValue: "", k.key + "Msg")
        _style = AppStorage(wrappedValue: NudgeStyle.bar.rawValue, k.key + "Style")
        _secs = AppStorage(wrappedValue: 6, k.key + "Secs")
    }
    var body: some View {
        Row(kind.icon, kind.color, kind.name, nil) { Toggle("", isOn: $on).toggleStyle(.switch).labelsHidden() }
        if on {
            Row("repeat", kind.color.opacity(0.6), "Every", "\(minutes) min") { Stepper("", value: $minutes, in: 1...120).labelsHidden() }
            Row("rectangle.on.rectangle", kind.color.opacity(0.6), "Style", nil) {
                Picker("", selection: $style) { ForEach(NudgeStyle.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
            Row("timer", kind.color.opacity(0.6), "On screen for", "\(secs) sec") { Stepper("", value: $secs, in: 2...60).labelsHidden() }
            TextField("Message", text: $msg, prompt: Text("Custom message (blank = rotating tips)"))
        }
    }
}
