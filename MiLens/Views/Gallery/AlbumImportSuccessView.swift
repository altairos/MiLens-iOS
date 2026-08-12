//  AlbumImportSuccessView —— 导入成功页（对照 Figma 05·导入成功 #27:7 / #33）。
//  Archive Entry Card（归档照片 + Paper 区 + Timeline 进度条）+ Local Archive Proof
//  （本地隐私证明）+ Privacy Register + 底部 Action。

import SwiftUI

struct AlbumImportSuccessView: View {
    let petName: String
    let count: Int
    let onViewPhotos: () -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                archiveEntryCard
                localArchiveProof
                    .padding(.top, 24)
                privacyNote
                    .padding(.top, 16)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
    }

    // MARK: - Archive Entry Card（对照 #33:15-26）

    private var archiveEntryCard: some View {
        VStack(spacing: 0) {
            // 归档照片区（占位）
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.milensGrouped)
                    .frame(height: 224)

                // Photo Shade 渐变
                Rectangle()
                    .fill(Color.milensInk.opacity(0.36))
                    .frame(height: 78)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // 日期标签
                Text("\(petName) · \(dateFormatter.string(from: Date()))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.milensDarkroomText)
                    .padding(.leading, 18)
                    .padding(.bottom, 16)
            }
            .frame(height: 224)

            // Paper 区（对照 #33:19-25）
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("LIFE LOG ARCHIVE")
                            .font(.custom("Jacques Francois", size: 10))
                            .tracking(0.4)
                            .foregroundStyle(Color.milensActionPrimary)
                            .padding(.top, 18)

                        Text("\(count) 张照片已归档")
                            .font(.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2))
                            .foregroundStyle(Color.milensTextPrimary)
                            .padding(.top, 8)

                        Text("已加入「\(petName)」的档案")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.milensTextSecondary)
                            .padding(.top, 4)

                        // Timeline 进度条
                        timelineBar
                            .padding(.top, 16)
                            .padding(.bottom, 22)
                    }
                    .padding(.leading, 13)
                    .padding(.trailing, 16)
                }
            }
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, Spacing.lg)
    }

    // MARK: - Timeline 进度条（对照 #33:24-26）

    private var timelineBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: geo.size.width * 0.92, height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .frame(height: 10)
    }

    // MARK: - Local Archive Proof（对照 #33:27-38）

    private var localArchiveProof: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("LOCAL ARCHIVE")
                    .font(.custom("Jacques Francois", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                    .padding(.top, 16)

                Text("只在这台设备上")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 8)

                Text("照片不会上传；已有内容也不会被移动。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 2)

                // 分隔线
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                    .padding(.top, 16)

                // 3 列统计
                HStack(spacing: 0) {
                    statColumn(value: String(format: "%02d", count), label: "原片")
                    Spacer()
                    statColumn(value: String(format: "%02d", count), label: "缩略图")
                    Spacer()
                    statColumn(value: "01", label: "伙伴")
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .padding(.leading, 13)
            .padding(.trailing, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.custom("Fraunces-Bold", size: 12))
                .foregroundStyle(Color.milensTextPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.top, 4)
        }
    }

    // MARK: - 隐私说明（对照 #33:39-40）

    private var privacyNote: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 196, height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            Text("归档完成 · 你仍可随时删除或重新分配照片")
                .font(.system(size: 12))
                .foregroundStyle(Color.milensTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - 底部 Action（对照 #33:41）

    private var bottomActionBar: some View {
        Button(action: onViewPhotos) {
            HStack {
                Text("查看\(petName)的照片")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.milensActionPrimary)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.milensActionPrimary, lineWidth: 1)
                        .frame(width: 42, height: 32)
                    Text("\u{2192}")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 5)
            .frame(height: 54)
            .background(Color.milensAccentWash)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(Color.milensBackground)
    }
}
