//  BeadPatternView —— 拼豆工作室（UI-DESIGN.md §6.7，对应源端 BeadPatternPage.ets）。
//  上半屏实时预览 + 下半屏参数控制（BeadSettingsPanelView）：
//  首次生成前预览显示原图，生成后显示图纸预览；参数变化 300ms 防抖实时重渲染；
//  生成完成做模糊→清晰揭示动画（Reduce Motion 时直接替换）+ .success 触感。
//  导出走全屏预览（BeadPatternResultView，fullScreenCover）。
//  生成/导出编排在 BeadViewModel（@Observable），决策逻辑在 MiLensKit。

import SwiftUI
import MiLensKit

struct BeadPatternView: View {
    let photoID: UUID

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 是否处于 regular 宽度（iPad 竖屏 / 大尺寸横屏），启用双栏分栏。
    private var isRegularWidth: Bool { hSizeClass == .regular }

    @State private var vm: BeadViewModel?
    @State private var showOriginalImage = false
    @State private var originalImage: UIImage?
    @State private var showExport = false
    /// 揭示动画进行中（生成完成后预览由模糊渐入清晰）。
    @State private var isRevealing = false
    /// 参数变化防抖任务（UI-DESIGN.md §6.7：250–400ms 防抖）。
    @State private var regenerateTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let vm {
                studio(vm)
            } else {
                ProgressView()
                    .tint(Color.milensPrimary)
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showOriginalImage) {
            originalImageView
        }
        .fullScreenCover(isPresented: $showExport) {
            if let vm {
                NavigationStack {
                    BeadPatternResultView(vm: vm)
                }
            }
        }
        .task {
            if vm == nil {
                // 分层收敛：VM 由工厂组装（View 不再直连 Repository/推理服务）
                let vm = factory.makeBeadViewModel(isPro: entitlement.isPro)
                await vm.load(photoID: photoID)
                self.vm = vm
            }
        }
    }

    // MARK: - 工作室布局（上预览 / 下参数）

    private func studio(_ vm: BeadViewModel) -> some View {
        Group {
            if isRegularWidth {
                studioIPad(vm)
            } else {
                studioCompact(vm)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = vm.toastMessage {
                Text(beadToastText(message))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, isRegularWidth ? 20 : 60)
            }
        }
        // 参数变化实时重渲染：仅在已有图纸后自动再生成（首次生成由「生成拼豆图纸」按钮显式触发，
        // 避免进入页面即开始重计算）。
        .onChange(of: vm.settings) { _, _ in
            scheduleRegenerate(vm)
        }
        .onChange(of: entitlement.isPro) { _, isPro in
            vm.updateEntitlement(isPro: isPro)
        }
        .onChange(of: vm.phase) { old, new in
            handlePhaseChange(from: old, to: new)
        }
        .sensoryFeedback(.success, trigger: vm.phase) { _, new in
            new == .success
        }
    }

    // MARK: - iPhone 紧凑布局（上预览 / 下参数）

    private func studioCompact(_ vm: BeadViewModel) -> some View {
        VStack(spacing: 0) {
            studioHeader(vm)
            previewArea(vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 0.5)
            BeadSettingsPanelView(vm: vm) {
                showExport = true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - iPad 双栏分栏（对照 Figma #310:841 Adaptive Workspace）

    /// 左列（Source Workspace，408pt）：源上下文 + 预览区；
    /// 右列（Parameter Inspector，354pt）：参数检查器。中间 24pt 间距。
    private func studioIPad(_ vm: BeadViewModel) -> some View {
        let settingsPanel = BeadSettingsPanelView(vm: vm) {
            showExport = true
        }
        return VStack(spacing: 0) {
            studioHeader(vm)
            HStack(spacing: AdaptiveColumn.splitGap) {
                // 左列：源上下文 + 预览区
                ScrollView {
                    VStack(spacing: 16) {
                        settingsPanel.sourceContent
                                                   .frame(maxWidth: .infinity)
                        previewArea(vm)
                                                       .frame(minHeight: 400)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, Spacing.xxl)
                }
                .frame(width: AdaptiveColumn.studioSource)
                .scrollIndicators(.hidden)

                // 右列：参数检查器
                ScrollView {
                    VStack(spacing: 16) {
                        // 参数标题（对照 #310:924-925）
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PATTERN PARAMETERS")
                                .font(.custom("Jacques Francois", size: 10))
                                .tracking(0.4)
                                .foregroundStyle(Color.milensActionPrimary)
                            Text("图纸参数")
                                .font(.custom("LXGWWenKai-Regular", size: 26))
                                .foregroundStyle(Color.milensTextPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                        settingsPanel.inspectorContent
                    }
                    .padding(.bottom, Spacing.xxl)
                }
                .frame(width: AdaptiveColumn.studioInspector)
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, Spacing.xxl)
        }
    }

    private func studioHeader(_ vm: BeadViewModel) -> some View {
        WorkshopNavHeader(title: String(localized: "create.bead.studio")) {
            dismiss()
        } trailing: {
            Button {
                showOriginalImage = true
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: Sizing.iconMd, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }
            .disabled(vm.photoURI.isEmpty)
        }
    }

    // MARK: - 上半屏：实时预览

    private func previewArea(_ vm: BeadViewModel) -> some View {
        ZStack {
            Color.milensStudioSurface

            if vm.pattern != nil, let image = vm.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .blur(radius: isRevealing ? 18 : 0)
                    .padding(Spacing.lg)
                    .background(Color.milensPaper)
                    .padding(.horizontal, Spacing.xl)
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            } else {
                // 首次生成前：预览显示原图，并说明生成后这里会实时更新
                VStack(spacing: Spacing.sm) {
                    ThumbnailImage(path: vm.thumbnailPath.isEmpty ? vm.photoURI : vm.thumbnailPath)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.lg)
                    Text("原图预览 · 生成后这里会实时显示拼豆效果")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                        .padding(.bottom, Spacing.sm)
                }
            }

            if case .generating = vm.phase {
                generatingOverlay(vm)
            }
        }
        .clipped()
    }

    /// 生成中覆盖层（对照 Figma「12·拼豆生成」#91:366）。
    /// 暗色 Processing Visual（照片底 + 主体检测虚线框 + 扫描线 + Phase Badge） +
    /// 四步生成步骤 + 取消按钮。
    private func generatingOverlay(_ vm: BeadViewModel) -> some View {
        ZStack {
            Color.milensBackground

            ScrollView {
                VStack(spacing: 14) {
                    // Processing Visual（对照 #91:373-388）
                    processingVisual(vm)

                    // 标题 + 说明（对照 #91:389-390）
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "bead.generating.title"))
                            .font(.titleStandard)
                            .foregroundStyle(Color.milensTextPrimary)
                        Text(String(localized: "bead.generating.subtitle"))
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Progress Track（对照 #91:391）
                    progressTrack(vm)

                    // 显影记录标题（对照 #332:692）
                    Text(String(localized: "bead.generating.log"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 四步生成步骤（对照 #91:393-409）
                    generationSteps(vm)

                    // 取消按钮（仅首次生成）
                    if vm.pattern == nil {
                        Button {
                            vm.cancelGeneration()
                        } label: {
                            Text(String(localized: "bead.generating.cancel"))
                                .font(.bodyPrimary)
                                .foregroundStyle(Color.milensTextSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(Color.milensBorder)
                                        .frame(height: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Processing Visual（对照 #91:373-388）

    private func processingVisual(_ vm: BeadViewModel) -> some View {
        ZStack {
            // 暗色画布底
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.milensInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.milensDarkroomBorder, lineWidth: 1)
                )

            // 来源照片底（半透明）
            if !vm.thumbnailPath.isEmpty || !vm.photoURI.isEmpty {
                ThumbnailImage(path: vm.thumbnailPath.isEmpty ? vm.photoURI : vm.thumbnailPath)
                    .opacity(0.82)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            // 主体检测虚线框（对照 #91:376）
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.milensActionPrimary, style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
                .opacity(0.55)
                .padding(48)

            // 裁角标记（对照 #91:377-384）
            cropCornerMarks

            // 扫描线（对照 #91:385，珊瑚色 + 发光）
            scanLine

            // Phase Badge（对照 #91:386-388，暗底 + 珊瑚描边）
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 8, height: 8)
                    Text(beadPhaseTitle(vm.phase))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensDarkroomText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.milensDarkroomBadge)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.milensActionPrimary, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 26)
            }
        }
        .frame(height: 350)
    }

    /// 裁角标记（照片四角的 L 形标记，对照 #91:377-384）
    private var cropCornerMarks: some View {
        GeometryReader { geo in
            let w: CGFloat = 19
            let h: CGFloat = 2
            let padding: CGFloat = 58
            let x = geo.size.width - padding
            let y = geo.size.height - padding
            // 左上
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.milensActionPrimary).frame(width: w, height: h)
                    .padding(.leading, padding).padding(.top, padding)
                Rectangle().fill(Color.milensActionPrimary).frame(width: h, height: w)
                    .padding(.leading, padding).padding(.top, padding)
                // 右上
                Rectangle().fill(Color.milensActionPrimary).frame(width: w, height: h)
                    .padding(.leading, x - w).padding(.top, padding)
                Rectangle().fill(Color.milensActionPrimary).frame(width: h, height: w)
                    .padding(.leading, x).padding(.top, padding)
                // 左下
                Rectangle().fill(Color.milensActionPrimary).frame(width: w, height: h)
                    .padding(.leading, padding).padding(.top, y)
                Rectangle().fill(Color.milensActionPrimary).frame(width: h, height: w)
                    .padding(.leading, padding).padding(.top, y - w)
                // 右下
                Rectangle().fill(Color.milensActionPrimary).frame(width: w, height: h)
                    .padding(.leading, x - w).padding(.top, y)
                Rectangle().fill(Color.milensActionPrimary).frame(width: h, height: w)
                    .padding(.leading, x).padding(.top, y - w)
            }
        }
        .allowsHitTesting(false)
    }

    /// 扫描线（珊瑚色 + 发光效果，对照 #91:385）
    @State private var scanLineOffset: CGFloat = 0

    private var scanLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: geo.size.width - 148, height: 2)
                .shadow(color: Color.milensCopperGlow, radius: 4)
                .opacity(0.95)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .offset(x: 74, y: scanLineOffset)
                .onAppear {
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: true)) {
                        scanLineOffset = geo.size.height - 170
                    }
                }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Progress Track（对照 #91:391）

    private func progressTrack(_ vm: BeadViewModel) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: geo.size.width * generationProgress(vm), height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .frame(height: 4)
    }

    /// 从 phase 估算进度。
    private func generationProgress(_ vm: BeadViewModel) -> Double {
        guard case .generating = vm.phase else { return 0 }
        return 0.42 // Figma 示意值
    }

    // MARK: - 四步生成步骤（对照 #91:393-409）

    private func generationSteps(_ vm: BeadViewModel) -> some View {
        let steps: [(String, String)] = [
            (String(localized: "bead.generating.step1"), String(localized: "bead.step.done")),
            (String(localized: "bead.generating.step2"), String(localized: "bead.step.inProgress")),
            (String(localized: "bead.generating.step3"), String(localized: "bead.step.waiting")),
            (String(localized: "bead.generating.step4"), String(localized: "bead.step.waiting")),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                stepRow(index: idx, title: step.0, status: step.1, isLast: idx == steps.count - 1)
            }
        }
    }

    private func stepRow(index: Int, title: String, status: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // 步骤点 + 连接线
                ZStack {
                    Circle()
                        .fill(index == 0 ? Color.milensActionPrimary : Color.milensCard)
                        .overlay(
                            Circle()
                                .stroke(index <= 1 ? Color.milensActionPrimary : Color.milensBorder,
                                        lineWidth: index == 0 ? 1 : index == 1 ? 2 : 1)
                        )
                        .frame(width: 14, height: 14)
                    if index == 0 {
                        Text("\u{2713}")
                            .font(.editorialOverline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, alignment: .center)

                Text(title)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)

                Spacer()
                Text(status)
                    .font(.editorialMetadata)
                    .foregroundStyle(index <= 1 ? Color.milensActionPrimary : Color.milensTextSecondary)
            }
            .padding(.vertical, 14)

            if !isLast {
                // 连接线 + 分隔线
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                    .padding(.leading, 46)
                    .opacity(0.65)
            }
        }
    }

    // MARK: - 实时重渲染与揭示动画

    private func scheduleRegenerate(_ vm: BeadViewModel) {
        regenerateTask?.cancel()
        guard vm.pattern != nil else { return }
        regenerateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            vm.generate()
        }
    }

    private func handlePhaseChange(from old: BeadGenerationPhase, to new: BeadGenerationPhase) {
        guard new == .success, old != .success else { return }
        // Reduce Motion：直接替换，不做模糊揭示（UI-DESIGN.md §7）
        guard !reduceMotion else { return }
        isRevealing = true
        withAnimation(.easeOut(duration: Motion.durationNormal)) {
            isRevealing = false
        }
    }

    // MARK: - 查看原图

    private var originalImageView: some View {
        Group {
            if let originalImage {
                Image(uiImage: originalImage)
                    .resizable()
                    .scaledToFit()
                    .background(Color.black)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if originalImage == nil {
                originalImage = await loadOriginalImage()
            }
        }
    }

    private func loadOriginalImage() async -> UIImage? {
        guard let vm else { return nil }
        let path = vm.thumbnailPath.isEmpty ? vm.photoURI : vm.thumbnailPath
        guard !path.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: path)
        }.value
    }
}
