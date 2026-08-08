//  EditorView —— 图片编辑器页面（对应源端 pages/EditorPage.ets）。
//  结构：自定义顶栏（返回/撤销/重做/保存）+ 画布（EditorCanvasView）+ 面板区 + 底部 dock。
//  依赖注入：Environment 取 photoRepo/fileStorage/visionService/mediaLifecycle，
//  sandboxDir 与导入同目录（Documents/MiPhotos，DESIGN.md §7 唯一入库路径）。
//  保存/返回决策全部走 EditorViewModel（EditorSaveLogic 驱动）。

import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.milens.app", category: "Editor")

struct EditorView: View {
    let photoID: UUID

    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.fileStorage) private var fileStorage
    @Environment(\.visionService) private var visionService
    @Environment(\.mediaLifecycleService) private var mediaLifecycleService
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: EditorViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard viewModel == nil else { return }
            let sandboxDir = URL.documentsDirectory
                .appendingPathComponent(ScanConfig.sandboxDirName)
                .path
            // 环境注入的 service 优先；缺失时走 in-memory 兜底，兜底失败则保持黑屏（不崩溃）。
            guard let mediaLifecycle = mediaLifecycleService ?? Self.fallbackLifecycle(
                photoRepo: photoRepo, fileStorage: fileStorage,
                sandboxDir: sandboxDir
            ) else { return }
            let vm = EditorViewModel(
                photoID: photoID,
                photoRepo: photoRepo,
                visionService: visionService,
                imageProcessor: CoreImageEditorProcessing(),
                saveService: EditorSaveService(
                    mediaLifecycle: mediaLifecycle,
                    sandboxDir: sandboxDir
                )
            )
            viewModel = vm
            await vm.load()
        }
    }

    // MARK: - 内容

    /// 环境未注入 MediaLifecycleService 时的兜底（Preview/异常路径）：in-memory 容器；
    /// 容器创建失败返回 nil，调用方保持黑屏而不崩溃。
    @MainActor
    private static func fallbackLifecycle(
        photoRepo: any PhotoRepositoryProtocol,
        fileStorage: any FileStorage,
        sandboxDir: String
    ) -> MediaLifecycleService? {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self), configurations: [config])
        } catch {
            logger.error("Editor fallback in-memory 容器创建失败: \(error, privacy: .public)")
            return nil
        }
        return MediaLifecycleService(
            photoRepo: photoRepo,
            petRepo: SwiftDataPetRepository(context: container.mainContext),
            fileStorage: fileStorage,
            sandboxDir: sandboxDir)
    }

    private func content(_ vm: EditorViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(vm)
            EditorCanvasView(viewModel: vm)
            EditorPanelArea(viewModel: vm)
            EditorDockView(viewModel: vm)
        }
        .background(.black)
        .onChange(of: vm.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .confirmationDialog(
            "保存编辑？",
            isPresented: Binding(
                get: { vm.showSaveChoice },
                set: { if !$0 { vm.dismissSaveChoice() } }
            ),
            titleVisibility: .visible
        ) {
            Button("保存并退出") { Task { await vm.saveAndBack() } }
            Button("仅保存") { Task { await vm.save() } }
            Button("取消", role: .cancel) { vm.dismissSaveChoice() }
        }
        .confirmationDialog(
            "有未保存的修改",
            isPresented: Binding(
                get: { vm.showBackConfirm },
                set: { if !$0 { vm.dismissBackConfirm() } }
            ),
            titleVisibility: .visible
        ) {
            Button("保存并退出") { Task { await vm.saveAndBack() } }
            Button("放弃修改", role: .destructive) { vm.discardAndBack() }
            Button("取消", role: .cancel) { vm.dismissBackConfirm() }
        }
        .alert(
            "无法继续",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.dismissError() } }
            )
        ) {
            Button("好", role: .cancel) { vm.dismissError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - 顶栏

    private func topBar(_ vm: EditorViewModel) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                vm.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Sizing.iconLg, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("返回")

            Spacer()

            topBarButton(icon: "arrow.uturn.backward", label: "撤销", enabled: vm.canUndo) { vm.undo() }
            topBarButton(icon: "arrow.uturn.forward", label: "重做", enabled: vm.canRedo) { vm.redo() }

            Button {
                vm.requestSave()
            } label: {
                Text("保存")
                    .font(Font.bodyPrimary.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                    .background(vm.isSaving ? Color.white.opacity(0.15) : Color.milensPrimary)
                    .clipShape(Capsule())
            }
            .disabled(vm.isSaving || vm.isPhotoLoading)
            .accessibilityLabel("保存")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.black)
        .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.15)) }
    }

    private func topBarButton(icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Sizing.iconLg))
                .foregroundStyle(enabled ? .white : .white.opacity(0.3))
                .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

#Preview {
    NavigationStack {
        EditorView(photoID: UUID())
    }
}
