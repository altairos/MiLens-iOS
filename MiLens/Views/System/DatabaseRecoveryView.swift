//  DatabaseRecoveryView —— 启动恢复界面（P1 启动可靠性）。
//  ModelContainer 创建失败时展示：可读错误信息 + 重试 + 导出诊断 +
//  「重建本地数据」（红色，二次确认——清除 MiLens 记录；DB 清空后启动孤儿审计
//  会连带删除沙盒 Documents/MiPhotos 中的照片副本（导入/编辑产物），
//  界面文案须明确提示此点；系统相册原图不受影响）。
//  对应源端暂无（HarmonyOS 启动失败无恢复 UI，iOS 首发补充）。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "DatabaseRecovery")

struct DatabaseRecoveryView: View {
    /// 启动失败的原始错误描述（可读化展示）
    let errorDescription: String
    /// 重试构造依赖
    let onRetry: () -> Void
    /// 重建本地数据（调用方负责销毁存储 + 重新构造）
    let onRebuild: () -> Void

    @State private var showRebuildConfirm = false
    @State private var diagnosticsPath: String?
    @State private var diagnosticsError: String?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48)) // ui-token:ok 错误态装饰大图标
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "recovery.title"))
                .font(.displayMedium)
            Text(String(localized: "recovery.body"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Text(errorDescription)
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.milensElevated, in: RoundedRectangle(cornerRadius: Radius.medium))

            VStack(spacing: Spacing.md) {
                Button(action: onRetry) {
                    Label(String(localized: "recovery.retry"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)

                Button {
                    switch Self.exportDiagnostics(error: errorDescription) {
                    case .success(let path):
                        diagnosticsPath = path
                        diagnosticsError = nil
                    case .failure(let error):
                        // 导出失败必须可见：不得仍显示「诊断已导出」
                        diagnosticsError = error.localizedDescription
                    }
                } label: {
                    Label(diagnosticsPath == nil
                          ? String(localized: "recovery.exportDiagnostics")
                          : String(localized: "recovery.diagnosticsExported"),
                          systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showRebuildConfirm = true
                } label: {
                    Label(String(localized: "recovery.rebuildData"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, Spacing.pagePad)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(String(localized: "recovery.rebuildConfirmTitle"), isPresented: $showRebuildConfirm) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "recovery.rebuild"), role: .destructive) { onRebuild() }
        } message: {
            Text(String(localized: "recovery.rebuildConfirmBody"))
        }
        .alert(String(localized: "recovery.diagnosticsExported"), isPresented: Binding(
            get: { diagnosticsPath != nil },
            set: { if !$0 { diagnosticsPath = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(diagnosticsPath ?? "")
        }
        .alert(String(localized: "recovery.exportFailed"), isPresented: Binding(
            get: { diagnosticsError != nil },
            set: { if !$0 { diagnosticsError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(diagnosticsError ?? "")
        }
    }

    /// 把启动错误写入 Documents/Diagnostics/ 日志文件（用户可从文件 App 访问）。
    /// 返回 Result：目录创建/文件写入任一失败都返回失败原因，界面不得显示「已导出」。
    private static func exportDiagnostics(error: String) -> Result<String, DiagnosticsExportError> {
        let fm = FileManager.default
        let dir = URL.documentsDirectory.appendingPathComponent("Diagnostics")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("exportDiagnostics: 创建 Diagnostics 目录失败（\(error.localizedDescription)）")
            return .failure(.createDirectory(error.localizedDescription))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = dir.appendingPathComponent("startup-error-\(formatter.string(from: Date())).log")
        let content = [
            String(localized: "recovery.diagHeader"),
            String(localized: "recovery.diagTime \(Date().formatted())"),
            String(localized: "recovery.diagError \(error)")
        ].joined(separator: "\n")
        do {
            try content.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            logger.error("exportDiagnostics: 写入诊断文件失败（\(error.localizedDescription)）")
            return .failure(.writeFile(error.localizedDescription))
        }
        return .success(file.path)
    }
}

/// 诊断导出失败原因（LocalizedError，界面直接展示 errorDescription）。
private enum DiagnosticsExportError: LocalizedError {
    case createDirectory(String)
    case writeFile(String)

    var errorDescription: String? {
        switch self {
        case .createDirectory(let detail): return String(localized: "recovery.diagCreateFailed \(detail)")
        case .writeFile(let detail): return String(localized: "recovery.diagWriteFailed \(detail)")
        }
    }
}
