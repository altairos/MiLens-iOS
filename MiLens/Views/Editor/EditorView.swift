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
                Color.milensBackground.ignoresSafeArea()
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
        .background(Color.milensBackground)
        .onChange(of: vm.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .confirmationDialog(
            String(localized: "editor.exit.dialog.saveTitle"),
            isPresented: Binding(
                get: { vm.showSaveChoice },
                set: { if !$0 { vm.dismissSaveChoice() } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "editor.exit.saveAndQuit")) { Task { await vm.saveAndBack() } }
            Button(String(localized: "editor.exit.saveOnly")) { Task { await vm.save() } }
            Button(String(localized: "common.cancel"), role: .cancel) { vm.dismissSaveChoice() }
        }
        .confirmationDialog(
            String(localized: "editor.exit.dialog.unsavedTitle"),
            isPresented: Binding(
                get: { vm.showBackConfirm },
                set: { if !$0 { vm.dismissBackConfirm() } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "editor.exit.saveAndQuit")) { Task { await vm.saveAndBack() } }
            Button(String(localized: "pet.edit.unsaved.discard"), role: .destructive) { vm.discardAndBack() }
            Button(String(localized: "common.cancel"), role: .cancel) { vm.dismissBackConfirm() }
        }
        .alert(
            String(localized: "editor.error.title"),
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.dismissError() } }
            )
        ) {
            Button(String(localized: "common.ok"), role: .cancel) { vm.dismissError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        // 装饰面板 Pro 锁定项 → 付费墙（开发计划 §3.4）：锁定素材点击由面板 VM 置 pendingPaywallItem，
        // isPro 由 EditorDecorationPanelView 从环境读取传入动作；sheet 关闭时复位意图，
        // 购买成功后可再次选择同一素材（规格 §4.2）。
        .sheet(isPresented: Binding(
            get: { vm.decorationVM.pendingPaywallItem != nil },
            set: { if !$0 { vm.decorationVM.clearPaywallIntent() } }
        )) {
            NavigationStack { PaywallView() }
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
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "a11y.editor.back"))

            Spacer()

            topBarButton(icon: "arrow.uturn.backward", label: String(localized: "a11y.editor.undo"), enabled: vm.canUndo) { vm.undo() }
            topBarButton(icon: "arrow.uturn.forward", label: String(localized: "a11y.editor.redo"), enabled: vm.canRedo) { vm.redo() }

            Button {
                vm.requestSave()
            } label: {
                Text("保存")
                    .font(Font.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                    .background(vm.isSaving ? Color.milensBorder : Color.milensActionPrimary)
                    .clipShape(Capsule())
            }
            .disabled(vm.isSaving || vm.isPhotoLoading)
            .accessibilityLabel(String(localized: "a11y.editor.save"))
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.milensBackground)
        .overlay(alignment: .bottom) { Divider().overlay(Color.milensSeparator) }
    }

    private func topBarButton(icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Sizing.iconLg))
                .foregroundStyle(enabled ? Color.milensTextPrimary : Color.milensTextTertiary)
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
