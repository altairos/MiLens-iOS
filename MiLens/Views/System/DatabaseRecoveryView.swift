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

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.milensTextSecondary)
            Text("本地数据无法加载")
                .font(.displayMedium)
            Text("打开本地相册记录时出现问题。您可以重试，或重建本地数据：清除 MiLens 记录，同时也会删除沙盒中已保存的照片副本（导入/编辑产物）。系统相册中的原图不受影响。")
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
                    Label("重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensPrimary)

                Button {
                    diagnosticsPath = Self.exportDiagnostics(error: errorDescription)
                } label: {
                    Label(diagnosticsPath == nil ? "导出诊断信息" : "诊断已导出", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showRebuildConfirm = true
                } label: {
                    Label("重建本地数据", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, Spacing.pagePad)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("重建本地数据？", isPresented: $showRebuildConfirm) {
            Button("取消", role: .cancel) {}
            Button("重建", role: .destructive) { onRebuild() }
        } message: {
            Text("将清除 MiLens 中的相册记录、宠物档案及沙盒中已保存的照片副本（导入/编辑产物），且无法恢复。系统相册中的原图不会被删除。")
        }
        .alert("诊断已导出", isPresented: Binding(
            get: { diagnosticsPath != nil },
            set: { if !$0 { diagnosticsPath = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(diagnosticsPath ?? "")
        }
    }

    /// 把启动错误写入 Documents/Diagnostics/ 日志文件（用户可从文件 App 访问）。
    private static func exportDiagnostics(error: String) -> String {
        let fm = FileManager.default
        let dir = URL.documentsDirectory.appendingPathComponent("Diagnostics")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("exportDiagnostics: 创建 Diagnostics 目录失败（\(error.localizedDescription)）")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = dir.appendingPathComponent("startup-error-\(formatter.string(from: Date())).log")
        let content = """
        MiLens 启动失败诊断
        时间：\(Date())
        错误：\(error)
        """
        do {
            try content.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            logger.error("exportDiagnostics: 写入诊断文件失败（\(error.localizedDescription)）")
        }
        return file.path
    }
}
