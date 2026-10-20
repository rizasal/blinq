import Foundation
import CoreAudio
import CoreGraphics

final class CallDetector {
    static let prefixes = ["com.tinyspeck.slackmacgap","com.microsoft.teams","com.google.Chrome","com.microsoft.edgemac","company.thebrowser","com.apple.Safari","com.apple.WebKit","com.brave.Browser","org.mozilla.firefox",
        "us.zoom.xos","com.apple.FaceTime","com.apple.TelephonyUtilities","com.cisco.webexmeetingsapp","Cisco-Systems.Spark","com.hnc.Discord","net.whatsapp.WhatsApp"]
    static let owners = ["slack","teams","chrome","safari","arc","edge"]
    static let shareRe = try! NSRegularExpression(pattern: "is sharing your screen|You are presenting|sharing control bar", options: .caseInsensitive)
    private var calls = 0, sharing = false

    private func addr(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    func micInUse() -> Bool {
        var a = addr(kAudioHardwarePropertyProcessObjectList), size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == 0, size > 0 else { return false }
        var objs = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &objs) == 0 else { return false }
        for o in objs {
            var r: UInt32 = 0, sz = UInt32(4), ra = addr(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(o, &ra, 0, nil, &sz, &r) == 0, r != 0 else { continue }
            var ba = addr(kAudioProcessPropertyBundleID), cf: Unmanaged<CFString>?
            sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(o, &ba, 0, nil, &sz, &cf) == 0, let id = cf?.takeRetainedValue() as String? else { continue }
            if Self.prefixes.contains(where: id.hasPrefix) { return true }
        }
        return false
    }

    func screenSharing() -> Bool {
        guard let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return l.contains {
            guard let o = ($0[kCGWindowOwnerName as String] as? String)?.lowercased(), Self.owners.contains(where: o.contains),
                  let n = $0[kCGWindowName as String] as? String else { return false }
            return Self.shareRe.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
        }
    }

    var inCall: Bool {
        if calls % 3 == 0 { sharing = screenSharing() }
        calls += 1
        return micInUse() || sharing
    }
}
