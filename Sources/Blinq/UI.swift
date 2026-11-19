import SwiftUI
import AppKit

extension NSWindow {
    func fade(to a: CGFloat, _ done: (() -> Void)? = nil) {
        if a == 0 { ignoresMouseEvents = true }  // don't swallow clicks while fading out
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; animator().alphaValue = a }, completionHandler: done)
    }
}

/// Soft, muted palette (instead of saturated system colours).
enum Palette {
    static func hex(_ h: UInt32) -> Color { Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255) }
    static let sage = hex(0x7FC4A8), lavender = hex(0xA593F2), sky = hex(0x7DB9EE), rose = hex(0xEE9BB4), apricot = hex(0xF4A970)
    static let mint = hex(0x6FD39E), ink = hex(0x1D2233), night = hex(0x0D1120), paper = hex(0xFBF9F5)
}

private func ease(_ x: Double) -> Double { (1 - cos(.pi * min(1, max(0, x)))) / 2 }
func fmtTime(_ t: Int) -> String { String(format: "%d:%02d", t / 60, t % 60) }

// MARK: Guided break activities

/// Something to *do* during a break, with a follow-along visual.
struct Activity: Identifiable, Equatable {
    let id: String, title: String, hint: String, icon: String, color: Color
    static func == (a: Activity, b: Activity) -> Bool { a.id == b.id }
    static let all = [
        Activity(id: "far", title: "Look far away", hint: "Find something 20 feet away and let your focus soften", icon: "mountain.2", color: Palette.sage),
        Activity(id: "breathe", title: "Breathe", hint: "Follow the circle", icon: "wind", color: Palette.lavender),
        Activity(id: "trace", title: "Follow the dot", hint: "Keep your head still, move only your eyes", icon: "scope", color: Palette.sky),
        Activity(id: "blink", title: "Blink with me", hint: "Close your eyes fully each time", icon: "eye", color: Palette.rose),
        Activity(id: "stretch", title: "Loosen up", hint: "", icon: "figure.cooldown", color: Palette.apricot),
    ]
}

/// Visual + live caption for an activity, driven by time since it started.
struct ActivityVisual: View {
    let a: Activity, start: Date
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = max(0, ctx.date.timeIntervalSince(start))
            switch a.id {
            case "breathe": Breathe(t: t, color: a.color)
            case "trace": Trace(t: t, color: a.color)
            case "blink": BlinkAlong(t: t, color: a.color)
            case "stretch": Stretch(t: t, color: a.color)
            default: FarFocus(t: t, color: a.color)
            }
        }
    }
}

private struct Caption: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 19, weight: .regular, design: .rounded)).opacity(0.75)
            .multilineTextAlignment(.center).frame(maxWidth: 440).frame(height: 52, alignment: .top)
            .contentTransition(.opacity).animation(.easeInOut(duration: 0.4), value: text)
    }
}

private struct Stage<V: View>: View {
    let caption: String
    @ViewBuilder let visual: () -> V
    var body: some View {
        VStack(spacing: 28) { visual().frame(width: 250, height: 250).frame(width: 330, height: 330); Caption(text: caption) }
    }
}

private struct FarFocus: View {
    let t: Double, color: Color
    var body: some View {
        Stage(caption: Activity.all[0].hint) {
            ZStack {
                // Rings drift inward, like the horizon pulling your focus away.
                ForEach(0..<5) { i in
                    let p = (t / 7 + Double(i) / 5).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(color.opacity(0.7 * sin(.pi * p)), lineWidth: 1.5 + 2 * (1 - p))
                        .frame(width: 250 * (1 - p) + 10, height: 250 * (1 - p) + 10)
                }
                Circle().fill(.white).frame(width: 8, height: 8).shadow(color: color, radius: 8)
            }
        }
    }
}

private struct Breathe: View {
    let t: Double, color: Color
    var body: some View {
        let c = t.truncatingRemainder(dividingBy: 12)  // 4 in · 2 hold · 6 out
        let (label, s) = c < 4 ? ("Breathe in…", ease(c / 4)) : c < 6 ? ("Hold", 1.0) : ("…and slowly out", 1 - ease((c - 6) / 6))
        return Stage(caption: label) {
            ZStack {
                Circle().fill(color.opacity(0.12)).scaleEffect(0.5 + 0.5 * s + 0.04)
                Circle().fill(RadialGradient(colors: [color.opacity(0.9), color.opacity(0.35)], center: .center, startRadius: 0, endRadius: 130))
                    .scaleEffect(0.42 + 0.5 * s)
                    .shadow(color: color.opacity(0.6), radius: 30 * s)
                Circle().stroke(.white.opacity(0.25), lineWidth: 1).frame(width: 238, height: 238)
            }
        }
    }
}

private struct Trace: View {
    let t: Double, color: Color
    func pt(_ t: Double, _ r: CGFloat) -> CGPoint {
        let w = 2 * Double.pi / 9  // one figure-eight every 9 s
        return CGPoint(x: 130 + r * sin(w * t), y: 130 + r * 0.5 * sin(2 * w * t))
    }
    var body: some View {
        Stage(caption: Activity.all[2].hint) {
            Canvas { g, _ in
                var path = Path()
                for i in 0...120 { let p = pt(Double(i) * 9 / 120, 120); i == 0 ? path.move(to: p) : path.addLine(to: p) }
                g.stroke(path, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 2, dash: [2, 6]))
                for k in stride(from: 12, through: 1, by: -1) {  // fading trail
                    let p = pt(t - Double(k) * 0.05, 120), r = 9 - Double(k) * 0.5
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color.opacity(0.35 - Double(k) * 0.025)))
                }
                let p = pt(t, 120)
                g.addFilter(.shadow(color: color, radius: 10))
                g.fill(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(.white))
            }
        }
    }
}

private struct BlinkAlong: View {
    let t: Double, color: Color
    var body: some View {
        let n = Int(t / 3) + 1
        Stage(caption: "Blink \(n) — close, squeeze gently, open") {
            Eye(open: blinkOpen(t), color: .white, pupil: color).frame(width: 220, height: 120)
        }
    }
}

private struct Stretch: View {
    let t: Double, color: Color
    static let steps = [
        ("figure.cooldown", "Roll your shoulders back, slowly"),
        ("figure.flexibility", "Tilt your head to the left"),
        ("figure.flexibility", "…now to the right"),
        ("figure.arms.open", "Reach up and stretch tall"),
        ("hand.raised", "Shake out your hands"),
    ]
    var body: some View {
        let i = Int(t / 5) % Self.steps.count
        let s = Self.steps[i]
        Stage(caption: s.1) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                Circle().trim(from: 0, to: (t / 5).truncatingRemainder(dividingBy: 1))
                    .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    .padding(6)
                Image(systemName: s.0).font(.system(size: 96, weight: .light))
                    .scaleEffect(x: i == 2 ? -1 : 1).id(i)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.5), value: i)
        }
    }
}

/// 0 = closed, 1 = open. A slow blink every 3 s.
func blinkOpen(_ t: Double) -> Double {
    let c = t.truncatingRemainder(dividingBy: 3)
    return c < 2.3 || c > 2.9 ? 1 : abs(cos(.pi * (c - 2.3) / 0.6))
}

struct EyeShape: Shape {
    var open: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let dy = r.height * 0.95 * open
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.midY - dy))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.midY + max(r.height * 0.12, dy * 0.9)))
        p.closeSubpath()
        return p
    }
}

struct Eye: View {
    let open: Double, color: Color, pupil: Color
    var body: some View {
        GeometryReader { g in
            let h = g.size.height, lw = max(1.5, g.size.width * 0.045)
            ZStack {
                ZStack {
                    Circle().fill(pupil).frame(width: h * 0.62, height: h * 0.62)
                    Circle().fill(color).frame(width: h * 0.24, height: h * 0.24)
                }
                .mask(EyeShape(open: open))
                EyeShape(open: open).stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
            .frame(width: g.size.width, height: h)
        }
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
        for sc in NSScreen.screens {
            let w = KeyWindow(contentRect: sc.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isOpaque = false; w.backgroundColor = .clear; w.isReleasedWhenClosed = false
            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI; blur.blendingMode = .behindWindow; blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: OverlayView(s: s))
            host.frame = blur.bounds; host.autoresizingMask = [.width, .height]
            blur.addSubview(host)
            w.contentView = blur
            w.setFrame(sc.frame, display: true)
            w.onEsc = { [weak s] in if s?.state == .onBreak { s?.skip() } }
            w.alphaValue = 0; w.orderFrontRegardless(); w.fade(to: 1)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }
    /// `after` leaves the overlay up briefly, e.g. to show the "break complete" state.
    func close(after delay: Double = 0) {
        let ws = windows; windows = []
        guard !ws.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            ws.forEach { w in w.fade(to: 0) { w.orderOut(nil) } }
            NSApp.hide(nil)  // hand focus back to the previous app
        }
    }
}

struct OverlayView: View {
    @ObservedObject var s: BreakScheduler
    @State private var appear = false
    var a: Activity { s.activity }
    var progress: Double { s.breakTotal > 0 ? Double(max(0, s.breakLeft)) / Double(s.breakTotal) : 0 }

    var body: some View {
        ZStack {
            RadialGradient(colors: [(s.justFinished ? Palette.mint : a.color).opacity(0.28), Palette.night.opacity(0.55), Palette.night.opacity(0.85)],
                           center: .center, startRadius: 40, endRadius: 1000)
                .ignoresSafeArea().animation(.easeInOut(duration: 0.8), value: a).animation(.easeInOut(duration: 0.8), value: s.justFinished)
            if s.justFinished { Finished(s: s).transition(.scale(scale: 0.9).combined(with: .opacity)) }
            else { session.transition(.opacity) }
        }
        .foregroundStyle(.white)
        .scaleEffect(appear ? 1 : 0.96).opacity(appear ? 1 : 0)
        .animation(.spring(duration: 0.5), value: s.justFinished)
        .onAppear { withAnimation(.spring(duration: 0.7)) { appear = true } }
    }

    var session: some View {
        ZStack {
            VStack(spacing: 26) {
                HStack(spacing: 10) {
                    Text("EYE BREAK").tracking(2)
                    Circle().frame(width: 4, height: 4).opacity(0.5)
                    Text(fmtTime(max(0, s.breakLeft))).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true)).animation(.default, value: s.breakLeft)
                }
                .font(.system(size: 13, weight: .semibold)).opacity(0.6)
                Text(a.title).font(.system(size: 36, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity).animation(.easeInOut, value: a)
                ZStack(alignment: .top) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 3)
                        Circle().trim(from: 0, to: progress)
                            .stroke(a.color.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: progress)
                    }
                    .frame(width: 330, height: 330)
                    ActivityVisual(a: a, start: s.activityStart).id(a.id + "\(s.activityStart.timeIntervalSince1970)")
                }
                ActivityPicker(s: s)
            }
            .padding(.bottom, 70)
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    GhostButton(title: "+30 sec", icon: "plus") { s.extend() }
                    GhostButton(title: "Snooze \(s.snoozeMin) min", icon: "moon.zzz") { s.snooze() }
                    GhostButton(title: "Skip", icon: "forward.end", hint: "esc") { s.skip() }
                }
                .padding(6)
                .background(.white.opacity(0.06), in: Capsule())
                .padding(.bottom, 40)
            }
        }
    }
}

/// Lets you switch to a different exercise mid-break.
private struct ActivityPicker: View {
    @ObservedObject var s: BreakScheduler
    @State private var hover: String?
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Activity.all) { a in
                    let on = a == s.activity
                    Button { withAnimation(.spring(duration: 0.4)) { s.switchTo(a) } } label: {
                        Image(systemName: a.icon).font(.system(size: 16, weight: .medium))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(on ? a.color.opacity(0.85) : .white.opacity(hover == a.id ? 0.16 : 0.07)))
                            .overlay(Circle().stroke(.white.opacity(on ? 0.5 : 0.1)))
                            .scaleEffect(on ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                    .onHover { hover = $0 ? a.id : (hover == a.id ? nil : hover) }
                    .help(a.title)
                }
            }
            Text(hover.flatMap { h in Activity.all.first { $0.id == h }?.title } ?? "Try another")
                .font(.system(size: 12, weight: .medium)).opacity(0.45)
        }
    }
}

private struct Finished: View {
    @ObservedObject var s: BreakScheduler
    @State private var pop = false
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark").font(.system(size: 46, weight: .bold))
                .frame(width: 112, height: 112)
                .background(Circle().fill(Palette.mint.gradient))
                .shadow(color: Palette.mint.opacity(0.5), radius: 24)
                .scaleEffect(pop ? 1 : 0.4)
            Text("Eyes refreshed").font(.system(size: 36, weight: .semibold, design: .rounded))
            HStack(spacing: 6) {
                ForEach(0..<max(s.taken, 1), id: \.self) { _ in Circle().fill(Palette.mint).frame(width: 8, height: 8) }
            }
            Text("\(s.taken) break\(s.taken == 1 ? "" : "s") today · see you in \(s.workMin) min")
                .font(.system(size: 16, weight: .medium)).opacity(0.65)
        }
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.5)) { pop = true } }
    }
}

struct GhostButton: View {
    let title: String, icon: String
    var hint: String? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title)
                if let hint { Text(hint).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4)) }
            }
            .font(.system(size: 13, weight: .medium))
            .opacity(hover ? 1 : 0.7)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.white.opacity(hover ? 0.14 : 0), in: Capsule())
            .contentShape(Capsule())
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
    func show(_ s: BreakScheduler) { Sounds.play("warn"); bar.show(size: NSSize(width: 640, height: 92)) { HeadsUpView(s: s) } }
    func hide() { bar.hide() }
}

struct HeadsUpView: View {
    @ObservedObject var s: BreakScheduler
    var left: Int { max(0, s.interval - s.workSecs) }
    var progress: Double { Double(left) / Double(HeadsUp.lead) }
    var a: Activity { s.activity }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(a.color.opacity(0.15))
                Circle().trim(from: 0, to: progress)
                    .stroke(a.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(1.5)
                    .animation(.linear(duration: 1), value: progress)
                Image(systemName: a.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(a.color)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("Eye break in ")
                    Text("\(left)s").monospacedDigit().contentTransition(.numericText(countsDown: true)).animation(.default, value: left)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Up next: \(a.title.lowercased()) · \(s.breakSec < 60 ? "\(s.breakSec) sec" : fmtTime(s.breakSec))")
                    .font(.system(size: 12)).opacity(0.6)
            }
            Spacer(minLength: 8)
            BarButton(title: "In \(s.snoozeMin) min", icon: "clock", tint: a.color, filled: false) { s.snooze() }
            BarButton(title: "Start now", icon: "play.fill", tint: a.color, filled: true) { s.startBreak() }
            CloseButton(help: "Skip this break") { s.skip() }
        }
        .foregroundStyle(Palette.ink)
        .padding(.leading, 12).padding(.trailing, 14)
        .frame(width: 616, height: 68)
        .background(GlassCapsule())
        .padding(.bottom, 4)
    }
}

struct GlassCapsule: View {
    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .light)
            Capsule().fill(Palette.paper.opacity(0.8))
            Capsule().stroke(Palette.ink.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: Palette.ink.opacity(0.18), radius: 16, y: 6)
    }
}

struct BarButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Palette.sage
    let filled: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(filled ? AnyShapeStyle(tint.gradient.opacity(hover ? 1 : 0.88)) : AnyShapeStyle(Palette.ink.opacity(hover ? 0.1 : 0.05)), in: Capsule())
            .foregroundStyle(Palette.ink.opacity(filled ? 0.9 : 0.8))
            .scaleEffect(hover ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

/// Quiet dismiss: an ×, not a big "Skip" button.
struct CloseButton: View {
    let help: String, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.primary.opacity(hover ? 0.12 : 0.05)))
                .opacity(hover ? 0.9 : 0.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
