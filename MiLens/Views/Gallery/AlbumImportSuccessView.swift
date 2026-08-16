//  AlbumImportSuccessView —— 导入成功页（对照 Figma 05·导入成功 #27:7 / #33）。
//  Archive Entry Card（归档照片 + Paper 区 + Timeline 进度条）+ Local Archive Proof
//  （本地隐私证明）+ Privacy Register + 底部 Action。

import SwiftUI

struct AlbumImportSuccessView: View {
    let petName: String
    let count: Int
    let onViewPhotos: () -> Void

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

                // 日期标签（年月按系统 locale 格式化后再入本地化模板）
                Text(String(localized: "album.success.dateMark \(petName) \(Date().formatted(.dateTime.year().month()))"))
                    .font(.editorialMetadata)
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
                        Text(String(localized: "gallery.import.lifeLogMark"))
                            .font(.custom("JacquesFrancois-Regular", size: 10))
                            .tracking(0.4)
                            .foregroundStyle(Color.milensActionPrimary)
                            .padding(.top, 18)

                        Text(String(localized: "album.success.title \(count)"))
                            .font(.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2))
                            .foregroundStyle(Color.milensTextPrimary)
                            .padding(.top, 8)

                        Text(String(localized: "album.success.joined \(petName)"))
                            .font(.bodySecondary)
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
                Text(String(localized: "gallery.import.localMark"))
                    .font(.custom("JacquesFrancois-Regular", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                    .padding(.top, 16)

                Text(String(localized: "album.success.localTitle"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 8)

                Text(String(localized: "album.success.localBody"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 2)

                // 分隔线
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                    .padding(.top, 16)

                // 3 列统计
                HStack(spacing: 0) {
                    statColumn(value: String(format: "%02d", count), label: String(localized: "album.success.statOriginal"))
                    Spacer()
                    statColumn(value: String(format: "%02d", count), label: String(localized: "album.success.statThumbnail"))
                    Spacer()
                    statColumn(value: "01", label: String(localized: "album.success.statPet"))
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
                .font(.editorialMetadata)
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
            Text(String(localized: "album.success.privacyNote"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - 底部 Action（对照 #33:41）

    private var bottomActionBar: some View {
        Button(action: onViewPhotos) {
            HStack {
                Text(String(localized: "album.success.viewPhotos \(petName)"))
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensActionPrimary)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.milensActionPrimary, lineWidth: 1)
                        .frame(width: 42, height: 32)
                    Text("\u{2192}")
                        .font(.system(size: 20)) // ui-token:ok 装饰箭头字符
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
