//  PetAssignmentSheet —— 宠物选择器（手动归属/移出的共享组件）。
//
//  用户手动纠正 AI 自动归属的唯一交互入口（P0 手动归属 UI）。
//  4 个调用方复用：PhotoViewView（单张）、Gallery contextMenu（单张）、
//  Gallery 多选批量、PetProfile 待整理分类。
//
//  模式：
//  - 单张（photos.count == 1）：标题"归属到宠物"
//  - 批量（photos.count > 1）：标题"归属 N 张照片"
//
//  当前共同归属的宠物标记 checkmark（所有照片归属同一只时才显示）。
//  底部"移出归属"调 assignPhotos(photos, to: nil)。

import SwiftUI

struct PetAssignmentSheet: View {
    /// 待归属的照片（1 张=单张模式；多张=批量模式）。
    let photos: [Photo]
    /// 归属完成后的回调（关闭 sheet + 调用方刷新）。
    let onAssigned: () -> Void

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss

    @State private var pets: [Pet] = []
    @State private var errorMessage: String?

    private var isBatch: Bool { photos.count > 1 }

    /// 当前共同归属的宠物 ID（仅当所有照片归属同一只宠物时才有值）。
    private var currentPetID: UUID? {
        let petIDs = Set(photos.compactMap { $0.pet?.id })
        return petIDs.count == 1 ? petIDs.first : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if pets.isEmpty {
                    emptyState
                } else {
                    petList
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "photo.assign.failed"),
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok")) { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
        .task { await loadPets() }
    }

    // MARK: - 标题

    private var navigationTitle: String {
        if isBatch {
            return String(localized: "photo.assign.batchTitle \(photos.count)")
        }
        return String(localized: "photo.assign.title")
    }

    // MARK: - 宠物列表

    private var petList: some View {
        List {
            Section {
                ForEach(pets) { pet in
                    Button {
                        assign(to: pet)
                    } label: {
                        petRow(pet, isCurrent: pet.id == currentPetID)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                Button(role: .destructive) {
                    assign(to: nil)
                } label: {
                    HStack {
                        Label(String(localized: "photo.assign.unassign"), systemImage: "minus.circle")
                        Spacer()
                    }
                    .foregroundStyle(Color.milensTextSecondary)
                }
            } footer: {
                Text(String(localized: "photo.assign.unassignHint"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
    }

    private func petRow(_ pet: Pet, isCurrent: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            // 头像（与 PetsView.PetCardRow 风格一致）
            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: 44, height: 44)
                if !pet.avatarPath.isEmpty {
                    ThumbnailImage(path: pet.avatarPath)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Text(PetProfileLogic.speciesEmoji(pet.species))
                        .font(.system(size: 22))
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(PetDisplayLogic.speciesDisplayName(pet.species))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            Spacer()

            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensActionPrimary)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - 空宠物态

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "photo.assign.empty"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 归属操作

    private func assign(to pet: Pet?) {
        do {
            _ = try factory.assignPhotos(photos, to: pet)
            onAssigned()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 数据加载

    @MainActor
    private func loadPets() async {
        do {
            pets = try factory.allPets()
        } catch {
            pets = []
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    PetAssignmentSheet(photos: []) { }
}
