//  BeadPatternView —— 拼豆图纸页（对应源端 BeadPatternPage.ets）。
//  三态：生成中（进度文案）→ 结果（BeadPatternResultView）/ 设置（BeadSettingsPanelView）。
//  生成/导出编排在 BeadViewModel（@Observable），决策逻辑在 MiLensKit。

import SwiftUI
import MiLensKit

struct BeadPatternView: View {
    let photoID: UUID

    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.visionService) private var vision
    @Environment(\.clipInferenceService) private var clipService

    @State private var vm: BeadViewModel?
    @State private var showOriginalImage = false
    @State private var originalImage: UIImage?

    var body: some View {
        Group {
            if let vm {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("拼豆图纸")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm, vm.pattern != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("查看原图") {
                        showOriginalImage = true
                    }
                }
            }
        }
        .sheet(isPresented: $showOriginalImage) {
            originalImageView
        }
        .task {
            if vm == nil {
                let vm = BeadViewModel(
                    photoRepo: photoRepo,
                    vision: vision,
                    clipService: clipService
                )
                await vm.load(photoID: photoID)
                self.vm = vm
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: BeadViewModel) -> some View {
        ZStack {
            Color.milensBackground.ignoresSafeArea()
            switch vm.phase {
            case .generating:
                generatingView(vm)
            case .success:
                if vm.pattern != nil {
                    BeadPatternResultView(vm: vm)
                } else {
                    BeadSettingsPanelView(vm: vm)
                }
            case .idle, .failure:
                BeadSettingsPanelView(vm: vm)
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
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: - 生成中（对应源端 isGenerating 分支）

    private func generatingView(_ vm: BeadViewModel) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.milensPrimary)
            Text(beadPhaseTitle(vm.phase))
                .font(.subheadline)
                .foregroundStyle(Color.milensTextSecondary)
            Text(beadPhaseSubtitle(vm.phase))
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
