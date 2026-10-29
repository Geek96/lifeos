import Foundation

/// vault 根目录下的 `lifeos.json`：CourseOS 联动、图层开关、日历显示的时段。
public struct LifeConfig: Codable, Equatable, Sendable {
    public struct CourseOSLink: Codable, Equatable, Sendable {
        /// CourseOS 学期目录（含 courseos.json 的那一层）；空 = 不联动。
        /// 以 `/` 开头按绝对路径；否则相对 vault 文件夹解析（比如 `../GT-semseters/2026Fall`）——
        /// LifeOS 和 CourseOS 常是同一个 Obsidian 目录下的两个兄弟 vault，相对路径不用管用户名、
        /// 换一台电脑也不用改。设置里的"选择…"会自动存成相对路径（选的文件夹和 vault 没有共同上级时才存绝对路径）。
        public var semester: String
        /// 上课时间块从哪天到哪天（学期上课的起止日）
        public var classesFrom: String?
        public var classesUntil: String?
        /// 课号 → 用户所在 section（课程档案写了多个 section 时用）
        public var sections: [String: String]

        public init(semester: String = "", classesFrom: String? = nil, classesUntil: String? = nil,
                    sections: [String: String] = [:]) {
            self.semester = semester
            self.classesFrom = classesFrom
            self.classesUntil = classesUntil
            self.sections = sections
        }

        /// `semester` 解析成实际路径；空 = 不联动，返回 nil。
        public func resolvedSemesterURL(vault: URL) -> URL? {
            guard !semester.isEmpty else { return nil }
            if semester.hasPrefix("/") { return URL(fileURLWithPath: semester) }
            return vault.appendingPathComponent(semester).standardizedFileURL
        }

        /// 从 `base`（vault）到 `target`（学期目录）算一条相对路径，比如 `../GT-semseters/2026Fall`；
        /// 两者只共享根目录（没有有意义的共同上级，比如在不同磁盘）时返回 nil，调用方退回绝对路径。
        public static func relativePath(from base: URL, to target: URL) -> String? {
            let baseParts = base.standardizedFileURL.pathComponents
            let targetParts = target.standardizedFileURL.pathComponents
            var common = 0
            while common < baseParts.count, common < targetParts.count, baseParts[common] == targetParts[common] {
                common += 1
            }
            guard common > 1 else { return nil }
            let ups = Array(repeating: "..", count: baseParts.count - common)
            let downs = targetParts[common...]
            let parts = ups + downs
            return parts.isEmpty ? "." : parts.joined(separator: "/")
        }
    }

    public struct Layers: Codable, Equatable, Sendable {
        public var classes: Bool
        public var courseDeadlines: Bool
        public var courseOptional: Bool

        public init(classes: Bool = true, courseDeadlines: Bool = true, courseOptional: Bool = false) {
            self.classes = classes
            self.courseDeadlines = courseDeadlines
            self.courseOptional = courseOptional
        }
    }

    public struct DayHours: Codable, Equatable, Sendable {
        public var start: Int
        public var end: Int
        public init(start: Int = 8, end: Int = 23) { self.start = start; self.end = end }
    }

    /// 插件开关；没写的插件默认关
    public struct Plugins: Codable, Equatable, Sendable {
        /// 健康：训练、饮食记录与目标对比、复测
        public var health: Bool
        /// 物品：找东西、资产、补货与保养、售后、搬家
        public var things: Bool
        /// 消费：流水、账户余额、订阅、预算
        public var finance: Bool
        /// 出行：近期、全部（含归档）、想去；每次出行的详情页
        public var travel: Bool
        /// 远景：愿景（时间甬道 / 清单）、项目（步骤与进度）、奇思妙想
        public var vision: Bool

        public init(health: Bool = false, things: Bool = false, finance: Bool = false, travel: Bool = false, vision: Bool = false) {
            self.health = health
            self.things = things
            self.finance = finance
            self.travel = travel
            self.vision = vision
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            health = try c.decodeIfPresent(Bool.self, forKey: .health) ?? false
            things = try c.decodeIfPresent(Bool.self, forKey: .things) ?? false
            finance = try c.decodeIfPresent(Bool.self, forKey: .finance) ?? false
            travel = try c.decodeIfPresent(Bool.self, forKey: .travel) ?? false
            vision = try c.decodeIfPresent(Bool.self, forKey: .vision) ?? false
        }
    }

    public var courseos: CourseOSLink
    public var layers: Layers
    public var dayHours: DayHours
    public var plugins: Plugins

    public init(courseos: CourseOSLink = .init(), layers: Layers = .init(), dayHours: DayHours = .init(),
                plugins: Plugins = .init()) {
        self.courseos = courseos
        self.layers = layers
        self.dayHours = dayHours
        self.plugins = plugins
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courseos = try c.decodeIfPresent(CourseOSLink.self, forKey: .courseos) ?? .init()
        layers = try c.decodeIfPresent(Layers.self, forKey: .layers) ?? .init()
        dayHours = try c.decodeIfPresent(DayHours.self, forKey: .dayHours) ?? .init()
        plugins = try c.decodeIfPresent(Plugins.self, forKey: .plugins) ?? .init()
    }

    public static func fileURL(vault: URL) -> URL { vault.appendingPathComponent("lifeos.json") }

    public static func load(vault: URL) -> LifeConfig {
        guard let data = try? Data(contentsOf: fileURL(vault: vault)),
              let config = try? JSONDecoder().decode(LifeConfig.self, from: data) else { return LifeConfig() }
        return config
    }

    public func save(vault: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.fileURL(vault: vault), options: .atomic)
    }
}
