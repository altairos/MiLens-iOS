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

    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.visionService) private var vision
    @Environment(\.clipInferenceService) private var clipService
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

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
        .background(Color.milensStudioBackground)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showOriginalImage) {
            originalImageView
        }
        .fullScreenCover(isPresented: $showExport) {
            if let vm {
                NavigationStack {
                    BeadPatternResultView(vm: vm)
                        .navigationTitle("拼豆图纸")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("完成") { showExport = false }
                            }
                        }
                }
            }
        }
        .task {
            if vm == nil {
                let vm = BeadViewModel(
                    photoRepo: photoRepo,
                    vision: vision,
                    clipService: clipService,
                    isPro: entitlement.isPro
                )
                await vm.load(photoID: photoID)
                self.vm = vm
            }
        }
    }

    // MARK: - 工作室布局（上预览 / 下参数）

    private func studio(_ vm: BeadViewModel) -> some View {
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
        .overlay(alignment: .bottom) {
            if let message = vm.toastMessage {
                Text(beadToastText(message))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 60)
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

    private func studioHeader(_ vm: BeadViewModel) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Sizing.iconMd, weight: .medium))
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }

            Spacer()

            Text("拼豆工作室")
                .font(.editorialSection)

            Spacer()

            Button {
                showOriginalImage = true
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: Sizing.iconMd, weight: .medium))
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }
            .disabled(vm.photoURI.isEmpty)
        }
        .foregroundStyle(Color.milensTextPrimary)
        .padding(.horizontal, Spacing.lg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
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
                    .padding(Spacing.md)
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

    /// 生成中覆盖层：可取消进度（UI-DESIGN.md §6.7）。
    /// 已有图纸时的实时再生成很快，且取消后 VM 会停留在 generating 相
    /// （cancelGeneration 只在无图纸时回到 idle），因此取消按钮仅在首次生成时提供。
    private func generatingOverlay(_ vm: BeadViewModel) -> some View {
        ZStack {
            Color.milensBackground.opacity(0.92)
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.milensPrimary)
                Text(beadPhaseTitle(vm.phase))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(beadPhaseSubtitle(vm.phase))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
                if vm.pattern == nil {
                    Button("取消") {
                        vm.cancelGeneration()
                    }
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(minHeight: Sizing.touchTarget)
                    .padding(.horizontal, Spacing.xl)
                    .background(Color.milensCard)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(Color.milensBorder, lineWidth: 0.5)
                    }
                    .padding(.top, Spacing.xs)
                }
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
