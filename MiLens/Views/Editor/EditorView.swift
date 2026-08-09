//  EditorView —— 图片编辑器页面（对应源端 pages/EditorPage.ets）。
//  结构：自定义顶栏（返回/撤销/重做/保存）+ 画布（EditorCanvasView）+ 面板区 + 底部 dock。
//  依赖注入：ViewModel 经 ViewModelFactory 构造（sandboxDir / 兜底语义在工厂内），
//  保存/返回决策全部走 EditorViewModel（EditorSaveLogic 驱动）。

import SwiftUI

struct EditorView: View {
    let photoID: UUID

    @Environment(\.viewModelFactory) private var factory
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
            // 工厂负责构造（含环境缺失时的 in-memory 兜底）；兜底失败返回 nil，保持黑屏（不崩溃）。
            guard let vm = factory.makeEditorViewModel(photoID: photoID) else { return }
            viewModel = vm
            await vm.load()
        }
    }

    // MARK: - 内容

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
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                    .background(vm.isSaving ? Color.white.opacity(0.15) : Color.milensActionPrimary)
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
