//  PetsView —— 宠物档案列表（Tab 2，对应源端 pages/PetProfilePage.ets 列表部分）。
//  P3 实现：宠物卡片列表（头像/名称/物种·年龄·性别/照片数·相处天数）+ 建档入口 + 彩蛋。
//  PetProfileViewModel（@Observable）驱动状态，决策通过 PetProfileLogic 纯函数。

import SwiftUI

struct PetsView: View {
    @Environment(\.petRepository) private var petRepo

    @State private var viewModel: PetProfileViewModel?
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = PetProfileViewModel(petRepo: petRepo)
                vm.loadPets()
                viewModel = vm
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let vm = viewModel {
                AddPetSheet(viewModel: vm)
            }
        }
        .overlay {
            if let vm = viewModel, vm.showEasterEgg {
                EasterEggOverlay { vm.showEasterEgg = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Motion.durationSlow), value: viewModel?.showEasterEgg)
    }

    // MARK: - 内容区

    @ViewBuilder
    private func content(_ vm: PetProfileViewModel) -> some View {
        if vm.isLoading {
            ProgressView()
        } else if vm.pets.isEmpty {
            emptyState(vm)
        } else {
            petList(vm)
        }
    }

    // MARK: - 空状态

    private func emptyState(_ vm: PetProfileViewModel) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.milensTextSecondary)
            Text("还没有伙伴档案")
                .font(.displayMedium)
            Text("点击下方按钮，添加第一个伙伴档案")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                vm.resetForm()
                showAddSheet = true
            } label: {
                Label("添加伙伴", systemImage: "plus")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.milensPrimary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 宠物列表

    private func petList(_ vm: PetProfileViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(vm.pets, id: \.id) { pet in
                    NavigationLink(value: Route.petProfile(petID: pet.id)) {
                        PetCard(pet: pet)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            vm.deletePet(pet)
                        } label: {
                            Label("删除伙伴", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 宠物卡片

private struct PetCard: View {
    let pet: Pet

    var body: some View {
        HStack(spacing: Spacing.lg) {
            // 头像 / 物种 Emoji
            avatarView

            // 信息列
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(pet.name)
                    .font(.titleStandard)
                    .foregroundStyle(Color.milensTextPrimary)
                infoLine
                photoCountLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
        }
        .padding(Spacing.lg)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large))
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.milensAccentSoft)
                .frame(width: 56, height: 56)
            if !pet.avatarPath.isEmpty {
                ThumbnailImage(path: pet.avatarPath)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else {
                Text(PetProfileLogic.speciesEmoji(pet.species))
                    .font(.system(size: 28))
            }
        }
        .frame(width: 56, height: 56)
    }

    private var infoLine: some View {
        HStack(spacing: Spacing.xs) {
            Text(PetDisplayLogic.speciesDisplayName(pet.species))
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
            if pet.birthday != nil {
                dot
                Text(PetDisplayLogic.ageText(from: pet.birthday))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            dot
            Text(PetDisplayLogic.genderDisplayName(pet.gender))
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
        }
    }

    private var photoCountLine: some View {
        HStack(spacing: Spacing.xs) {
            Text("\(pet.photoCount) 张照片")
                .font(.caption)
                .foregroundStyle(Color.milensPrimary)
            if pet.adoptionDay != nil {
                dot
                Text("相处 \(PetDisplayLogic.daysTogether(from: pet.adoptionDay)) 天")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
    }

    private var dot: some View {
        Text("·")
            .font(.caption)
            .foregroundStyle(Color.milensTextTertiary)
    }
}

// MARK: - 彩蛋弹窗

private struct EasterEggOverlay: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: Spacing.lg) {
                Text("🎂")
                    .font(.system(size: 40))
                Text("特别的缘分")
                    .font(.displayMedium)
                Text("这位可爱的宝贝和本APP的开发者同一天出生。\n感谢屏幕前的你，呵护着如此珍贵的生命。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    onClose()
                } label: {
                    Text("👍")
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensPrimary)
            }
            .padding(Spacing.xxl)
            .background(Color.milensCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large))
            .padding(.horizontal, Spacing.xxl)
        }
    }
}

#Preview {
    NavigationStack {
        PetsView()
    }
}
