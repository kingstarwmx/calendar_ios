import Matrix
import Foundation

final class MatrixManager: NSObject, MatrixPluginListenerDelegate, WCCrashBlockMonitorDelegate {
    static let shared = MatrixManager()

    private var crashPlugin: WCCrashBlockMonitorPlugin?
    private var memoryPlugin: WCMemoryStatPlugin?
    private var fpsPlugin: WCFPSMonitorPlugin?
    private var builder: MatrixBuilder?

    private override init() {
        super.init()
    }

    func start() {
        guard crashPlugin == nil else { return }

        guard let matrix = Matrix.sharedInstance() as? Matrix else {
            assertionFailure("Matrix sharedInstance not available")
            return
        }

        let builder = MatrixBuilder()
        builder.pluginListener = self

        let crashPlugin = WCCrashBlockMonitorPlugin()
        let crashConfig = WCCrashBlockMonitorConfig()
        crashConfig.enableCrash = true
        crashConfig.blockMonitorDelegate = self
        crashConfig.enableBlockMonitor = true
        if let blockConfig = WCBlockMonitorConfiguration.defaultConfig() as? WCBlockMonitorConfiguration {
            blockConfig.bMainThreadHandle = true
            blockConfig.bFilterSameStack = true
            crashConfig.blockMonitorConfiguration = blockConfig
        }
        crashPlugin.pluginConfig = crashConfig

        let memoryPlugin = WCMemoryStatPlugin()
        memoryPlugin.pluginConfig = WCMemoryStatConfig.defaultConfiguration()

        let fpsPlugin = WCFPSMonitorPlugin()
        if let fpsConfig = WCFPSMonitorConfig.defaultConfigurationForScroll() as? WCFPSMonitorConfig {
            fpsPlugin.pluginConfig = fpsConfig
        }

        builder.add(crashPlugin)
        builder.add(memoryPlugin)
        builder.add(fpsPlugin)

        matrix.add(builder)

        _ = crashPlugin.start()
        _ = memoryPlugin.start()
        _ = fpsPlugin.start()

        self.builder = builder
        self.crashPlugin = crashPlugin
        self.memoryPlugin = memoryPlugin
        self.fpsPlugin = fpsPlugin
    }

    func stop() {
        crashPlugin?.stop()
        memoryPlugin?.stop()
        fpsPlugin?.stop()
        crashPlugin = nil
        memoryPlugin = nil
        fpsPlugin = nil
        builder = nil
    }

    // MARK: - MatrixPluginListenerDelegate
    
    func onInit(_ plugin: MatrixPluginProtocol) {
        debugLog("[Matrix] plugin init: \(type(of: plugin))")
    }

    func onStart(_ plugin: MatrixPluginProtocol) {
        debugLog("[Matrix] plugin start: \(type(of: plugin))")
    }

    func onStop(_ plugin: MatrixPluginProtocol) {
        debugLog("[Matrix] plugin stop: \(type(of: plugin))")
    }

    func onDestroy(_ plugin: MatrixPluginProtocol) {
        debugLog("[Matrix] plugin destroy: \(type(of: plugin))")
    }

    func onReport(_ issue: MatrixIssue) {
        let tag = issue.issueTag ?? "unknown"
        let info = issue.customInfo ?? [:]
        debugLog("[Matrix] issue tag: \(tag) info: \(info)")
    }
    
    // MARK: - WCCrashBlockMonitorDelegate
    func onCrashBlockMonitorRunloopHangDetected(_ duration: UInt64) {
            debugLog("[Matrix] runloop hang \(duration / 1000) ms")
    }

    func onCrashBlockMonitorGetDumpFile(_ dumpFile: String!, with dumpType: EDumpType) {
        guard dumpType == .mainThreadBlock else { return }

        let url = URL(fileURLWithPath: dumpFile)
            .appendingPathComponent("BlockMainThread.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = json["frame_stack"] as? [[String: Any]],
              let firstStack = stacks.first,
              let frames = firstStack["stack_string"] as? [String] else { return }

        debugLog("====== Matrix 卡顿堆栈（前 10 帧） ======")
        frames.prefix(10).forEach { debugLog($0) }
        debugLog("=================================")
    }

    // MARK: - Helpers

    private func debugLog(_ message: String) {
#if DEBUG
        print(message)
#endif
    }
}
