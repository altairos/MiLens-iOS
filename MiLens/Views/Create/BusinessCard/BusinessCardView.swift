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
    @State private var sharePreview: (image: UIImage, url: URL)?

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
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
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
        let filename = "business_card_\(pet.name).png"
        do {
            let url = try BeadExportService().writeShareCache(data: png, filename: filename)
            sharePreview = (image: rendered, url: url)
        } catch {
            logger.error("share: 写入分享缓存失败（\(error.localizedDescription)）")
        }
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

// MARK: - 名片排版（预览与导出共用）

/// 宠物名片版式：头像 + 名字 + 身份信息 + 标签胶囊 + 简介 + 主人称呼。
/// 字号与间距按画布宽度比例缩放（预览与导出同源）。
struct BusinessCardArtwork: View {
    let data: PetBusinessCardData
    var avatarImage: UIImage?
    var template: BusinessCardTemplate = .standard
    var includeWatermark: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch template {
            case .standard:
                standardLayout(w: w, h: h)
            case .elegant:
                elegantLayout(w: w, h: h)
            case .playful:
                playfulLayout(w: w, h: h)
            case .minimal:
                minimalLayout(w: w, h: h)
            }
        }
        .aspectRatio(
            Double(PetBusinessCardLogic.exportWidth) / Double(PetBusinessCardLogic.exportHeight),
            contentMode: .fit)
    }

    // MARK: - 标准（居中头像 + 信息列 + 标签）

    private func standardLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: w * 0.04) {
            Spacer(minLength: h * 0.06)

            avatarView(size: w * 0.28)

            Text(data.name)
                .font(.custom("LXGWWenKai-Regular", size: w * 0.08))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitleLine)
                .font(.system(size: w * 0.034, weight: .regular, design: .rounded))
                .foregroundStyle(Color.milensTextSecondary)

            if !data.tags.isEmpty {
                tagFlow(w: w)
            }

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.036, weight: .light, design: .rounded))
                    .foregroundStyle(Color.milensTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, w * 0.1)
            }

            Spacer()

            if !ownerLine.isEmpty {
                Text(ownerLine)
                    .font(.system(size: w * 0.03, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.bottom, h * 0.04)
            }

            watermarkIfIncluded(w: w)
        }
        .frame(width: w, height: h)
        .background(Color.milensCard)
    }

    // MARK: - 优雅（衬线留白 + 大号名字）

    private func elegantLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: w * 0.05) {
            Spacer(minLength: h * 0.1)

            Text(data.name)
                .font(.custom("LXGWWenKai-Regular", size: w * 0.12))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            avatarView(size: w * 0.22)

            Text(subtitleLine)
                .font(.system(size: w * 0.032, weight: .light, design: .serif))
                .foregroundStyle(Color.milensTextSecondary)
                .tracking(w * 0.005)

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.034, weight: .light, design: .serif))
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            watermarkIfIncluded(w: w)
        }
        .frame(width: w, height: h)
        .background(Color.milensCard)
    }

    // MARK: - 活泼（圆角彩底 + 标签网格）

    private func playfulLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: w * 0.035) {
            Spacer(minLength: h * 0.05)

            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: w * 0.32, height: w * 0.32)
                avatarView(size: w * 0.26)
            }

            Text("\(data.name) \u{1F43E}")
                .font(.custom("LXGWWenKai-Regular", size: w * 0.075))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitleLine)
                .font(.system(size: w * 0.032, weight: .medium, design: .rounded))
                .foregroundStyle(Color.milensTextSecondary)

            if !data.tags.isEmpty {
                tagFlow(w: w)
            }

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.034, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.milensTextPrimary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            watermarkIfIncluded(w: w)
        }
        .frame(width: w, height: h)
        .background(Color.milensCard)
    }

    // MARK: - 极简（纯文字）

    private func minimalLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: w * 0.03) {
            Spacer(minLength: h * 0.1)

            Text(data.name)
                .font(.custom("LXGWWenKai-Regular", size: w * 0.1))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(subtitleLine)
                .font(.system(size: w * 0.032, weight: .regular, design: .default))
                .foregroundStyle(Color.milensTextSecondary)

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.034, weight: .regular, design: .default))
                    .foregroundStyle(Color.milensTextPrimary)
            }

            if !data.tags.isEmpty {
                Text(data.tags.joined(separator: " · "))
                    .font(.system(size: w * 0.03, weight: .light, design: .default))
                    .foregroundStyle(Color.milensTextTertiary)
            }

            Spacer()

            if !ownerLine.isEmpty {
                Text(ownerLine)
                    .font(.system(size: w * 0.028, weight: .regular, design: .default))
                    .foregroundStyle(Color.milensTextTertiary)
            }

            watermarkIfIncluded(w: w)
        }
        .padding(.horizontal, w * 0.12)
        .frame(width: w, height: h, alignment: .topLeading)
        .background(Color.milensCard)
    }

    // MARK: - 共用组件

    @ViewBuilder
    private func avatarView(size: CGFloat) -> some View {
        if let avatarImage {
            Image(uiImage: avatarImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: size, height: size)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
    }

    private func tagFlow(w: CGFloat) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(data.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: w * 0.03, weight: .medium, design: .rounded))
                    .padding(.horizontal, w * 0.025)
                    .padding(.vertical, w * 0.012)
                    .background(Color.milensAccentSoft)
                    .foregroundStyle(Color.milensTextPrimary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, w * 0.08)
    }

    @ViewBuilder
    private func watermarkIfIncluded(w: CGFloat) -> some View {
        if includeWatermark {
            Text("MiLens")
                .font(.system(size: w * 0.026, weight: .medium, design: .rounded))
                .foregroundStyle(Color.milensTextTertiary)
                .padding(.bottom, w * 0.04)
        }
    }

    private var subtitleLine: String {
        PetBusinessCardLogic.subtitleLine(
            speciesName: data.speciesName, breed: data.breed,
            genderName: data.genderName, ageText: data.ageText)
    }

    private var ownerLine: String {
        PetBusinessCardLogic.ownerLine(data.ownerName)
    }
}

// MARK: - 简易流式布局（标签胶囊换行）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        _ = arrange(subviews: subviews, maxWidth: maxWidth, totalHeight: &totalHeight)
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var totalHeight: CGFloat = 0
        let positions = arrange(subviews: subviews, maxWidth: bounds.width, totalHeight: &totalHeight)
        for (index, position) in positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat, totalHeight: inout CGFloat) -> [(x: CGFloat, y: CGFloat)] {
        var positions: [(x: CGFloat, y: CGFloat)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append((x, y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight = y + rowHeight
        return positions
    }
}

#Preview {
    NavigationStack {
        BusinessCardView(petID: UUID())
    }
}
