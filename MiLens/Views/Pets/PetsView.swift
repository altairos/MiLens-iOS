//  PetsView —— 宠物档案列表（Tab 2，对应源端 pages/PetProfilePage.ets 列表部分）。
//  P3 实现：宠物卡片列表（头像/名称/物种·年龄·性别/照片数·相处天数）+ 建档入口 + 彩蛋。
//  PetProfileViewModel（@Observable）驱动状态，决策通过 PetProfileLogic 纯函数。

import SwiftUI

struct PetsView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.notifyService) private var notifyService
    @Environment(\.proEntitlement) private var entitlement

    @State private var viewModel: PetProfileViewModel?
    @State private var showAddSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // 分层收敛：VM 由工厂组装（View 不再直连 petRepo）
                let vm = factory.makePetProfileViewModel(isPro: entitlement.isPro)
                vm.loadPets()
                viewModel = vm
            }
        }
        .onChange(of: entitlement.isPro) { _, isPro in
            viewModel?.updateEntitlement(isPro: isPro)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.durationSlow), value: viewModel?.showEasterEgg)
        .background(Color.milensBackground)
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
            Image(systemName: "pawprint")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
            Text("还没有伙伴档案")
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
            Text("为它建立一份档案，\n照片、纪念日和故事都会留在这里。")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                vm.resetForm()
                showAddSheet = true
            } label: {
                Label("添加伙伴", systemImage: "plus")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(minHeight: Sizing.touchTarget)
                    .padding(.horizontal, Spacing.lg)
                    .background(Color.milensActionPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.pagePad)
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
                            // 撤销该宠物的纪念提醒
                            if let notifyService {
                                Task { await notifyService.removeReminders(for: pet) }
                            }
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
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
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
        // M4：头像为装饰性图形，合并为单一无障碍元素（名称由卡片内 Text 读出）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pet.avatarPath.isEmpty
            ? String(localized: "a11y.pets.avatar \(PetDisplayLogic.speciesDisplayName(pet.species))")
            : String(localized: "a11y.pets.avatarPhoto \(pet.name)"))
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
                .foregroundStyle(Color.milensActionPrimary)
            if pet.adoptionDay != nil {
                dot
                Text(String(localized: "pet.daysTogether \(PetDisplayLogic.daysTogether(from: pet.adoptionDay))"))
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
                    .foregroundStyle(Color.milensTextPrimary)
                Text("这位可爱的宝贝和本APP的开发者同一天出生。\n感谢屏幕前的你，呵护着如此珍贵的生命。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    onClose()
                } label: {
                    Text("知道啦")
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.xxl)
            .background(Color.milensElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .elevation(Elevation.medium)
            .padding(.horizontal, Spacing.xxl)
        }
    }
}

#Preview {
    NavigationStack {
        PetsView()
    }
}
