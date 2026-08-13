//  BusinessCardPickerView —— 宠物名片卡的选宠物页（创作 Tab 新增项目）。
//  对照 Workshop 编辑式导航头（统一风格）。
//  从 CreateView「宠物名片」入口进入；选择一只宠物 → 进入 BusinessCardView 填写信息。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "BusinessCard")

struct BusinessCardPickerView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss

    @State private var pets: [Pet] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if pets.isEmpty {
                emptyState
            } else {
                petList
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPets() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "picker.businessCard.title")) { dismiss() }
            ContentUnavailableView(
                String(localized: "picker.businessCard.empty"),
                systemImage: "pawprint",
                description: Text(String(localized: "picker.businessCard.emptyDesc"))
            )
        }
    }

    // MARK: - 宠物列表

    private var petList: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "picker.businessCard.title")) { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "picker.businessCard.fromArchive"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)

                    VStack(spacing: 12) {
                        ForEach(pets) { pet in
                            NavigationLink(value: Route.businessCard(petID: pet.id)) {
                                petRow(pet)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func petRow(_ pet: Pet) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: 48, height: 48)
                if !pet.avatarPath.isEmpty {
                    ThumbnailImage(path: pet.avatarPath)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Text(PetProfileLogic.speciesEmoji(pet.species))
                        .font(.system(size: 24)) // ui-token:ok 头像占位 emoji
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(PetDisplayLogic.speciesDisplayName(pet.species))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            Spacer()

            Text("\u{2197}")
                .font(.uiTitle)
                .foregroundStyle(Color.milensActionPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.milensGrouped)
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 18, topTrailing: 8),
                style: .continuous
            )
            .stroke(Color.milensBorder, lineWidth: 1)
        }
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 18, topTrailing: 8),
            style: .continuous
        ))
    }

    // MARK: - 数据

    @MainActor
    private func loadPets() async {
        defer { isLoading = false }
        do {
            pets = try factory.allPets()
        } catch {
            logger.error("loadPets: 读取宠物列表失败（\(error.localizedDescription)）")
            pets = []
        }
    }
}
