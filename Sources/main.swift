import AppKit
import SwiftUI
import Darwin

struct Entry: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let bytes: UInt64
}

func gb(_ bytes: UInt64) -> Double { Double(bytes) / 1_073_741_824 }
func reading(_ bytes: UInt64) -> String {
    bytes >= 1_073_741_824 ? String(format: "%.1f GB", gb(bytes)) :
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

func systemSample() -> (UInt64?, Int32?) {
    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / 4)
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    let result = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(host, HOST_VM_INFO64, $0, &count)
        }
    }
    let pages = max(0, Int64(vm.internal_page_count) - Int64(vm.purgeable_count))
        + Int64(vm.wire_count) + Int64(vm.compressor_page_count)
    var pressure: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let ok = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0
    return (result == KERN_SUCCESS ? UInt64(pages) * UInt64(getpagesize()) : nil, ok ? pressure : nil)
}

func footprints(_ roots: [String]) -> [String: UInt64] {
    let capacity = proc_listallpids(nil, 0) + 128
    guard capacity > 128 else { return [:] }
    var pids = [pid_t](repeating: 0, count: Int(capacity))
    let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
    guard count > 0 else { return [:] }
    var totals: [String: UInt64] = [:]
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    for pid in pids.prefix(Int(count)) where pid > 0 {
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard let root = roots.first(where: { path.hasPrefix($0 + "/") }) else { continue }
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        if status == 0 { totals[root, default: 0] += info.ri_phys_footprint }
    }
    return totals
}

final class Model: ObservableObject {
    @Published var used: UInt64?
    @Published var pressure: Int32?
    @Published var entries: [Entry] = []
    @Published var pinned = false
    let total = ProcessInfo.processInfo.physicalMemory

    var label: String {
        switch pressure {
        case 1: return "压力正常"
        case 2: return "内存吃紧"
        case 4: return "压力较高"
        default: return "压力未知"
        }
    }
    var tint: Color {
        switch pressure {
        case 1: return .green
        case 2: return .orange
        case 4: return .red
        default: return .secondary
        }
    }
}

struct Dial: View {
    let entry: Entry?
    let limit: Double
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                if let icon = entry?.icon {
                    Image(nsImage: icon).resizable().frame(width: 25, height: 25)
                }
                Text(entry?.name ?? "—").font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }.frame(height: 27)
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height - 7)
                    let radius = min(size.width / 2 - 19, center.y - 15)
                    func point(_ i: Int, _ r: Double) -> CGPoint {
                        let angle = Double(i) / 24 * Double.pi
                        return CGPoint(x: center.x - cos(angle) * r, y: center.y - sin(angle) * r)
                    }
                    var arc = Path()
                    arc.move(to: point(0, radius))
                    for i in 1...96 {
                        let angle = Double(i) / 96 * Double.pi
                        arc.addLine(to: CGPoint(x: center.x - cos(angle) * radius,
                                               y: center.y - sin(angle) * radius))
                    }
                    context.stroke(arc, with: .color(.accentColor.opacity(0.48)), lineWidth: 1)
                    for i in 0...24 {
                        let major = i.isMultiple(of: 8)
                        var tick = Path()
                        tick.move(to: point(i, radius))
                        tick.addLine(to: point(i, radius - (major ? 9 : 4)))
                        context.stroke(tick, with: .color(.primary.opacity(major ? 0.74 : 0.40)),
                                       lineWidth: major ? 1.3 : 0.7)
                        if major {
                            context.draw(Text(String(format: "%.0f", limit * Double(i) / 24))
                                .font(.system(size: 10, weight: .medium, design: .monospaced)),
                                         at: point(i, radius + 12))
                        }
                    }
                }
                if let entry {
                    GeometryReader { geometry in
                        let length = min(geometry.size.width / 2 - 19, geometry.size.height - 22) - 4
                        let fraction = min(1, gb(entry.bytes) / limit)
                        ZStack(alignment: .bottom) {
                            Path { path in
                                path.move(to: CGPoint(x: 3, y: 0))
                                path.addLine(to: CGPoint(x: 6, y: length - 5))
                                path.addQuadCurve(to: CGPoint(x: 0, y: length - 5),
                                                  control: CGPoint(x: 3, y: length + 5))
                                path.closeSubpath()
                            }
                            .fill(LinearGradient(colors: [.gray, .white, Color(white: 0.42), Color(white: 0.8)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .shadow(color: .black.opacity(0.4), radius: 1.4, x: 1, y: 1)
                            Circle().fill(Color(white: 0.36)).frame(width: 2, height: 2)
                        }
                        .frame(width: 6, height: length)
                        .rotationEffect(.degrees(-90 + fraction * 180), anchor: .bottom)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 7 - length / 2)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: fraction)
                    }
                }
            }.frame(height: 89)
            Text(entry.map { reading($0.bytes) } ?? "—")
                .font(.system(size: 23, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.20)))
    }
}

struct Dashboard: View {
    @ObservedObject var model: Model
    let togglePin: () -> Void
    let quit: () -> Void
    var body: some View {
        let limit = max(6, ceil(gb(model.entries.first?.bytes ?? 0) / 3) * 3)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RAMLOOP").font(.system(size: 17, weight: .bold)).tracking(1)
                    Label { Text(model.label) } icon: {
                        Circle().fill(model.tint).frame(width: 7, height: 7)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%@ / %.0f GB",
                            model.used.map { String(format: "%.1f", gb($0)) } ?? "—",
                            gb(model.total)))
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                Button(action: togglePin) {
                    Image(systemName: model.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help(model.pinned ? "取消固定" : "固定面板")
                Menu {
                    Button("退出 RAMLOOP", action: quit)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            HStack(spacing: 10) {
                Dial(entry: model.entries.first, limit: limit)
                Dial(entry: model.entries.dropFirst().first, limit: limit)
            }
            Text("其他应用").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(model.entries.dropFirst(2).prefix(3))) { entry in
                    HStack(spacing: 7) {
                        if let icon = entry.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        Text(reading(entry.bytes)).monospacedDigit()
                    }.font(.system(size: 12)).frame(height: 22)
                }
                if model.entries.count <= 2 {
                    Text("—").foregroundStyle(.secondary).frame(height: 22)
                }
            }.padding(.horizontal, 9)
            Spacer(minLength: 0)
        }.padding(14).frame(width: 440, height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 330),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    var hoverStart: TimeInterval?
    var exitStart: TimeInterval?
    var lastSystem = -Double.infinity
    var lastApps = -Double.infinity
    var sampling = false
    var suppressHover = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "RAMLOOP")
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(frame: panel.contentView!.bounds)
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 20
        glass.layer?.masksToBounds = true
        let mask = NSImage(size: glass.bounds.size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
            return true
        }
        glass.maskImage = mask
        let content = NSHostingView(rootView: Dashboard(model: model, togglePin: { [weak self] in
            self?.model.pinned.toggle()
        }, quit: { NSApp.terminate(nil) }))
        content.frame = glass.bounds
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        content.layer?.cornerRadius = 20
        content.layer?.masksToBounds = true
        glass.addSubview(content)
        panel.contentView = glass
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        tick()
        if CommandLine.arguments.contains("--preview") {
            model.pinned = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.show() }
        }
    }

    func buttonFrame() -> NSRect? {
        guard let button = item.button, let window = button.window, item.isVisible else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func show() {

        guard let anchor = buttonFrame(),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })
        else { return }
        let width = panel.frame.width
        let x = min(max(anchor.midX - width / 2, screen.visibleFrame.minX + 6),
                    screen.visibleFrame.maxX - width - 6)
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - panel.frame.height - 3))
        panel.orderFrontRegardless()
        exitStart = nil
        lastSystem = -.infinity
        lastApps = -.infinity
    }

    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "退出 RAMLOOP", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            if let button = item.button, let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: button)
            }
        } else if model.pinned {
            model.pinned = false
            suppressHover = true
            panel.orderOut(nil)
        } else {
            model.pinned = true
            show()
        }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation
        let overButton = buttonFrame()?.contains(mouse) ?? false
        if !overButton { suppressHover = false }
        if !panel.isVisible && overButton && !suppressHover {
            if hoverStart == nil { hoverStart = now }
            if now - (hoverStart ?? now) >= 0.30 { show() }
        } else { hoverStart = nil }
        if panel.isVisible && !model.pinned && !overButton && !panel.frame.contains(mouse) {
            if exitStart == nil { exitStart = now }
            if now - (exitStart ?? now) >= 0.06 { panel.orderOut(nil) }
        } else { exitStart = nil }

        if now - lastSystem >= (panel.isVisible ? 1 : 3) {
            lastSystem = now
            (model.used, model.pressure) = systemSample()
            item.button?.contentTintColor = model.pressure == 4 ? .systemRed :
                model.pressure == 2 ? .systemOrange : nil
        }
        guard panel.isVisible, !sampling, now - lastApps >= 3 else { return }
        lastApps = now
        sampling = true
        var apps: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let path = app.bundleURL?.resolvingSymlinksInPath().path { apps[path] = app }
        }
        let catalog = apps
        let roots = catalog.keys.sorted { $0.count > $1.count }
        DispatchQueue.global(qos: .utility).async {
            let totals = footprints(roots)
            DispatchQueue.main.async {
                self.model.entries = totals.compactMap { path, bytes -> Entry? in
                    guard let app = catalog[path], bytes > 0 else { return nil }
                    return Entry(id: path, name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                                 icon: app.icon, bytes: bytes)
                }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
                self.sampling = false
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
