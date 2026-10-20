import SwiftUI
import AppKit

enum Sounds {
    static let names = ["None", "Glass", "Hero", "Ping", "Pop", "Purr", "Tink", "Submarine", "Blow", "Bottle", "Frog", "Funk", "Morse", "Sosumi", "Basso"]
    static let events: [(key: String, name: String, icon: String, color: Color, def: String)] = [
        ("warn", "Break warning", "bell", .teal, "Tink"),
        ("breakStart", "Break starts", "cup.and.saucer", .indigo, "Glass"),
        ("breakEnd", "Break ends", "checkmark", .green, "Hero"),
        ("posture", "Sit up straight", "figure.stand", .orange, "Pop"),
        ("blink", "Blink your eyes", "eye", .cyan, "Purr"),
    ]
    static func name(_ key: String) -> String {
        UserDefaults.standard.string(forKey: "snd_" + key) ?? events.first { $0.key == key }?.def ?? "None"
    }
    static func play(_ key: String) { preview(name(key)) }
    static func preview(_ n: String) { if n != "None" { NSSound(named: n)?.stop(); NSSound(named: n)?.play() } }
}

struct SoundRow: View {
    let e: (key: String, name: String, icon: String, color: Color, def: String)
    @AppStorage var sound: String
    init(_ e: (key: String, name: String, icon: String, color: Color, def: String)) {
        self.e = e; _sound = AppStorage(wrappedValue: e.def, "snd_" + e.key)
    }
    var body: some View {
        Row(e.icon, e.color, e.name, nil) {
            Picker("", selection: $sound) { ForEach(Sounds.names, id: \.self) { Text($0) } }
                .labelsHidden().frame(width: 120)
            Button { Sounds.preview(sound) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless).disabled(sound == "None")
        }
        .onChange(of: sound) { _, n in Sounds.preview(n) }
    }
}
