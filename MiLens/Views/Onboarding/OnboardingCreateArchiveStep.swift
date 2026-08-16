//  OnboardingCreateArchiveStep —— 首次启动 02 建立档案（对照 Figma #47:10）。
//  EditorialSection（LIFE ARCHIVE + "先为伙伴建立生命档案"）+
//  Empty Identity 卡片（肖像轨道虚线圈 + ARCHIVE 001 + 「等待一位伙伴」）+
//  「伙伴叫什么名字？」+ 名字字段（Rail + TextField，底 milensGrouped）+
//  「选择伙伴类型」+ 3 个 species chip（喵星人/汪星人/其他伙伴）+
//  Honest Note 卡片。
//  FocusDialButton「创建第一份档案」（disabled：名字为空）。
//  petName / petSpecies 双向绑定到 viewModel。

import SwiftUI

struct OnboardingCreateArchiveStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: viewModel.stepOverline,
                    title: String(localized: "onboarding.createArchive.title"),
                    bodyText: String(localized: "onboarding.createArchive.body")
                )

                // Empty Identity 卡片
                emptyIdentityCard
                    .padding(.top, Spacing.xxl)

                // 名字字段
                Text(String(localized: "onboarding.createArchive.nameLabel"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, Spacing.xxl)

                nameField
                    .padding(.top, Spacing.sm)

                // 种类选择
                Text(String(localized: "onboarding.createArchive.speciesLabel"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, Spacing.xl)

                speciesChips
                    .padding(.top, Spacing.sm)

                // Honest Note 卡片
                honestNoteCard
                    .padding(.top, Spacing.xl)

                // 校验错误
                if !viewModel.scanError.isEmpty {
                    Label(viewModel.scanError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.milensDanger)
                        .padding(.top, Spacing.md)
                }

                // Focus Dial
                FocusDialButton(
                    label: String(localized: "onboarding.createArchive.cta"),
                    systemImage: "checkmark",
                    isEnabled: !viewModel.petName.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    nameFocused = false
                    viewModel.submitCreatePet()
                }
                .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty Identity 卡片（对照 #47:10 Archive / Empty Identity）

    private var emptyIdentityCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            HStack(spacing: 16) {
                // 肖像轨道虚线圈
                ZStack {
                    Circle()
                        .stroke(Color.milensBorder, lineWidth: 1)
                        .frame(width: 112, height: 112)
                    Circle()
                        .fill(Color.milensPrimary)
                        .frame(width: 10, height: 10)
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "onboarding.createArchive.mark"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(String(localized: "onboarding.createArchive.card.waiting"))
                        .font(.uiTitle)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(String(localized: "onboarding.createArchive.card.body"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.vertical, 20)
        }
    }

    // MARK: - 名字字段（对照 #47:10 Field / Name）

    private var nameField: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 2)
            TextField(String(localized: "onboarding.createArchive.namePlaceholder"), text: $viewModel.petName)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit {
                    nameFocused = false
                    if !viewModel.petName.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.submitCreatePet()
                    }
                }
                .padding(.horizontal, 14)
            Spacer()
        }
        .frame(height: 54)
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: - 种类选择（对照 #47:10 Species chips）

    private var speciesChips: some View {
        HStack(spacing: Spacing.sm) {
            speciesChip(title: PetDisplayLogic.speciesDisplayName(.cat), species: .cat, width: 102)
            speciesChip(title: PetDisplayLogic.speciesDisplayName(.dog), species: .dog, width: 102)
            speciesChip(title: String(localized: "onboarding.createArchive.species.other"), species: .unknown, width: 118)
            Spacer(minLength: 0)
        }
    }

    private func speciesChip(title: String, species: Species, width: CGFloat) -> some View {
        let isSelected = viewModel.petSpecies == species
        return Button {
            viewModel.petSpecies = species
        } label: {
            Text(title)
                .font(.uiBodyStrong)
                .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                .frame(width: width, height: 42)
                .background(isSelected ? Color.milensAccentWash : Color.milensCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(isSelected ? Color.milensActionPrimary : Color.milensBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Honest Note 卡片（对照 #47:10 Archive / Honest Note）

    private var honestNoteCard: some View {
        EditorialCard(cornerRadius: Radius.medium) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 2)
                Text(String(localized: "onboarding.createArchive.note"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.leading, 14)
                    .padding(.vertical, 14)
                    .padding(.trailing, 16)
                Spacer()
            }
        }
    }
}
