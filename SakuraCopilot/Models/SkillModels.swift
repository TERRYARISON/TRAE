import Foundation
import SwiftData

// MARK: - 技能（提示词工作流包）

@Model
final class Skill {
    @Attribute(.unique) var id: UUID
    var name: String
    var descText: String
    var promptTemplate: String
    var enabled: Bool
    var isBuiltin: Bool
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage) var triggersData: Data?
    @Attribute(.externalStorage) var stepsData: Data?

    init(id: UUID = UUID(), name: String, desc: String, triggers: [String] = [],
         prompt: String = "", steps: [String] = [],
         enabled: Bool = true, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.descText = desc
        self.promptTemplate = prompt
        self.enabled = enabled
        self.isBuiltin = isBuiltin
        self.createdAt = Date()
        self.updatedAt = Date()
        self.triggersData = try? JSONEncoder().encode(triggers)
        self.stepsData = try? JSONEncoder().encode(steps)
    }

    var triggers: [String] {
        get { (try? JSONDecoder().decode([String].self, from: triggersData ?? Data())) ?? [] }
        set { triggersData = try? JSONEncoder().encode(newValue); updatedAt = Date() }
    }

    var steps: [String] {
        get { (try? JSONDecoder().decode([String].self, from: stepsData ?? Data())) ?? [] }
        set { stepsData = try? JSONEncoder().encode(newValue); updatedAt = Date() }
    }

    /// 导入导出结构
    struct ExportForm: Codable {
        var name: String
        var desc: String
        var triggers: [String]
        var prompt: String
        var steps: [String]
    }

    var exportForm: ExportForm {
        ExportForm(name: name, desc: descText, triggers: triggers, prompt: promptTemplate, steps: steps)
    }
}
