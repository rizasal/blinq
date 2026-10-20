import SwiftUI
import AppKit

private let tips = [
    ("eye", "Look at something 20 feet away"),
    ("wind", "Take a slow, deep breath"),
    ("figure.cooldown", "Roll your shoulders and stretch"),
    ("drop", "Have a sip of water"),
    ("eyes", "Blink slowly a few times"),
    ("figure.walk", "Stand up and move around"),
]

extension NSWindow {
    func fade(to a: CGFloat, _ done: (() -> Void)? = nil) {
        if a == 0 { ignoresMouseEvents = true }  // don't swallow clicks while fading out
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; animator().alphaValue = a }, completionHandler: done)
    }
}

// MARK: Break overlay

final class KeyWindow: NSWindow {
    var onEsc: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEsc?() }
}

final class Overlay {
    var windows: [NSWindow] = []
    func show(_ s: BreakScheduler) {
        close()
        let tip = tips.randomElement()!
        for sc in NSScreen.screens {
            let w = KeyWindow(contentRect: sc.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isOpaque = false; w.backgroundColor = .clear; w.isReleasedWhenClosed = false
            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI; blur.blendingMode = .behindWindow; blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: OverlayView(s: s, tip: tip))
            host.frame = blur.bounds; host.autoresizingMask = [.width, .height]
            blur.addSubview(host)
            w.contentView = blur
            w.setFrame(sc.frame, display: true)
            w.onEsc = { [weak s] in s?.skip() }
            w.alphaValue = 0; w.orderFrontRegardless(); w.fade(to: 1)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }
    func close() {
        let ws = windows; windows = []
        guard !ws.isEmpty else { return }
        ws.forEach { w in w.fade(to: 0) { w.orderOut(nil) } }
        NSApp.hide(nil)  // hand focus back to the previous app
    }
}

struct OverlayView: View {
    @ObservedObject var s: BreakScheduler
    let tip: (String, String)
    @State private var appear = false
    var progress: Double { s.breakSec > 0 ? Double(max(0, s.breakLeft)) / Double(s.breakSec) : 0 }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.teal.opacity(0.35), Color.indigo.opacity(0.25), .black.opacity(0.55)],
                           center: .center, startRadius: 50, endRadius: 900).ignoresSafeArea()
            VStack(spacing: 36) {
                VStack(spacing: 10) {
                    Image(systemName: tip.0).font(.system(size: 44, weight: .light)).symbolRenderingMode(.hierarchical)
                    Text("Time to look away").font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text(tip.1).font(.title2).foregroundStyle(.secondary)
                }
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 10)
                    Circle().trim(from: 0, to: progress)
                        .stroke(AngularGradient(colors: [.teal, .mint, .teal], center: .center),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    Text(fmt(max(0, s.breakLeft)))
                        .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: s.breakLeft)
                }.frame(width: 220, height: 220)
                HStack(spacing: 14) {
                    PillButton(title: "Snooze \(s.snoozeMin) min", icon: "clock.arrow.circlepath") { s.snooze() }
                    PillButton(title: "Skip", icon: "forward.end", hint: "esc") { s.skip() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .foregroundStyle(.white)
            .scaleEffect(appear ? 1 : 0.94).opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.6)) { appear = true } }
    }
    func fmt(_ t: Int) -> String { t >= 60 ? String(format: "%d:%02d", t / 60, t % 60) : "\(t)" }
}

struct PillButton: View {
    let title: String, icon: String
    var hint: String? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                if let hint { Text(hint).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4)) }
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 20).padding(.vertical, 11)
            .background(.white.opacity(hover ? 0.22 : 0.12), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

// MARK: Heads-up bar

/// A pill-shaped bar that slides in at the top centre of every screen.
final class TopBar {
    private var panels: [NSPanel] = []
    var visible: Bool { !panels.isEmpty }
    func show<V: View>(size: NSSize, _ view: @escaping () -> V) {
        hide()
        for sc in NSScreen.screens {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.level = .statusBar; p.isFloatingPanel = true; p.hasShadow = false
            p.isOpaque = false; p.backgroundColor = .clear
            p.isReleasedWhenClosed = false; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: view()); host.sizingOptions = []; p.contentView = host
            let f = sc.visibleFrame
            let end = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 10, width: size.width, height: size.height)
            p.setFrame(end.offsetBy(dx: 0, dy: size.height + 30), display: false); p.alphaValue = 0
            p.orderFrontRegardless(); panels.append(p)
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.45; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                p.animator().setFrame(end, display: true); p.animator().alphaValue = 1
            }
        }
    }
    func hide() {
        let ps = panels; panels = []
        ps.forEach { p in p.fade(to: 0) { p.orderOut(nil) } }
    }
}

final class HeadsUp {
    static let lead = 10  // seconds before a break
    private let bar = TopBar()
    var visible: Bool { bar.visible }
    func show(_ s: BreakScheduler) { Sounds.play("warn"); bar.show(size: NSSize(width: 744, height: 100)) { HeadsUpView(s: s) } }
    func hide() { bar.hide() }
}

struct HeadsUpView: View {
    @ObservedObject var s: BreakScheduler
    @State private var pulse = false
    var left: Int { max(0, s.interval - s.workSecs) }
    var progress: Double { Double(left) / Double(HeadsUp.lead) }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.black.opacity(0.08), lineWidth: 4)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text("\(left)").font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true)).animation(.default, value: left)
            }
            .frame(width: 44, height: 44)
            .scaleEffect(pulse ? 1.06 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time to rest your eyes").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("Your break starts in \(left) second\(left == 1 ? "" : "s")").font(.system(size: 13)).opacity(0.75)
            }
            Spacer()
            BarButton(title: "Skip", filled: false) { s.skip() }
            BarButton(title: "Snooze \(s.snoozeMin)m", filled: false) { s.snooze() }
            BarButton(title: "Start now", filled: true) { s.startBreak() }
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, 18)
        .frame(width: 720, height: 76)
        .background {
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .light)
            Capsule().fill(.white.opacity(0.7))
        }
        .overlay(Capsule().stroke(.black.opacity(0.06), lineWidth: 1))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 4)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
    }
}

struct BarButton: View {
    let title: String, filled: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(filled ? AnyShapeStyle(Color.teal.opacity(hover ? 1 : 0.85)) : AnyShapeStyle(Color.black.opacity(hover ? 0.12 : 0.06)), in: Capsule())
                .foregroundStyle(filled ? .white : .black.opacity(0.8))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
