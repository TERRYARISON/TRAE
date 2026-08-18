import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 右抽屉：助理设置（人设 → 记忆 → 技能 → 模型 → 偏好 → 备份）
struct AssistantDrawer: View {
    @Environment(AppServices.self) private var services
    let close: () -> Void

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("樱").font(.cyber(24, .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(CyberTheme.sakuraGrad))
                            .shadow(color: CyberTheme.neonPink.opacity(0.6), radius: 8)
                        Text("助理").font(.cyber(18, .bold)).foregroundStyle(CyberTheme.sakura)
                    }
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                            .foregroundStyle(CyberTheme.textFaint)
                    }
                }
                .padding(16)

                ScrollView {
                    VStack(spacing: 12) {
                        DrawerLink(icon: "person.crop.square.filled.and.at.rectangle", title: "助理人设", tint: CyberTheme.neonPink) {
                            PersonaPanel()
                        }
                        DrawerLink(icon: "brain.head.profile", title: "记忆四卡片", tint: CyberTheme.neonPurple) {
                            MemoryPanel()
                        }
                        DrawerLink(icon: "wand.and.stars", title: "技能", tint: CyberTheme.neonCyan) {
                            SkillPanel()
                        }
                        DrawerLink(icon: "cpu", title: "模型配置", tint: CyberTheme.neonGold) {
                            ModelPanel()
                        }
                        DrawerLink(icon: "gearshape.2", title: "偏好设置", tint: CyberTheme.sakura) {
                            PreferencesPanel()
                        }
                        DrawerLink(icon: "arrow.up.arrow.down.circle", title: "备份与导出", tint: CyberTheme.neonMagenta) {
                            BackupPanel()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

private struct DrawerLink<Destination: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            WithSakuraBackground { destination() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.14)))
                Text(title).font(.cyber(15, .semibold)).foregroundStyle(CyberTheme.textPri)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CyberTheme.textFaint)
            }
            .padding(14)
            .background(GlowCard(glow: false)) {}
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 人设面板
struct PersonaPanel: View {
    @Environment(AppServices.self) private var services
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "助理人设（整段自由文本）", icon: "person.crop.square")
                GlowCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $text)
                            .font(.cyber(13))
                            .foregroundStyle(CyberTheme.textPri)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                        Text("约 \(text.approxTokens) tokens")
                            .font(.cyber(10, mono: true))
                            .foregroundStyle(CyberTheme.textFaint)
                    }
                    .padding(14)
                }
                Button {
                    services.memory.personaText = text
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { saved = false } }
                } label: {
                    Label(saved ? "已保存" : "保存人设", systemImage: saved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
            }
            .padding(16)
        }
        .navigationTitle("助理人设")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { text = services.memory.personaText }
    }
}

// MARK: - 记忆面板
struct MemoryPanel: View {
    @Environment(AppServices.self) private var services
    @State private var newEntry: MemoryCardKind?
    @State private var entryText = ""
    @State private var deleteEntry: MemoryEntry?
    @State private var showDeleteEntry = false
    @State private var forgetText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: Binding(get: { services.memory.masterOn },
                                      set: { services.memory.masterOn = $0 })) {
                    Label("总开关（关闭后不再注入记忆）", systemImage: "power")
                        .font(.cyber(14, .semibold))
                        .foregroundStyle(CyberTheme.textPri)
                }
                .tint(CyberTheme.neonPink)
                .padding(12)
                .background(GlowCard(glow: false)) {}

                ForEach(MemoryCardKind.allCases, id: \.self) { kind in
                    if let card = services.memory.card(kind) {
                        CardSection(card: card,
                                     onAdd: { newEntry = kind; entryText = "" },
                                     onDelete: { deleteEntry = $0; showDeleteEntry = true })
                    }
                }

                SectionTitle(text: "自然语言管理", icon: "text.badge.checkmark")
                HStack {
                    TextField("如：删掉关于X的记忆", text: $forgetText)
                        .font(.cyber(13))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.neonPurple.opacity(0.4), lineWidth: 1))
                    Button {
                        _ = services.memory.forget(keyword: forgetText)
                        forgetText = ""
                    } label: {
                        Image(systemName: "trash.fill").font(.system(size: 14))
                    }
                    .buttonStyle(GhostButtonStyle(tint: CyberTheme.danger))
                    .disabled(forgetText.isBlank)
                }
            }
            .padding(16)
        }
        .navigationTitle("记忆四卡片")
        .navigationBarTitleDisplayMode(.inline)
        .alert("新增条目", isPresented: Binding(get: { newEntry != nil }, set: { if !$0 { newEntry = nil } })) {
            TextField("条目内容", text: $entryText)
            Button("取消", role: .cancel) { newEntry = nil }
            Button("添加") {
                if let kind = newEntry { _ = services.memory.addEntry(kind: kind, content: entryText) }
                newEntry = nil
            }.tint(CyberTheme.neonPink)
        }
        .destructiveConfirm(title: "删除条目",
                             message: "「\(deleteEntry?.content ?? "")」",
                             isPresented: $showDeleteEntry) {
            if let entry = deleteEntry { services.memory.delete(entry: entry) }
            deleteEntry = nil
        }
    }
}

private struct CardSection: View {
    @Environment(AppServices.self) private var services
    let card: MemoryCard
    let onAdd: () -> Void
    let onDelete: (MemoryEntry) -> Void

    private var tint: Color {
        switch card.tint {
        case "pink": return CyberTheme.neonPink
        case "cyan": return CyberTheme.neonCyan
        case "purple": return CyberTheme.neonPurple
        case "gold": return CyberTheme.neonGold
        default: return CyberTheme.sakura
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: card.kind.icon).foregroundStyle(tint).font(.system(size: 14, weight: .semibold))
                Text(card.kind.title).font(.cyber(14, .bold)).foregroundStyle(CyberTheme.textPri)
                Spacer()
                Toggle("", isOn: Binding(get: { card.enabled }, set: { card.enabled = $0; try? services.context.save() }))
                    .tint(tint).labelsHidden()
            }
            Text(card.kind.hint).font(.cyber(10)).foregroundStyle(CyberTheme.textFaint)

            if card.kind == .persona {
                Text(card.personaText ?? "").font(.cyber(12)).foregroundStyle(CyberTheme.textSec)
                    .lineLimit(3)
            } else {
                ForEach(card.sortedEntries) { entry in
                    HStack(alignment: .top) {
                        Text("·").foregroundStyle(tint)
                        Text(entry.content).font(.cyber(12)).foregroundStyle(CyberTheme.textSec)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { onDelete(entry) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                                .foregroundStyle(CyberTheme.textFaint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button(action: onAdd) {
                Label("新增", systemImage: "plus.circle.fill")
                    .font(.cyber(12, .medium))
                    .foregroundStyle(tint)
            }
        }
        .padding(12)
        .background(GlowCard(glow: false)) {}
    }
}

// MARK: - 技能面板
struct SkillPanel: View {
    @Environment(AppServices.self) private var services
    @State private var showEditor = false
    @State private var editingSkill: Skill?
    @State private var showImport = false
    @State private var shareItems: [Any]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "内置与自定义技能", icon: "wand.and.stars")
                ForEach(services.skills.all()) { skill in
                    SkillRow(skill: skill,
                             onToggle: { skill.enabled.toggle(); try? services.context.save() },
                             onEdit: { editingSkill = skill; showEditor = true },
                             onExport: {
                                 if let url = services.skills.exportURL(for: skill) {
                                     shareItems = [url]
                                 }
                             },
                             onDelete: { services.skills.delete(skill) })
                }
                Button {
                    editingSkill = nil; showEditor = true
                } label: {
                    Label("新建技能", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
                Button {
                    showImport = true
                } label: {
                    Label("导入技能（JSON）", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle(tint: CyberTheme.neonCyan))
            }
            .padding(16)
        }
        .navigationTitle("技能")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            SkillEditor(skill: editingSkill)
                .environment(services)
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems {
                ActivityShareSheet(items: items)
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               case .success = services.skills.importSkill(from: data) {
                // 导入成功
            }
        }
    }
}

private struct SkillRow: View {
    let skill: Skill
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    @State private var showDelete = false

    var body: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: skill.isBuiltin ? "sparkles" : "wand.and.stars")
                        .foregroundStyle(skill.enabled ? CyberTheme.neonCyan : CyberTheme.textFaint)
                    Text(skill.name).font(.cyber(14, .bold)).foregroundStyle(CyberTheme.textPri)
                    if skill.isBuiltin { TagChip(text: "内置", color: CyberTheme.neonGold) }
                    Spacer()
                    Toggle("", isOn: Binding(get: { skill.enabled }, set: { _ in onToggle() }))
                        .tint(CyberTheme.neonPink).labelsHidden()
                }
                if !skill.descText.isBlank {
                    Text(skill.descText).font(.cyber(11)).foregroundStyle(CyberTheme.textSec)
                }
                HStack {
                    Button("编辑", action: onEdit).font(.cyber(11, .medium)).foregroundStyle(CyberTheme.neonCyan)
                    Button("导出", action: onExport).font(.cyber(11, .medium)).foregroundStyle(CyberTheme.neonGold)
                    Button("删除", role: .destructive) { showDelete = true }
                        .font(.cyber(11, .medium)).foregroundStyle(CyberTheme.danger)
                        .disabled(skill.isBuiltin)
                }
            }
            .padding(12)
        }
        .destructiveConfirm(title: "删除技能", message: "删除「\(skill.name)」？",
                             isPresented: $showDelete, action: onDelete)
    }
}

struct SkillEditor: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let skill: Skill?

    @State private var name = ""
    @State private var desc = ""
    @State private var triggers = ""
    @State private var prompt = ""
    @State private var steps = ""

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Field("名称") { TextField("如：长文阅读", text: $name).font(.cyber(14)) }
                        Field("描述") { TextField("技能用途", text: $desc).font(.cyber(14)) }
                        Field("触发词（逗号分隔）") { TextField("如：读长文, 总结长文", text: $triggers).font(.cyber(14)) }
                        Field("提示词模板") {
                            TextEditor(text: $prompt)
                                .font(.cyber(12))
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                        }
                        Field("流程步骤（每行一步）") {
                            TextEditor(text: $steps)
                                .font(.cyber(12))
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(16)
                }
                .navigationTitle(skill == nil ? "新建技能" : "编辑技能")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }.foregroundStyle(CyberTheme.textFaint)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            let triggerArr = triggers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            let stepArr = steps.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                            if let s = skill {
                                s.name = name; s.descText = desc
                                s.triggers = triggerArr; s.promptTemplate = prompt
                                s.steps = stepArr
                                try? services.context.save()
                            } else {
                                _ = services.skills.create(name: name, desc: desc, triggers: triggerArr,
                                                            prompt: prompt, steps: stepArr)
                            }
                            dismiss()
                        }.foregroundStyle(CyberTheme.neonPink).disabled(name.isBlank)
                    }
                }
            }
        }
        .onAppear {
            if let s = skill {
                name = s.name; desc = s.descText
                triggers = s.triggers.joined(separator: ",")
                prompt = s.promptTemplate
                steps = s.steps.joined(separator: "\n")
            }
        }
    }

    @ViewBuilder
    private func Field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.cyber(11, .bold)).foregroundStyle(CyberTheme.textSec)
            content()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.stroke.opacity(0.6), lineWidth: 1))
        }
    }
}

// MARK: - 模型面板
struct ModelPanel: View {
    @Environment(AppServices.self) private var services
    @State private var showAdd = false
    @State private var presetIdx = 0
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var models = ""
    @State private var isLocal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "已配置接口", icon: "server.rack")
                ForEach(services.modelStore.providers) { provider in
                    GlowCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: provider.isLocal ? "internaldrive" : "network")
                                    .foregroundStyle(CyberTheme.neonCyan)
                                Text(provider.name).font(.cyber(14, .bold)).foregroundStyle(CyberTheme.textPri)
                                Spacer()
                                if provider.isActive { TagChip(text: "当前", color: CyberTheme.neonPink) }
                            }
                            Text(provider.baseURL).font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                            Text("\(provider.models.count) 个模型").font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textSec)
                            HStack {
                                Button("设为当前") { services.modelStore.setActive(provider) }
                                    .font(.cyber(11, .medium)).foregroundStyle(CyberTheme.neonCyan)
                                    .disabled(provider.isActive)
                                Button("删除", role: .destructive) { services.modelStore.deleteProvider(provider) }
                                    .font(.cyber(11, .medium)).foregroundStyle(CyberTheme.danger)
                            }
                        }
                        .padding(12)
                    }
                }
                Button { showAdd = true } label: {
                    Label("添加接口", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
            }
            .padding(16)
        }
        .navigationTitle("模型配置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AddProviderSheet(presetIdx: $presetIdx, name: $name, baseURL: $baseURL,
                              apiKey: $apiKey, models: $models, isLocal: $isLocal)
                .environment(services)
                .presentationDetents([.large])
        }
    }
}

private struct AddProviderSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Binding var presetIdx: Int
    @Binding var name: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var models: String
    @Binding var isLocal: Bool

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "快捷预设", icon: "bolt.fill")
                        Picker("预设", selection: $presetIdx) {
                            ForEach(ModelStore.presets.indices, id: \.self) { i in
                                Text(ModelStore.presets[i].name).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(CyberTheme.neonCyan)
                        .onChange(of: presetIdx) { _, idx in
                            let p = ModelStore.presets[idx]
                            name = p.name; baseURL = p.baseURL
                            models = p.models.joined(separator: ",")
                            isLocal = p.name.contains("本地")
                        }

                        Field("名称") { TextField("接口名称", text: $name).font(.cyber(14)) }
                        Field("Base URL") { TextField("https://…/v1", text: $baseURL).font(.cyber(14))
                            .textInputAutocapitalization(.never).autocorrectionDisabled() }
                        Field("API Key（加密存储）") {
                            SecureField("sk-…", text: $apiKey).font(.cyber(14))
                        }
                        Field("模型列表（逗号分隔，可后续补）") {
                            TextField("model-a, model-b", text: $models).font(.cyber(14))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        Toggle("本地小模型（Ollama 等）", isOn: $isLocal)
                            .tint(CyberTheme.neonPink)
                            .font(.cyber(13, .semibold))
                            .foregroundStyle(CyberTheme.textPri)
                    }
                    .padding(16)
                }
                .navigationTitle("添加接口")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }.foregroundStyle(CyberTheme.textFaint)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            let modelArr = models.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isBlank }
                                .map { ModelInfo(id: $0, name: $0, supportsTools: true) }
                            _ = services.modelStore.addProvider(name: name.isBlank ? "未命名" : name,
                                                                  baseURL: baseURL, apiKey: apiKey,
                                                                  isLocal: isLocal, models: modelArr)
                            dismiss()
                        }.foregroundStyle(CyberTheme.neonPink).disabled(baseURL.isBlank)
                    }
                }
            }
        }
        .onAppear {
            if name.isBlank {
                let p = ModelStore.presets[presetIdx]
                name = p.name; baseURL = p.baseURL
                models = p.models.joined(separator: ",")
                isLocal = p.name.contains("本地")
            }
        }
    }

    @ViewBuilder
    private func Field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.cyber(11, .bold)).foregroundStyle(CyberTheme.textSec)
            content()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.stroke.opacity(0.6), lineWidth: 1))
        }
    }
}

// MARK: - 偏好面板
struct PreferencesPanel: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "对话偏好", icon: "gearshape.2")
                Toggle("智能路由（按任务自动选模型）", isOn: Binding(get: { services.prefs.smartRouter }, set: { services.prefs.smartRouter = $0 }))
                    .tint(CyberTheme.neonPink).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri)
                Toggle("自动知识库检索（@ 可覆盖）", isOn: Binding(get: { services.prefs.autoRAG }, set: { services.prefs.autoRAG = $0 }))
                    .tint(CyberTheme.neonPink).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri)
                Toggle("联网搜索默认开启", isOn: Binding(get: { services.prefs.webDefaultOn }, set: { services.prefs.webDefaultOn = $0 }))
                    .tint(CyberTheme.neonPink).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri)

                SectionTitle(text: "上下文压缩", icon: "rectangle.compress.vertical")
                VStack(alignment: .leading, spacing: 4) {
                    Text("触发阈值 \(services.prefs.compressThreshold) tokens").font(.cyber(11, .medium)).foregroundStyle(CyberTheme.textSec)
                    Slider(value: Binding(get: Double(services.prefs.compressThreshold),
                                          set: { services.prefs.compressThreshold = Int($0) }),
                           in: 8000...100000, step: 1000).tint(CyberTheme.neonPink)
                }

                SectionTitle(text: "视觉", icon: "wand.and.stars")
                Toggle("樱花花瓣", isOn: Binding(get: { services.prefs.petalsOn }, set: { services.prefs.petalsOn = $0 }))
                    .tint(CyberTheme.neonPink).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri)
                Toggle("霓虹辉光", isOn: Binding(get: { services.prefs.glowOn }, set: { services.prefs.glowOn = $0 }))
                    .tint(CyberTheme.neonPink).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri)

                SectionTitle(text: "联网搜索接口", icon: "magnifyingglass.circle")
                VStack(alignment: .leading, spacing: 6) {
                    TextField("搜索端点", text: Binding(get: { services.prefs.searchEndpoint }, set: { services.prefs.searchEndpoint = $0 }))
                        .font(.cyber(12, mono: true))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.stroke.opacity(0.6), lineWidth: 1))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("API Key（可选）", text: Binding(get: { services.prefs.searchKey }, set: { services.prefs.searchKey = $0 }))
                        .font(.cyber(12, mono: true))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.stroke.opacity(0.6), lineWidth: 1))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .padding(16)
        }
        .navigationTitle("偏好设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 备份面板
struct BackupPanel: View {
    @Environment(AppServices.self) private var services
    @State private var includeKeys = true
    @State private var passphrase = ""
    @State private var showRestore = false
    @State private var shareItems: [Any]?
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: "全量备份与恢复", icon: "arrow.up.arrow.down.circle")
                Toggle("包含模型密钥", isOn: $includeKeys)
                    .tint(CyberTheme.neonPink).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri)
                Field("加密口令（可选，留空则不加密）") {
                    SecureField("口令", text: $passphrase).font(.cyber(14))
                }

                Button {
                    busy = true
                    do {
                        let url = try services.backup.export(includeKeys: includeKeys, passphrase: passphrase)
                        status = "已导出 \(url.lastPathComponent)，可在文件 App 中查看或分享"
                        shareItems = [url]
                    } catch {
                        status = "导出失败：\(error.localizedDescription)"
                    }
                    busy = false
                } label: {
                    Label("导出备份（生成 + 分享）", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
                .disabled(busy)

                Button {
                    showRestore = true
                } label: {
                    Label("从备份恢复", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle(tint: CyberTheme.neonCyan))
                .disabled(busy)

                if !status.isBlank {
                    Text(status).font(.cyber(11)).foregroundStyle(CyberTheme.textSec).padding(8)
                }
            }
            .padding(16)
        }
        .navigationTitle("备份与导出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems {
                ActivityShareSheet(items: items)
            }
        }
        .fileImporter(isPresented: $showRestore, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                busy = true
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let summary = try services.backup.restore(from: url, passphrase: passphrase)
                    status = summary
                } catch {
                    status = "恢复失败：\(error.localizedDescription)"
                }
                busy = false
            case .failure(let err):
                status = "导入失败：\(err.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func Field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.cyber(11, .bold)).foregroundStyle(CyberTheme.textSec)
            content()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.stroke.opacity(0.6), lineWidth: 1))
        }
    }
}
