//  ExportToast —— 作品导出/保存的统一成功反馈组件。
//
//  创作页（宠物卡片、成长对比、时间线长图等）保存到相册后需要明确的成功提示，
//  避免用户无法确认是否保存成功。BeadViewModel 自带 toast 体系（BeadToastMessage），
//  其余页面无独立 VM，用本组件 + .exportToast 修饰器以最少代码获得一致的反馈：
//  半透明胶囊（图标 + 文案）+ 成功触感，2.5s 自动消失。

import SwiftUI

private let exportToastDuration: Duration = .seconds(2.5)

/// 导出反馈胶囊视图（成功 / 失败两态）。
struct ExportToastView: View {
    enum Kind {
        case success, failure
    }

    let kind: Kind
    let message: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: Sizing.iconMd))
            Text(message)
                .font(.bodySecondary.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            Capsule().fill(kind == .success ? Color.milensSuccess : Color.milensDanger)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 消息类型

/// 导出反馈消息（成功 / 失败 + 文案）。作为 `.exportToast` 的状态值。
struct ExportToastMessage: Equatable {
    let kind: ExportToastView.Kind
    let text: String

    /// 快捷构造成功反馈消息。
    static func success(_ text: String) -> ExportToastMessage {
        .init(kind: .success, text: text)
    }

    /// 快捷构造失败反馈消息。
    static func failure(_ text: String) -> ExportToastMessage {
        .init(kind: .failure, text: text)
    }
}

// MARK: - View 修饰器

private struct ExportToastModifier: ViewModifier {
    /// 非空时显示胶囊，nil 时隐藏。2.5s 后自动置 nil（由调用方持有状态）。
    @Binding var message: ExportToastMessage?

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: message) { _, new in
                guard let new else { return false }
                return new.kind == .success
            }
            .sensoryFeedback(.error, trigger: message) { _, new in
                guard let new else { return false }
                return new.kind == .failure
            }
            .overlay(alignment: .top) {
                if let message {
                    ExportToastView(kind: message.kind, message: message.text)
                        .padding(.top, Spacing.xl)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message) {
                            do {
                                try await Task.sleep(for: exportToastDuration)
                            } catch {
                                return  // 视图销毁或新 toast 触发
                            }
                            self.message = nil
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: message)
    }
}

extension View {
    /// 绑定一个可空的导出反馈消息：非空时在顶部显示胶囊 + 触感，2.5s 自动清除。
    /// 用法：
    /// ```
    /// @State private var exportToast: ExportToastMessage?
    /// // ...
    /// .exportToast($exportToast)
    /// // 触发：exportToast = .success("已保存到相册")
    /// ```
    func exportToast(_ message: Binding<ExportToastMessage?>) -> some View {
        modifier(ExportToastModifier(message: message))
    }
}
