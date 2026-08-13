//  AlbumScanStageView —— 扫描中 / 导入中状态页（对照 Figma 01·扫描中 #29 / 04·导入中 #32）。
//  通过 isImport 区分文案与步骤：扫描 = 浏览相册筛选候选；导入 = 写入档案缩略图。
//  Local Scan Stage 暗底画布 + 扫描线动画 + Phase Badge + 进度条 + 步骤列表 + 停止/取消按钮。

import SwiftUI

struct AlbumScanStageView: View {
    @Bindable var vm: GalleryViewModel
    let isImport: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var scanLineOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                localScanStage
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xl)

                // 进度文本
                Text(isImport ? "正在把照片写入档案" : "正在寻找可能属于伙伴的照片")
                    .font(.titleStandard)
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)

                Text(isImport
                     ? "复制原片并建立缩略图，全程不离开设备。"
                     : "只读取缩略图；候选仍需要你逐张确认。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, 4)

                // 进度条
                progressBar
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)

                // 步骤标题
                Text(isImport ? "归档记录" : "扫描记录")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xl)

                // 步骤列表
                scanSteps
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)

                // 停止/取消按钮
                Button {
                    if isImport {
                        // 取消导入任务（ImportService 检测取消后优雅中断当前照片，
                        // 已写文件不丢弃），再关闭页面。
                        vm.cancelImport()
                        dismiss()
                    } else {
                        vm.cancelScan()
                        dismiss()
                    }
                } label: {
                    Text(isImport ? "取消导入" : "停止扫描")
                        .font(.uiBodyStrong)
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
                .padding(.top, Spacing.xl)
            }
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Local Scan Stage（对照 #29:10 / #32:19）

    private var localScanStage: some View {
        ZStack {
            // 暗色画布底
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.milensInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.milensDarkroomBorder, lineWidth: 1)
                )

            // 来源照片底（占位用纯色 + 缩略图）
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.milensStudioSurface)

            // Dark Wash 半透明覆盖
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.milensInk.opacity(0.28))

            // Candidate Window 虚线框
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.milensActionPrimary,
                        style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
                .opacity(0.72)
                .padding(58)

            // 扫描线
            scanLine

            // Phase Badge
            VStack {
                Spacer()
                phaseBadge
                    .padding(.bottom, 26)
            }
        }
        .frame(height: 350)
    }

    // MARK: - Phase Badge（对照 #29:15）

    private var phaseBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.milensPrimary)
                .frame(width: 8, height: 8)
            Text(isImport ? "写入本地档案 · \(vm.lastImportResult?.imported ?? 0) 张"
                 : "本地浏览 · 正在筛选候选")
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
    }

    // MARK: - 扫描线（对照 #29:14）

    private var scanLine: some View {
        GeometryReader { geo in
            let lineWidth = geo.size.width - 148
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: lineWidth, height: 2)
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

    // MARK: - 进度条（对照 #29:20-21）

    private var progressBar: some View {
        let percent = isImport ? vm.importProgressPercent : vm.scanProgressPercent
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: geo.size.width * percent, height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .frame(height: 4)
    }

    // MARK: - 扫描/导入步骤（对照 #29:23 / #32:32）

    private var scanSteps: some View {
        let steps = isImport ? importSteps : scanStepData
        return VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                stepRow(index: idx, title: step.0, status: step.1, isLast: idx == steps.count - 1)
            }
        }
    }

    private var scanStepData: [(String, String)] {
        [
            ("读取相册缩略图", "已完成"),
            ("筛选可能含宠物的照片", "进行中"),
            ("等待你确认", "等待"),
        ]
    }

    private var importSteps: [(String, String)] {
        [
            ("复制原片", "已完成"),
            ("写入档案", "进行中"),
            ("生成缩略图索引", "等待"),
        ]
    }

    private func stepRow(index: Int, title: String, status: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                    .padding(.leading, 46)
                    .opacity(0.65)
            }
        }
    }
}
