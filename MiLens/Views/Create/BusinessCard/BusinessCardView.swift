//  BusinessCardView —— 宠物名片卡生成页（创作 Tab 新增项目）。
//
//  名片卡是信息导向的创作项目：身份信息（物种/品种/年龄）+ 性格标签 +
//  一句话简介 + 主人称呼。照片为辅（头像位）。
//  预览与导出共用 BusinessCardArtwork（同一排版，导出用 ImageRenderer 固定尺寸）。
//  V1 草稿按 petID 缓存到 UserDefaults（不持久化到 SwiftData，避免 schema 迁移）。
//  Pro 门控：免费可用 standard 模板（带水印），Pro 解锁全部模板 + 无水印。

import SwiftUI
import UIKit
import Photos
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "BusinessCard")

struct BusinessCardView: View {
    let petID: UUID

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var pet: Pet?
    @State private var avatarImage: UIImage?
    @State private var isLoading = true

    // 用户输入（草稿）
    @State private var tagline = ""
    @State private var ownerName = ""
    @State private var selectedTags: [String] = []

    // 模板
    @AppStorage("businessCardTemplate") private var selectedTemplateRaw: String = BusinessCardTemplate.standard.rawValue
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
        .navigationTitle("宠物名片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await saveToLibrary() }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving)

                Button {
                    share()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .disabled(isSaving)
            }
        }
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
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .sheet(isPresented: $showTemplatePaywall) {
            NavigationStack { PaywallView() }
        }
        .task { await load() }
        .onDisappear { saveDraft() }
    }

    // MARK: - 内容

    private func content(pet: Pet) -> some View {
        let data = buildData(pet: pet)
        return ScrollView {
            VStack(spacing: Spacing.lg) {
                BusinessCardArtwork(
                    data: data,
                    avatarImage: avatarImage,
                    template: resolvedTemplate,
                    includeWatermark: !entitlement.isPro
                )
                    .frame(maxWidth: 420)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(Color.milensBorder, lineWidth: 0.5)
                    }

                templateSelector

                editSection(pet: pet)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 模板选择器

    private var selectedTemplate: BusinessCardTemplate {
        BusinessCardTemplate(rawValue: selectedTemplateRaw) ?? .standard
    }

    private var resolvedTemplate: BusinessCardTemplate {
        BusinessCardTemplate.resolve(selectedTemplate, isPro: entitlement.isPro)
    }

    private var templateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(BusinessCardTemplate.allTemplates) { template in
                    templateChip(template)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func templateChip(_ template: BusinessCardTemplate) -> some View {
        let isSelected = selectedTemplate == template
        let isUsable = template.isUsable(isPro: entitlement.isPro)
        return Button {
            if isUsable {
                selectedTemplateRaw = template.rawValue
            } else {
                showTemplatePaywall = true
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Color.milensGrouped)
                        .frame(width: 56, height: 70)
                    Image(systemName: template.previewIcon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.milensTextSecondary)
                    if !isUsable {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(isSelected ? Color.milensActionPrimary : Color.clear, lineWidth: 2)
                }
                Text(template.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 编辑区

    @ViewBuilder
    private func editSection(pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 一句话简介
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("一句话简介")
                    .font(.bodyPrimary.weight(.medium))
                    .foregroundStyle(Color.milensTextPrimary)
                TextField("如：家里的开心果", text: $tagline, axis: .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tagline) { _, newValue in
                        if newValue.count > PetBusinessCardLogic.maxTaglineLength {
                            tagline = String(newValue.prefix(PetBusinessCardLogic.maxTaglineLength))
                        }
                    }
                Text("\(tagline.count)/\(PetBusinessCardLogic.maxTaglineLength)")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
            }

            // 主人称呼
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("主人称呼")
                    .font(.bodyPrimary.weight(.medium))
                    .foregroundStyle(Color.milensTextPrimary)
                TextField("如：小橘妈妈", text: $ownerName, axis: .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: ownerName) { _, newValue in
                        if newValue.count > PetBusinessCardLogic.maxOwnerNameLength {
                            ownerName = String(newValue.prefix(PetBusinessCardLogic.maxOwnerNameLength))
                        }
                    }
            }

            // 性格标签
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("性格标签（最多 \(PetBusinessCardLogic.maxTagCount) 个）")
                    .font(.bodyPrimary.weight(.medium))
                    .foregroundStyle(Color.milensTextPrimary)
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(PetBusinessCardLogic.availableTags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private func tagChip(_ tag: String) -> some View {
        let isSelected = selectedTags.contains(tag)
        let atLimit = selectedTags.count >= PetBusinessCardLogic.maxTagCount && !isSelected
        return Button {
            if isSelected {
                selectedTags.removeAll { $0 == tag }
            } else if !atLimit {
                selectedTags.append(tag)
            }
        } label: {
            Text(tag)
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

    // MARK: - 动作

    private func buildData(pet: Pet) -> PetBusinessCardData {
        let input = PetBusinessCardInput(
            id: pet.id,
            name: pet.name,
            speciesName: PetDisplayLogic.speciesDisplayName(pet.species),
            breed: pet.breed,
            genderName: PetDisplayLogic.genderDisplayName(pet.gender),
            ageText: PetDisplayLogic.ageText(from: pet.birthday),
            avatarPath: pet.avatarPath
        )
        return PetBusinessCardLogic.buildData(
            from: input, tags: selectedTags, tagline: tagline, ownerName: ownerName)
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
                .font(.system(size: 40))
                .foregroundStyle(Color.milensTextSecondary)
            Text("宠物加载失败")
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
