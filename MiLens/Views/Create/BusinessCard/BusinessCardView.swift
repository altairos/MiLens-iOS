//  BusinessCardView —— 宠物名片卡生成页（创作 Tab 新增项目）。
//
//  名片卡是信息导向的创作项目：身份信息（物种/品种/年龄）+ 性格标签 +
//  一句话简介 + 主人称呼。照片为辅（头像位）。
//  预览与导出共用 BusinessCardArtwork（同一排版，导出用 ImageRenderer 固定尺寸）。
//  V1 草稿按 petID 缓存到 UserDefaults（不持久化到 SwiftData，避免 schema 迁移）。
//  Pro 门控：免费可用 museum 模板（带水印），Pro 解锁全部模板 + 无水印。

import SwiftUI
import UIKit
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "BusinessCard")

/// 预设标签 key → 展示文本（动态 key 规范：NSLocalizedString 查 Localizable.xcstrings；
/// 未命中的旧中文草稿值原样返回，宽容保留为自定义标签）。
private func localizedTag(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct BusinessCardView: View {
    let petID: UUID

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var pet: Pet?
    @State private var avatarImage: UIImage?
    @State private var isLoading = true

    // 用户输入（草稿）。selectedTags 存预设标签 key（businesscard.tag.*）或自定义展示文本
    @State private var tagline = ""
    @State private var ownerName = ""
    @State private var selectedTags: [String] = []

    // 字段编辑 sheet
    @State private var editingField: EditableField? = nil

    // 模板
    @AppStorage("businessCardTemplate") private var selectedTemplateRaw: String = BusinessCardTemplate.museum.rawValue
    @State private var showTemplatePaywall = false

    // 导出/分享
    @State private var isSaving = false
    @State private var shareItem: ShareItem?
    @State private var saveError: String?
    @State private var sharePreview: (image: UIImage, url: URL, filename: String, spec: String)?

    private let petDraftPrefix = "businessCard.draft."

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if let pet {
                content(pet: pet)
            } else {
                loadFailedView
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: Binding<SharePreviewData?>(
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url, filename: $0.filename, spec: $0.spec) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                filename: data.filename,
                spec: data.spec,
                onDismiss: { sharePreview = nil }
            )
        }
        .alert(String(localized: "businessCard.saveFailed"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .sheet(isPresented: $showTemplatePaywall) {
            NavigationStack { PaywallView() }
        }
        .sheet(item: $editingField) { field in
            BusinessCardFieldEditorSheet(
                field: field,
                tagline: $tagline,
                ownerName: $ownerName,
                selectedTags: $selectedTags,
                ownerPlaceholder: ownerPlaceholder
            )
        }
        .task { await load() }
        .onDisappear { saveDraft() }
    }

    // MARK: - 可编辑字段标识

    enum EditableField: String, Identifiable {
        case tagline, owner, tags
        var id: String { rawValue }
    }

    // MARK: - 占位文案

    /// 照护人占位：优先用当前宠物名动态生成（如「如：小橘妈妈」），宠物名为空时回退通用示例。
    private var ownerPlaceholder: String {
        let name = pet?.name ?? ""
        return name.isEmpty
            ? String(localized: "field.owner.placeholder.fallback")
            : String(localized: "field.owner.placeholder \(name)")
    }

    // MARK: - 内容

    private func content(pet: Pet) -> some View {
        let data = buildData(pet: pet)
        return VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "create.businessCard.title")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 来源条
                    WorkshopSourceBar(
                        meta: String(localized: "source.businessCard.meta"),
                        label: "\(pet.name) · \(PetDisplayLogic.ageText(from: pet.birthday))",
                        onChange: { dismiss() }
                    ) {
                        if let avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.milensGrouped
                                .overlay(Image(systemName: "person.fill").foregroundStyle(Color.milensTextTertiary))
                        }
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.md)

                    // Overline + 规格
                    HStack {
                        EditorialOverline(text: String(localized: "businesscard.overline"))
                        Spacer()
                        Text(String(localized: "businesscard.spec"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.lg)

                    BusinessCardArtwork(
                        data: data,
                        avatarImage: avatarImage,
                        template: resolvedTemplate,
                        includeWatermark: !entitlement.isPro
                    )
                        .frame(maxWidth: 342)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                                .stroke(Color.milensBorder, lineWidth: 0.5)
                        }
                        .elevation(Elevation.medium)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.sm)

                    // 模板选择
                    Text(String(localized: "businesscard.selectTemplate"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xl)

                    templateRail
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xs)

                    // 字段编辑行
                    VStack(spacing: 0) {
                        WorkshopFieldRow(
                            label: String(localized: "field.tagline"),
                            value: tagline.isEmpty ? String(localized: "field.tagline.placeholder") : tagline,
                            onEdit: { editingField = .tagline }
                        )
                        WorkshopFieldRow(
                            label: String(localized: "field.owner"),
                            value: ownerName.isEmpty ? ownerPlaceholder : ownerName,
                            onEdit: { editingField = .owner }
                        )
                        WorkshopFieldRow(
                            label: String(localized: "field.tags"),
                            value: selectedTags.isEmpty ? String(localized: "field.tags.placeholder") : selectedTags.map(localizedTag).joined(separator: " / "),
                            onEdit: { editingField = .tags },
                            showsRule: false
                        )
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.lg)

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                CreationActionBar(
                    primaryLabel: String(localized: "action.saveShare"),
                    secondaryLabel: String(localized: "action.saveDraft"),
                    primaryAction: { share() },
                    secondaryAction: { Task { await saveToLibrary() } }
                )
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                .background(Color.milensBackground)
            }
        }
    }

    // MARK: - 模板选择器

    private var selectedTemplate: BusinessCardTemplate {
        BusinessCardTemplate(rawValue: selectedTemplateRaw) ?? .museum
    }

    private var resolvedTemplate: BusinessCardTemplate {
        BusinessCardTemplate.resolve(selectedTemplate, isPro: entitlement.isPro)
    }

    private var templateRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(BusinessCardTemplate.allTemplates.enumerated()), id: \.element.id) { index, template in
                    WorkshopTemplateTab(
                        index: String(format: "%02d", index + 1),
                        label: template.displayName,
                        state: templateState(template),
                        action: {
                            if template.isUsable(isPro: entitlement.isPro) {
                                selectedTemplateRaw = template.rawValue
                            } else {
                                showTemplatePaywall = true
                            }
                        }
                    )
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func templateState(_ template: BusinessCardTemplate) -> WorkshopTemplateState {
        if !template.isUsable(isPro: entitlement.isPro) { return .locked }
        return selectedTemplate == template ? .selected : .default
    }

    // MARK: - 动作

    private func buildData(pet: Pet) -> PetBusinessCardData {
        let input = PetBusinessCardInput(
            id: pet.id,
            name: pet.name,
            speciesName: PetDisplayLogic.speciesDisplayName(pet.species),
            breed: pet.breed,
            genderName: PetDisplayLogic.genderDisplayName(pet.gender),
            ageText: PetDisplayLogic.ageText(from: pet.birthday),
            avatarPath: pet.avatarPath,
            birthday: pet.birthday,
            profileCreatedAt: pet.createdAt
        )
        return PetBusinessCardLogic.buildData(
            from: input, tags: selectedTags.map(localizedTag), tagline: tagline, ownerName: ownerName)
    }

    private func renderCard(pet: Pet) -> UIImage? {
        let data = buildData(pet: pet)
        let w = PetBusinessCardLogic.exportWidth
        let h = PetBusinessCardLogic.exportHeight
        let artwork = BusinessCardArtwork(
            data: data,
            avatarImage: avatarImage,
            template: resolvedTemplate,
            includeWatermark: !entitlement.isPro
        )
            .frame(width: CGFloat(w), height: CGFloat(h))
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func saveToLibrary() async {
        guard let pet else { return }
        guard let rendered = renderCard(pet: pet) else {
            saveError = "名片渲染失败，请重试"
            return
        }
        guard let png = rendered.pngData() else {
            saveError = "图片编码失败，请重试"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: png)
        } catch {
            logger.error("saveToLibrary: 保存失败（\(error.localizedDescription)）")
            saveError = "保存到相册失败：\(error.localizedDescription)"
        }
    }

    private func share() {
        guard let pet else { return }
        guard let rendered = renderCard(pet: pet),
              let png = rendered.pngData() else { return }
        let filename = "MiLens_\(pet.name)_\(String(localized: "share.panel.title")).png"
        let spec = "\(PetBusinessCardLogic.exportWidth) × \(PetBusinessCardLogic.exportHeight) · PNG · \(formatByteCount(png.count))"
        do {
            let url = try BeadExportService().writeShareCache(data: png, filename: filename)
            sharePreview = (image: rendered, url: url, filename: filename, spec: spec)
        } catch {
            logger.error("share: 写入分享缓存失败（\(error.localizedDescription)）")
        }
    }

    /// 格式化字节数为可读字符串（KB/MB）。
    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - 加载失败

    private var loadFailedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)) // ui-token:ok 错误态装饰大图标
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "businesscard.loadFailed"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据

    @MainActor
    private func load() async {
        defer { isLoading = false }
        do {
            guard let found = try factory.pet(id: petID) else { return }
            pet = found
            loadDraft(petID: petID)
            // 加载头像
            if !found.avatarPath.isEmpty {
                let path = found.avatarPath
                avatarImage = await Task.detached(priority: .utility) {
                    UIImage(contentsOfFile: path)
                }.value
            }
        } catch {
            logger.error("load: 读取宠物失败（\(error.localizedDescription)）")
        }
    }

    // MARK: - 草稿（UserDefaults，按 petID 缓存）
    // tags 存预设标签 key（跨语言稳定，切换语言后选中态不受影响）；
    // 旧版中文草稿值原样保留为自定义展示文本（不做迁移，V1.0 未上架）。

    private func loadDraft(petID: UUID) {
        let defaults = UserDefaults.standard
        let key = petDraftPrefix + petID.uuidString
        let dict = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        tagline = dict["tagline"] ?? ""
        ownerName = dict["ownerName"] ?? ""
        selectedTags = dict["tags"]?.components(separatedBy: "\u{1F}") ?? []
    }

    private func saveDraft() {
        let defaults = UserDefaults.standard
        let key = petDraftPrefix + petID.uuidString
        let dict: [String: String] = [
            "tagline": tagline,
            "ownerName": ownerName,
            "tags": selectedTags.joined(separator: "\u{1F}"),
        ]
        defaults.set(dict, forKey: key)
    }
}

#Preview {
    NavigationStack {
        BusinessCardView(petID: UUID())
    }
}

// MARK: - 名片字段编辑 Sheet（Figma 09 字段编辑）

/// 名片字段编辑 sheet：一句话 / 照护人 / 个性标签。
private struct BusinessCardFieldEditorSheet: View {
    let field: BusinessCardView.EditableField
    @Binding var tagline: String
    @Binding var ownerName: String
    @Binding var selectedTags: [String]
    let ownerPlaceholder: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    switch field {
                    case .tagline:
                        Text(String(localized: "field.tagline"))
                            .font(.uiBodyStrong)
                        TextField(String(localized: "field.tagline.placeholder"), text: $tagline, axis: .horizontal)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: tagline) { _, newValue in
                                if newValue.count > PetBusinessCardLogic.maxTaglineLength {
                                    tagline = String(newValue.prefix(PetBusinessCardLogic.maxTaglineLength))
                                }
                            }
                        Text("\(tagline.count)/\(PetBusinessCardLogic.maxTaglineLength)")
                            .font(.caption)
                            .foregroundStyle(Color.milensTextTertiary)

                    case .owner:
                        Text(String(localized: "field.owner"))
                            .font(.uiBodyStrong)
                        TextField(ownerPlaceholder, text: $ownerName, axis: .horizontal)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: ownerName) { _, newValue in
                                if newValue.count > PetBusinessCardLogic.maxOwnerNameLength {
                                    ownerName = String(newValue.prefix(PetBusinessCardLogic.maxOwnerNameLength))
                                }
                            }

                    case .tags:
                        Text("\(String(localized: "field.tags"))（最多 \(PetBusinessCardLogic.maxTagCount) 个）")
                            .font(.uiBodyStrong)
                        FlowLayout(spacing: Spacing.sm) {
                            ForEach(PetBusinessCardLogic.availableTagKeys, id: \.self) { key in
                                tagChip(key)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .navigationTitle(String(localized: "field.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.ok")) { dismiss() }
                }
            }
        }
    }

    /// chip 以 key 判定选中态（草稿与选中态均存 key），label 查表展示。
    private func tagChip(_ key: String) -> some View {
        let isSelected = selectedTags.contains(key)
        let atLimit = selectedTags.count >= PetBusinessCardLogic.maxTagCount && !isSelected
        return Button {
            if isSelected {
                selectedTags.removeAll { $0 == key }
            } else if !atLimit {
                selectedTags.append(key)
            }
        } label: {
            Text(localizedTag(key))
                .font(.caption.weight(.medium))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(isSelected ? Color.milensActionPrimary : Color.milensGrouped)
                .foregroundStyle(isSelected ? Color.white : (atLimit ? Color.milensTextTertiary : Color.milensTextSecondary))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(atLimit)
    }
}
