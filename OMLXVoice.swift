import Cocoa
import Carbon
import AVFoundation

enum Settings {
    // 触发按键:鼠标按键编号(4 = 多数鼠标的“前进”侧键)。可在 ~/.config/omlx-voice/button 里改
    static var button: Int64 = {
        let p = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/omlx-voice/button")
        if let t = try? String(contentsOf: p, encoding: .utf8), let n = Int64(t.trimmingCharacters(in: .whitespacesAndNewlines)) { return n }
        return 4
    }()
}

let serverURL = URL(string: "http://127.0.0.1:8977/inference")!
let wavURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("omlx-voice.wav")

final class HUD {
    var panel: NSPanel?
    var label: NSTextField!
    func show(_ text: String) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let fx = NSVisualEffectView(frame: p.contentView!.bounds)
            fx.material = .hudWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = 12
            fx.layer?.masksToBounds = true
            fx.autoresizingMask = [.width, .height]
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: 15, weight: .medium)
            l.alignment = .center
            l.frame = NSRect(x: 8, y: 9, width: 144, height: 22)
            l.autoresizingMask = [.width]
            fx.addSubview(l)
            p.contentView = fx
            panel = p
            label = l
        }
        label.stringValue = text
        if let s = NSScreen.main {
            panel?.setFrameOrigin(NSPoint(x: s.frame.midX - 80, y: s.frame.minY + 120))
        }
        panel?.orderFrontRegardless()
    }
    func hide(after: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { self.panel?.orderOut(nil) }
    }
}

let hud = HUD()

let historyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/omlx-voice/history.jsonl")
var history: [String] = []
final class MenuTarget: NSObject {
    @objc func pick(_ item: NSMenuItem) {
        guard let t = item.representedObject as? String else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { paste(t) }
    }
}
let menuTarget = MenuTarget()
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

func rebuildMenu() {
    let m = NSMenu()
    let head = NSMenuItem(title: history.isEmpty ? "还没有识别记录" : "点一句,重新贴到光标处", action: nil, keyEquivalent: "")
    head.isEnabled = false
    m.addItem(head)
    for t in history.suffix(10).reversed() {
        let title = t.count > 36 ? String(t.prefix(36)) + "…" : t
        let it = NSMenuItem(title: title, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
        it.target = menuTarget
        it.representedObject = t
        m.addItem(it)
    }
    m.addItem(.separator())
    m.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem.menu = m
}

func record(_ text: String) {
    history.append(text)
    if history.count > 50 { history.removeFirst(history.count - 50) }
    let obj: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "text": text]
    if let d = try? JSONSerialization.data(withJSONObject: obj), var line = String(data: d, encoding: .utf8) {
        line += "\n"
        if let h = try? FileHandle(forWritingTo: historyURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: historyURL, atomically: true, encoding: .utf8) }
    }
    rebuildMenu()
}
var recorder: AVAudioRecorder?
var recordStart = Date()

func startRecording() {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        hud.show("需要麦克风权限"); hud.hide(after: 2); return
    }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                                   AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                   AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    try? FileManager.default.removeItem(at: wavURL)
    recorder = try? AVAudioRecorder(url: wavURL, settings: settings)
    if recorder?.record() == true {
        recordStart = Date()
        hud.show("● 录音中…")
        let started = recordStart
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { if recorder?.isRecording == true && recordStart == started { stopRecording() } }
    } else {
        hud.show("无法录音"); hud.hide(after: 2)
    }
}

func stopRecording() {
    guard let r = recorder, r.isRecording else { return }
    r.stop()
    recorder = nil
    if Date().timeIntervalSince(recordStart) < 0.4 { hud.hide(); return }
    hud.show("识别中…")
    transcribe()
}

func transcribe() {
    guard let audio = try? Data(contentsOf: wavURL) else { hud.hide(); return }
    let boundary = "----omlxvoice\(UUID().uuidString)"
    var body = Data()
    func field(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }
    field("response_format", "json")
    field("temperature", "0.0")
    field("language", "auto")
    let promptFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/omlx-voice/prompt.txt")
    let prompt = (try? String(contentsOf: promptFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    field("prompt", prompt ?? "你好,这是一段中文。Hello, this is an English sentence.")
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    body.append(audio)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    var req = URLRequest(url: serverURL)
    req.httpMethod = "POST"
    req.timeoutInterval = 60
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.httpBody = body
    URLSession.shared.dataTask(with: req) { data, _, err in
        var text = ""
        if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = j["text"] as? String {
            text = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        DispatchQueue.main.async {
            if text.isEmpty {
                hud.show(err == nil ? "没听清" : "识别服务未启动"); hud.hide(after: 1.5)
            } else {
                hud.hide()
                record(text)
                paste(text)
            }
        }
    }.resume()
}

func paste(_ text: String) {
    let pb = NSPasteboard.general
    let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
        item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
    }
    pb.clearContents()
    pb.setString(text, forType: .string)
    let src = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        pb.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let it = NSPasteboardItem()
            for (t, d) in entries { it.setData(d, forType: t) }
            return it
        }
        pb.writeObjects(items)
    }
}

func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("omlxVoiceRepaste"), object: nil) }
    return noErr
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

NotificationCenter.default.addObserver(forName: Notification.Name("omlxVoiceKey"), object: nil, queue: .main) { n in
    if (n.userInfo?["pressed"] as? Bool) == true { startRecording() } else { stopRecording() }
}

AVCaptureDevice.requestAccess(for: .audio) { _ in }
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
_ = AXIsProcessTrustedWithOptions(opts)

func mouseTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        NotificationCenter.default.post(name: Notification.Name("omlxVoiceReenable"), object: nil)
        return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.mouseEventButtonNumber) == Settings.button else { return Unmanaged.passUnretained(event) }
    let pressed = type == .otherMouseDown
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: Notification.Name("omlxVoiceKey"), object: nil, userInfo: ["pressed": pressed])
    }
    return nil
}

let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
var tap: CFMachPort?
func installTap() {
    tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                            eventsOfInterest: CGEventMask(mask), callback: mouseTap, userInfo: nil)
    if let tap {
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    } else {
        hud.show("需要辅助功能权限"); hud.hide(after: 3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { installTap() }
    }
}
NotificationCenter.default.addObserver(forName: Notification.Name("omlxVoiceReenable"), object: nil, queue: .main) { _ in
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
}
statusItem.button?.title = "🎙"
rebuildMenu()
if let lines = try? String(contentsOf: historyURL, encoding: .utf8) {
    history = lines.split(separator: "\n").suffix(50).compactMap {
        (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["text"] as? String
    }
    rebuildMenu()
}
NotificationCenter.default.addObserver(forName: Notification.Name("omlxVoiceRepaste"), object: nil, queue: .main) { _ in
    if let t = history.last { paste(t) }
}
var hotKeyRef: EventHotKeyRef?
var hkSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &hkSpec, nil, nil)
RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x6f6d7676), id: 2), GetApplicationEventTarget(), 0, &hotKeyRef)
if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
installTap()

app.run()
