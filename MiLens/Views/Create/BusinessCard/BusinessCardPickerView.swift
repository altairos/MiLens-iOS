//  BusinessCardPickerView —— 宠物名片卡的选宠物页（创作 Tab 新增项目）。
//  从 CreateView「宠物名片」入口进入；选择一只宠物 → 进入 BusinessCardView 填写信息。
//  与 PetCardPhotoPickerView（选照片）不同：名片卡以宠物身份为主体，先选宠物再填信息。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "BusinessCard")

struct BusinessCardPickerView: View {
    @Environment(\.viewModelFactory) private var factory

    @State private var pets: [Pet] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensPrimary)
            } else if pets.isEmpty {
                emptyState
            } else {
                petList
            }
        }
        .background(Color.milensBackground)
        .navigationTitle("选择伙伴")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPets() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有伙伴档案",
            systemImage: "pawprint",
            description: Text("先到「伙伴」Tab 建立宠物档案，再来生成名片")
        )
    }

    // MARK: - 宠物列表

    private var petList: some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                ForEach(pets) { pet in
                    NavigationLink(value: Route.businessCard(petID: pet.id)) {
                        petRow(pet)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, Spacing.lg)
        }
    }

    @ViewBuilder
    private func petRow(_ pet: Pet) -> some View {
        HStack(spacing: Spacing.lg) {
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
                        .font(.system(size: 24))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(PetDisplayLogic.speciesDisplayName(pet.species))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.milensTextTertiary)
        }
        .padding(Spacing.md)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
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
