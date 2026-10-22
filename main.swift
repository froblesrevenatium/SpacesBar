import AppKit
import ApplicationServices
import ServiceManagement

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray

struct SpaceInfo: Equatable {
    let id: Int
    let number: Int?
    let isActive: Bool
    var apps: [pid_t]
}

struct DisplayInfo: Equatable {
    var spaces: [SpaceInfo]
}

enum SpaceReader {
    private static let connection = CGSMainConnectionID()
    private static let allSpacesMask: Int32 = 7
    private static let userSpaceType = 0

    static func read() -> [DisplayInfo] {
        guard let rawDisplays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else { return [] }
        var number = 0
        var displays = rawDisplays.map { display -> DisplayInfo in
            let currentID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> SpaceInfo? in
                guard let id = space["ManagedSpaceID"] as? Int else { return nil }
                let isUserSpace = (space["type"] as? Int) == userSpaceType
                if isUserSpace { number += 1 }
                return SpaceInfo(id: id, number: isUserSpace ? number : nil, isActive: id == currentID, apps: [])
            }
            return DisplayInfo(spaces: spaces)
        }

        for (spaceID, pid) in windowsBySpace() {
            for displayIndex in displays.indices {
                guard let spaceIndex = displays[displayIndex].spaces.firstIndex(where: { $0.id == spaceID }) else { continue }
                if !displays[displayIndex].spaces[spaceIndex].apps.contains(pid) {
                    displays[displayIndex].spaces[spaceIndex].apps.append(pid)
                }
            }
        }
        return displays
    }

    private static func windowsBySpace() -> [(space: Int, pid: pid_t)] {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var regularApps: [pid_t: Bool] = [:]
        var result: [(Int, pid_t)] = []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 50, (bounds["Height"] ?? 0) > 50 else { continue }
            let isRegular = regularApps[pid] ?? (NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular)
            regularApps[pid] = isRegular
            guard isRegular,
                  let spaces = CGSCopySpacesForWindows(connection, allSpacesMask, [windowID] as CFArray) as? [Int] else { continue }
            spaces.forEach { result.append(($0, pid)) }
        }
        return result
    }
}

struct RenderedBar {
    let image: NSImage
    let hits: [(range: ClosedRange<CGFloat>, space: SpaceInfo)]

    func space(at x: CGFloat) -> SpaceInfo? {
        hits.first { $0.range.contains(x) }?.space
    }
}

struct BarMetrics {
    let height: CGFloat
    let iconSize: CGFloat
    let iconSpacing: CGFloat
    let padding: CGFloat
    let spaceGap: CGFloat
    let displayGap: CGFloat
    let cornerRadius: CGFloat
    let font: NSFont

    init(height: CGFloat) {
        self.height = height
        iconSize = height - 4
        iconSpacing = 1
        padding = max(4, (height * 0.22).rounded())
        spaceGap = max(4, (height * 0.2).rounded())
        displayGap = spaceGap * 2.5
        cornerRadius = (height * 0.3).rounded()
        font = NSFont.monospacedDigitSystemFont(ofSize: (height * 0.52).rounded(), weight: .semibold)
    }
}

enum BarRenderer {
    private static let maxIcons = 6

    private struct Layout {
        let space: SpaceInfo
        let icons: [NSImage]
        let overflow: Int
        let label: String?
        let x: CGFloat
        let width: CGFloat
    }

    static func render(_ displays: [DisplayInfo], metrics m: BarMetrics, icon: (pid_t) -> NSImage?) -> RenderedBar {
        var layouts: [Layout] = []
        var separators: [CGFloat] = []
        var x: CGFloat = 0
        for (displayIndex, display) in displays.enumerated() {
            if displayIndex > 0 {
                separators.append(x + m.displayGap / 2 - m.spaceGap / 2)
                x += m.displayGap - m.spaceGap
            }
            for space in display.spaces {
                let icons = space.apps.compactMap(icon)
                let shown = Array(icons.prefix(maxIcons))
                let overflow = icons.count - shown.count
                let label = space.number.map(String.init)
                var width = m.padding * 2
                if let label { width += textWidth(label, m) }
                if !shown.isEmpty {
                    width += (label == nil ? 0 : m.padding - 1) + CGFloat(shown.count) * m.iconSize + CGFloat(shown.count - 1) * m.iconSpacing
                }
                if overflow > 0 { width += 2 + textWidth("+\(overflow)", m) }
                layouts.append(Layout(space: space, icons: shown, overflow: overflow, label: label, x: x, width: width))
                x += width + m.spaceGap
            }
        }
        let size = NSSize(width: max(x - m.spaceGap, 1), height: m.height)
        let image = NSImage(size: size, flipped: false) { _ in
            layouts.forEach { draw($0, m) }
            NSColor.labelColor.withAlphaComponent(0.35).setFill()
            separators.forEach { NSRect(x: $0, y: 4, width: 1, height: m.height - 8).fill() }
            return true
        }
        let hits = layouts.map { (range: ($0.x - m.spaceGap / 2)...($0.x + $0.width + m.spaceGap / 2), space: $0.space) }
        return RenderedBar(image: image, hits: hits)
    }

    private static func contrastingColor(for background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.6 ? NSColor.black.withAlphaComponent(0.85) : .white
    }

    private static func textWidth(_ text: String, _ m: BarMetrics) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: m.font]).width)
    }

    private static func draw(_ layout: Layout, _ m: BarMetrics) {
        let rect = NSRect(x: layout.x, y: 0, width: layout.width, height: m.height)
        let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: m.cornerRadius, yRadius: m.cornerRadius)
        let active = layout.space.isActive
        if active {
            NSColor.controlAccentColor.setFill()
            pill.fill()
        }
        let textColor = active ? contrastingColor(for: .controlAccentColor) : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: m.font, .foregroundColor: textColor]
        var x = rect.minX + m.padding
        if let label = layout.label {
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: NSPoint(x: x, y: (m.height - size.height) / 2), withAttributes: attributes)
            x += textWidth(label, m) + (layout.icons.isEmpty ? 0 : m.padding - 1)
        }
        for icon in layout.icons {
            icon.draw(in: NSRect(x: x, y: (m.height - m.iconSize) / 2, width: m.iconSize, height: m.iconSize), from: .zero, operation: .sourceOver, fraction: active ? 1 : 0.75)
            x += m.iconSize + m.iconSpacing
        }
        if layout.overflow > 0 {
            let text = "+\(layout.overflow)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: x, y: (m.height - size.height) / 2), withAttributes: attributes)
        }
    }
}

enum SpaceSwitcher {
    private static let firstDesktopHotKeyID = 118
    private static let lastDesktopNumber = 16

    private struct HotKey {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    enum Outcome {
        case switched
        case needsAccessibility
        case needsShortcut(Int)
    }

    static func switchTo(_ space: SpaceInfo) -> Outcome {
        guard !space.isActive else { return .switched }
        if let number = space.number, let hotKey = hotKey(forDesktop: number) {
            guard AXIsProcessTrusted() else { return .needsAccessibility }
            post(hotKey)
            return .switched
        }
        if let pid = space.apps.first, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            return .switched
        }
        return .needsShortcut(space.number ?? 0)
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func hotKey(forDesktop number: Int) -> HotKey? {
        guard (1...lastDesktopNumber).contains(number),
              let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
              let hotKeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotKeys[String(firstDesktopHotKeyID + number - 1)] as? [String: Any],
              (entry["enabled"] as? Bool) == true,
              let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
              parameters.count == 3 else { return nil }
        return HotKey(keyCode: CGKeyCode(parameters[1]), flags: CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    private static func post(_ hotKey: HotKey) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: hotKey.keyCode, keyDown: keyDown)
            event?.flags = hotKey.flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

final class MenuHostView: NSView {
    var onClick: ((NSView, NSPoint) -> Void)?
    var onRightClick: ((NSView) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?(self, convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(self)
    }
}

final class CenterBar {
    private static let verticalMargin: CGFloat = 2
    private var panels: [NSPanel] = []
    private var imageViews: [NSImageView] = []
    var onClick: ((CGFloat) -> Void)?
    var onRightClick: ((NSView) -> Void)?

    func show(_ image: NSImage) {
        if panels.count != NSScreen.screens.count { rebuild() }
        for (index, screen) in NSScreen.screens.enumerated() {
            imageViews[index].image = image
            panels[index].setFrame(frame(for: image.size, on: screen), display: true)
            panels[index].orderFrontRegardless()
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
    }

    func rebuild() {
        panels.forEach { $0.close() }
        panels = []
        imageViews = []
        for _ in NSScreen.screens {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false

            let host = MenuHostView()
            let imageView = NSImageView()
            host.onClick = { [weak self, weak imageView] view, point in
                guard let imageView else { return }
                self?.onClick?(view.convert(point, to: imageView).x)
            }
            host.onRightClick = { [weak self] view in self?.onRightClick?(view) }
            imageView.imageScaling = .scaleNone
            imageView.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            ])
            panel.contentView = host

            panels.append(panel)
            imageViews.append(imageView)
        }
    }

    static var contentHeight: CGFloat {
        guard let screen = NSScreen.screens.first else { return NSStatusBar.system.thickness }
        return menuBarHeight(of: screen) - verticalMargin * 2
    }

    private static func menuBarHeight(of screen: NSScreen) -> CGFloat {
        max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
    }

    private func frame(for imageSize: NSSize, on screen: NSScreen) -> NSRect {
        let menuBarHeight = Self.menuBarHeight(of: screen)
        let size = NSSize(width: imageSize.width, height: min(imageSize.height, menuBarHeight))
        var x = screen.frame.midX - size.width / 2
        if let rightOfNotch = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            x = max(x, screen.frame.minX + rightOfNotch.minX + 8)
        }
        let y = screen.frame.maxY - menuBarHeight + (menuBarHeight - size.height) / 2
        return NSRect(origin: NSPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
}

final class SpacesBar: NSObject, NSMenuDelegate {
    private static let centerKey = "showInCenter"
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let loginItem = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
    private let centerItem = NSMenuItem(title: "Mostrar en el centro", action: #selector(toggleCenter), keyEquivalent: "")
    private let menu = NSMenu()
    private let centerBar = CenterBar()
    private var showInCenter = UserDefaults.standard.bool(forKey: centerKey)
    private var displays: [DisplayInfo] = []
    private var rendered: RenderedBar?
    private var icons: [pid_t: NSImage] = [:]
    private var timer: Timer?

    override init() {
        super.init()
        menu.delegate = self
        loginItem.target = self
        centerItem.target = self
        menu.addItem(centerItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("Escritorios")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        centerBar.onClick = { [weak self] x in self?.clicked(atImageX: x) }
        centerBar.onRightClick = { [weak self] view in
            guard let self else { return }
            self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        names.forEach { workspace.addObserver(self, selector: #selector(refreshSoon), name: $0, object: nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(redraw), name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(redraw), name: Notification.Name("AppleColorPreferencesChangedNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSColor.systemColorsDidChangeNotification, object: nil)

        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh(force: true)
    }

    @objc private func refreshSoon() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    private func refresh(force: Bool = false) {
        let current = SpaceReader.read()
        guard force || current != displays else { return }
        displays = current
        redraw()
    }

    @objc private func redraw() {
        let alive = Set(displays.flatMap { $0.spaces.flatMap(\.apps) })
        icons = icons.filter { alive.contains($0.key) }
        let metrics = BarMetrics(height: showInCenter ? CenterBar.contentHeight : NSStatusBar.system.thickness - 2)
        let rendered = BarRenderer.render(displays, metrics: metrics) { [weak self] pid in self?.icon(for: pid) }
        self.rendered = rendered
        let image = rendered.image
        if showInCenter {
            item.isVisible = false
            centerBar.show(image)
        } else {
            centerBar.hide()
            item.isVisible = true
            item.button?.image = image
        }
        let active = displays.flatMap(\.spaces).filter(\.isActive).compactMap(\.number).map(String.init).joined(separator: ", ")
        item.button?.toolTip = active.isEmpty ? "Escritorios" : "Escritorio activo: \(active)"
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = icons[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
            return
        }
        let point = sender.convert(event.locationInWindow, from: nil)
        let imageWidth = rendered?.image.size.width ?? 0
        clicked(atImageX: point.x - (sender.bounds.width - imageWidth) / 2)
    }

    private func clicked(atImageX x: CGFloat) {
        guard let space = rendered?.space(at: x) else { return }
        switch SpaceSwitcher.switchTo(space) {
        case .switched:
            refreshSoon()
        case .needsAccessibility:
            SpaceSwitcher.requestAccessibility()
        case .needsShortcut(let number):
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = number > 0 ? "Activa el atajo del escritorio \(number)" : "No se puede cambiar a este espacio"
            alert.informativeText = number > 0
                ? "Configuración del Sistema → Teclado → Funciones rápidas de teclado → Mission Control → \"Cambiar al escritorio \(number)\". SpacesBar usa ese atajo para cambiar de escritorio."
                : "Este espacio no tiene apps ni atajo de teclado asociado."
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func screensChanged() {
        centerBar.rebuild()
        redraw()
    }

    @objc private func toggleCenter() {
        showInCenter.toggle()
        UserDefaults.standard.set(showInCenter, forKey: Self.centerKey)
        redraw()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        centerItem.state = showInCenter ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "No se pudo cambiar el inicio de sesión"
            alert.runModal()
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let bar = SpacesBar()
application.run()
