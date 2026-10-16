import Foundation

/// vault 根目录下的 `lifeos.json`：CourseOS 联动、图层开关、日历显示的时段。
public struct LifeConfig: Codable, Equatable, Sendable {
    public struct CourseOSLink: Codable, Equatable, Sendable {
        /// CourseOS 学期目录（含 courseos.json 的那一层）；空 = 不联动
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

    public var courseos: CourseOSLink
    public var layers: Layers
    public var dayHours: DayHours

    public init(courseos: CourseOSLink = .init(), layers: Layers = .init(), dayHours: DayHours = .init()) {
        self.courseos = courseos
        self.layers = layers
        self.dayHours = dayHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courseos = try c.decodeIfPresent(CourseOSLink.self, forKey: .courseos) ?? .init()
        layers = try c.decodeIfPresent(Layers.self, forKey: .layers) ?? .init()
        dayHours = try c.decodeIfPresent(DayHours.self, forKey: .dayHours) ?? .init()
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
