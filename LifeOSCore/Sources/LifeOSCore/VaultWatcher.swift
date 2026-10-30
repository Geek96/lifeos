#if os(macOS)
import Foundation
import CoreServices

/// 监听 vault 与机器面目录的文件变化（FSEvents），替代手动“扫描”。只有 macOS 有；手机版回到前台时重新读。
/// latency 内的连续变动合并成一次回调；回调在后台队列上触发，调用方自行切回主线程。
public final class VaultWatcher: @unchecked Sendable {
    private let paths: [String]
    private let latency: Double
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "LifeOS.VaultWatcher")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    /// 不存在的路径会被忽略（例如还没有 {Semester}.data/）。
    public init(paths: [URL], latency: Double = 1.0, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        self.latency = latency
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        guard let s = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          latency, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }
}
#endif
