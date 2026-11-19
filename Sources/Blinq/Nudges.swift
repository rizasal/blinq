import SwiftUI
import AppKit

// Lightweight reminders (no blackout): a toast at the top of the screen.
struct NudgeKind {
    let key: String, name: String, icon: String, color: Color, defaultMin: Int, doneLabel: String, messages: [String]
    static let all = [
        NudgeKind(key: "posture", name: "Sit up straight", icon: "figure.stand", color: Palette.apricot, defaultMin: 15, doneLabel: "Sitting tall", messages: [
            "Sit up straight — shoulders back, chin level",
            "Check your posture: feet flat, back supported",
            "Unclench your jaw and drop your shoulders",
            "Straighten up — screen at eye level",
        ]),
        NudgeKind(key: "blink", name: "Blink your eyes", icon: "eye", color: Palette.sky, defaultMin: 10, doneLabel: "Blinked", messages: [
            "Blink slowly 10 times",
            "Close your eyes for a moment",
            "Blink — your eyes will thank you",
            "Soft blinks: close, squeeze gently, open",
        ]),
    ]
    var d: UserDefaults { .standard }
    /// Nudges acted on today (reset by BreakScheduler.rollDay).
    static func markDone(_ key: String) { let d = UserDefaults.standard; d.set(d.integer(forKey: "done_" + key) + 1, forKey: "done_" + key) }
    static var doneToday: Int { all.reduce(0) { $0 + UserDefaults.standard.integer(forKey: "done_" + $1.key) } }
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
        case .bar: bar.show(size: NSSize(width: 544, height: 88)) { ToastView(kind: k, message: msg, secs: secs, dismiss: close) }
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

/// Line that drains over the nudge's on-screen time.
struct DrainBar: View {
    let secs: Int, color: Color
    @State private var p = 1.0
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.primary.opacity(0.07)).overlay(alignment: .leading) {
                Capsule().fill(color.opacity(0.8)).frame(width: g.size.width * p)
            }
        }
        .frame(height: 3)
        .onAppear { withAnimation(.linear(duration: Double(secs))) { p = 0 } }
    }
}

/// Animated glyph: an eye that blinks, or a figure that straightens up.
struct NudgeIcon: View {
    let kind: NudgeKind, size: CGFloat
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(kind.color.gradient)
                if kind.key == "blink" {
                    Eye(open: blinkOpen(t), color: .white, pupil: .white.opacity(0.35)).frame(width: size * 0.56, height: size * 0.32)
                } else {
                    let c = t.truncatingRemainder(dividingBy: 3.2)
                    let tilt = c < 1 ? -14 * (1 - c) : c > 2.6 ? -14 * (c - 2.6) / 0.6 : 0
                    Image(systemName: kind.icon).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
                        .rotationEffect(.degrees(tilt), anchor: .bottom)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: kind.color.opacity(0.35), radius: size / 8, y: size / 16)
        }
    }
}

/// "Done" is the main action and counts toward today's stats; × just dismisses.
struct NudgeActions: View {
    let kind: NudgeKind, dismiss: () -> Void
    var large = false
    @State private var done = false
    var body: some View {
        HStack(spacing: 8) {
            if done {
                Label("Nice", systemImage: "checkmark.circle.fill")
                    .font(.system(size: large ? 17 : 13, weight: .semibold))
                    .foregroundStyle(large ? .white : kind.color)
                    .padding(.horizontal, large ? 22 : 14).padding(.vertical, large ? 12 : 8)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if large {
                GhostButton(title: "Not now", icon: "xmark", action: dismiss)
                Button(action: finish) {
                    Label(kind.doneLabel, systemImage: "checkmark").font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Palette.paper, in: Capsule()).foregroundStyle(Palette.ink)
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            } else {
                BarButton(title: kind.doneLabel, icon: "checkmark", tint: kind.color, filled: true, action: finish)
                CloseButton(help: "Dismiss", action: dismiss)
            }
        }
        .animation(.spring(duration: 0.35), value: done)
    }
    func finish() {
        guard !done else { return }
        NudgeKind.markDone(kind.key); done = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }
}

struct NudgeCardView: View {
    let kind: NudgeKind, message: String, secs: Int, dismiss: () -> Void
    @State private var appear = false
    var body: some View {
        VStack(spacing: 18) {
            NudgeIcon(kind: kind, size: 76)
            VStack(spacing: 6) {
                Text(kind.name).font(.system(size: 12, weight: .semibold)).tracking(1).textCase(.uppercase).opacity(0.5)
                Text(message).font(.system(size: 20, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NudgeActions(kind: kind, dismiss: dismiss).frame(height: 34)
            DrainBar(secs: secs, color: kind.color).padding(.horizontal, 40)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 22)
        .frame(width: 400)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial).environment(\.colorScheme, .light)
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.paper.opacity(0.8))
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
    var body: some View {
        ZStack {
            RadialGradient(colors: [kind.color.opacity(0.3), Palette.night.opacity(0.7)], center: .center, startRadius: 40, endRadius: 900).ignoresSafeArea()
            VStack(spacing: 30) {
                NudgeIcon(kind: kind, size: 150)
                VStack(spacing: 10) {
                    Text(kind.name).font(.system(size: 14, weight: .semibold)).tracking(2).textCase(.uppercase).opacity(0.6)
                    Text(message).font(.system(size: 40, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                }
                NudgeActions(kind: kind, dismiss: dismiss, large: true).frame(height: 48)
                DrainBar(secs: secs, color: .white).frame(width: 280)
            }
            .foregroundStyle(.white)
            .scaleEffect(appear ? 1 : 0.94).opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.6)) { appear = true } }
    }
}

struct ToastView: View {
    let kind: NudgeKind, message: String, secs: Int, dismiss: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            NudgeIcon(kind: kind, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.name).font(.system(size: 11, weight: .semibold)).tracking(0.5).opacity(0.5).textCase(.uppercase)
                Text(message).font(.system(size: 14, weight: .medium, design: .rounded)).lineLimit(1)
                DrainBar(secs: secs, color: kind.color).frame(width: 180).padding(.top, 4)
            }
            Spacer(minLength: 6)
            NudgeActions(kind: kind, dismiss: dismiss)
        }
        .foregroundStyle(Palette.ink)
        .padding(.leading, 12).padding(.trailing, 14)
        .frame(width: 520, height: 64)
        .background(GlassCapsule())
        .padding(.bottom, 4)
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
