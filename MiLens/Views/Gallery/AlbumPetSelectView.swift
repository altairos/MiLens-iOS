//  AlbumPetSelectView —— 选择宠物档案页（对照 Figma 03·选择宠物 #27:5 / #31）。
//  Evidence Register（待归档照片缩略图 + 张数）+ Section 分隔 + Pet Archive Rows
//  （选中/未选中/新建）+ Import Register（本次导入 + 加入档案 + 配额提示）+ 底部 Action。

import SwiftUI

struct AlbumPetSelectView: View {
    @Bindable var vm: GalleryViewModel
    let selectedCount: Int
    @Binding var selectedPetID: UUID?
    let onConfirm: () -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    evidenceRegister
                    sectionDivider
                    petRows
                    importRegister
                }
                .padding(.bottom, 80)
            }

            bottomActionBar
        }
    }

    // MARK: - Evidence Register（对照 #31:14-23）

    private var evidenceRegister: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("待归档照片")
                    .font(.custom("Jacques Francois", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                    .padding(.top, 13)

                HStack(spacing: 6) {
                    // 前 4 张候选缩略图
                    ForEach(Array(vm.candidateURIs.prefix(4).enumerated()), id: \.element) { _, uri in
                        CandidateThumbnail(identifier: uri)
                            .frame(width: 52, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // 张数
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(selectedCount)")
                            .font(.numberStat)
                            .foregroundStyle(Color.milensTextPrimary)
                        Text("张")
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    .padding(.leading, 8)
                }
                .padding(.top, 13)
                .padding(.bottom, 16)
            }
            .padding(.leading, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
    }

    // MARK: - Section 分隔（对照 #31:24-26）

    private var sectionDivider: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("伙伴档案")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 84, height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 2)
        }
    }

    // MARK: - Pet Archive Rows（对照 #31:27-50）

    private var petRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.pets.enumerated()), id: \.element.id) { index, pet in
                petRow(pet: pet, index: index + 1)
            }
            // 新建伙伴档案行
            newPetRow
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    private func petRow(pet: Pet, index: Int) -> some View {
        let isSelected = selectedPetID == pet.id
        return Button {
            selectedPetID = isSelected ? nil : pet.id
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .topLeading) {
                    if isSelected {
                        Rectangle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 3, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 1))
                    }
                    Text(String(format: "%02d", index))
                        .font(.custom("Fraunces-Bold", size: 12))
                        .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextTertiary)
                        .padding(.leading, 10)
                }
                .frame(width: 24, alignment: .leading)

                // 头像
                Group {
                    if !pet.avatarPath.isEmpty {
                        ThumbnailImage(path: pet.avatarPath)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.milensGrouped)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(PetProfileLogic.speciesEmoji(pet.species))
                                    .font(.system(size: 28)) // ui-token:ok 头像占位 emoji
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(pet.name)
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text("\(PetDisplayLogic.speciesDisplayName(pet.species)) · \(pet.photoCount) 张照片")
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                }

                Spacer()

                Text(isSelected ? "已选择" : "\u{2192}")
                    .font(.bodySecondary)
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextTertiary)
                    .padding(.trailing, 12)
            }
            .frame(height: 84)
            .background(isSelected ? Color.milensAccentWash : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var newPetRow: some View {
        Button(action: onCreateNew) {
            HStack(spacing: 14) {
                Text("+")
                    .font(.custom("Fraunces-Bold", size: 12))
                    .foregroundStyle(Color.milensTextTertiary)
                    .frame(width: 24, alignment: .leading)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.milensGrouped)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text("\u{FF0B}")
                            .font(.system(size: 20, weight: .medium)) // ui-token:ok 新建占位字符
                            .foregroundStyle(Color.milensActionPrimary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("新建伙伴档案")
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text("由你填写名字和资料")
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                }

                Spacer()

                Text("\u{2192}")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.trailing, 12)
            }
            .frame(height: 84)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import Register（对照 #31:51-56）

    private var importRegister: some View {
        let petName = selectedPetID.flatMap { id in vm.pets.first { $0.id == id }?.name } ?? "新档案"
        let remainingAfter = max(0, CommercialRules.freePhotoLimit - vm.totalPhotoCount - selectedCount)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("本次导入")
                    .font(.custom("Jacques Francois", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                    .padding(.top, 16)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(selectedCount)")
                        .font(.numberStat)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text("加入「\(petName)」的档案")
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                .padding(.top, 7)

                Text("确认后才会写入；导入后免费额度 \(vm.totalPhotoCount + selectedCount) / \(CommercialRules.freePhotoLimit)")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
            .padding(.leading, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
    }

    // MARK: - 底部 Action（对照 #31:57）

    private var bottomActionBar: some View {
        let petName = selectedPetID.flatMap { id in vm.pets.first { $0.id == id }?.name } ?? "伙伴"
        let label = selectedPetID == nil
            ? "确认导入 · \(selectedCount) 张"
            : "确认并导入到\(petName)"
        return Button(action: onConfirm) {
            HStack {
                Text(label)
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
        .disabled(selectedCount == 0)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(Color.milensBackground)
    }
}
