// DEBUG only: `-FSSnapshot <dir>` renders the §13.2 Mac screenshot matrix to PNG files without
// XCUITest (no Developer Tools or Accessibility prompt, no Screen Recording permission: the app
// only draws its own windows). Each demo screen is shown in a real window at the default window
// size, in light and dark, at the default and the largest text size, plus the menu-bar panel.
//
//   -FSSnapshot <dir>               output folder (created)
//   -FSSnapshotScreens a,b,c        only these DemoScreen names (default: the Mac matrix)
//   -FSSnapshotTall                 also render each screen in a tall window (whole page)
//
// Demo models are fully in memory: no CloudKit, no network, no Keychain, no checks, no login item.

#if DEBUG
import AppKit
import SwiftUI
import ShieldCore
import ShieldUI

@MainActor
enum SnapshotRunner {
    static let flag = "-FSSnapshot"
    static let screensFlag = "-FSSnapshotScreens"
    static let tallFlag = "-FSSnapshotTall"

    struct Variant {
        let appearance: NSAppearance.Name
        let size: DynamicTypeSize

        var name: String {
            "\(appearance == .darkAqua ? "dark" : "light")-\(ShieldTypeScale.name(size))"
        }
    }

    static let variants: [Variant] = [
        Variant(appearance: .aqua, size: .large),
        Variant(appearance: .darkAqua, size: .large),
        Variant(appearance: .aqua, size: .accessibility5),
        Variant(appearance: .darkAqua, size: .accessibility5),
    ]

    /// The menu-bar panel in each of its three words: "Protected", "1 to do", "Today".
    static let menuScreens: [DemoScreen] = [.homeProtected, .homeOneToDo, .homeOneRed]

    static func outputDirectory(_ arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex else { return nil }
        return URL(fileURLWithPath: arguments[arguments.index(after: index)], isDirectory: true)
    }

    static func run(outputDirectory: URL, arguments: [String]) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var screens = DemoScreen.macScreenshotMatrix
        if let index = arguments.firstIndex(of: screensFlag), arguments.index(after: index) < arguments.endIndex {
            screens = arguments[arguments.index(after: index)].split(separator: ",").compactMap { DemoScreen(name: String($0)) }
        }
        let tall = arguments.contains(tallFlag)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        Task { @MainActor in
            var count = 0
            for variant in variants {
                for screen in screens {
                    await capture(window: screen, variant: variant, height: MainWindow.defaultHeight,
                                  to: outputDirectory.appendingPathComponent("mac-\(variant.name)-\(screen.rawValue).png"))
                    count += 1
                    if tall {
                        await capture(window: screen, variant: variant, height: 2_400,
                                      to: outputDirectory.appendingPathComponent("tall-mac-\(variant.name)-\(screen.rawValue).png"))
                    }
                }
                for screen in menuScreens {
                    await capture(menuFor: screen, variant: variant,
                                  to: outputDirectory.appendingPathComponent("menubar-\(variant.name)-\(screen.rawValue).png"))
                    count += 1
                }
            }
            print("snapshots \(count) -> \(outputDirectory.path)")
            exit(0)
        }
        app.run()
        exit(0)
    }

    // MARK: Window

    private static func capture(window screen: DemoScreen, variant: Variant, height: CGFloat, to url: URL) async {
        let model = AppModel.demo(screen, platform: .mac)
        let root = RootView(model: model)
            .dynamicTypeSize(variant.size)
            .frame(minWidth: ShieldMetrics.macWindowMinWidth, minHeight: ShieldMetrics.macWindowMinHeight)
        let window = UnconstrainedWindow(
            contentRect: NSRect(x: 40, y: 40, width: MainWindow.defaultWidth, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Family Shield"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: variant.appearance)
        window.contentView = NSHostingView(rootView: root)
        window.setContentSize(NSSize(width: MainWindow.defaultWidth, height: height))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(1_200))
        if let frameView = window.contentView?.superview {
            write(frameView, to: url)
        }
        window.close()
    }

    // MARK: Menu-bar panel

    private static func capture(menuFor screen: DemoScreen, variant: Variant, to url: URL) async {
        let model = AppModel.demo(screen, platform: .mac)
        let content = MenuBarSnapshot(model: model).dynamicTypeSize(variant.size)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let window = UnconstrainedWindow(contentRect: NSRect(x: 60, y: 60, width: size.width, height: size.height),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: variant.appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        write(hosting, to: url)
        window.close()
    }

    /// Draws `view` at 1× into a PNG.
    private static func write(_ view: NSView, to url: URL) {
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// A window that may be taller than the screen (whole-page review renders).
private final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The menu-bar item above its panel, as it looks when clicked.
private struct MenuBarSnapshot: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            MenuBarLabelContent(model: model)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: 30)
                .background(Color(nsColor: .windowBackgroundColor))
            // Drawn for a 13-inch MacBook Air screen, whatever screen the tool runs on.
            MenuBarPanel(model: model, screenHeight: MenuBarPanel.smallLaptopScreenHeight, openWindow: {}, quit: {})
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                .padding([.horizontal, .bottom], 12)
        }
        .fixedSize()
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
#endif
