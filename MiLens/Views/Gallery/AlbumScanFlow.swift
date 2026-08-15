//  AlbumScanFlow —— 相册扫描导入流程容器（对照 Figma「相册扫描与配额付费墙原型」#27:2）。
//  fullScreenCover 呈现，@State phase 驱动步骤切换：
//  扫描 → 候选 → 选择宠物 → 导入 → 成功 / 额度用尽。
//  复用 GalleryViewModel 扫描/导入能力，不新建 ViewModel。

import SwiftUI

/// 扫描导入流程阶段（对照 Figma 01–08 画板）。
enum AlbumScanPhase: Equatable {
    case scanning          // 01 扫描中
    case candidates        // 02 候选列表
    case petSelect         // 03 选择宠物
    case importing         // 04 导入中
    case success(petName: String, count: Int)  // 05 导入成功
    case quotaExhausted    // 07 免费额度已用完
}

struct AlbumScanFlowView: View {
    @Bindable var vm: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var phase: AlbumScanPhase = .scanning
    /// 候选选中的 identifier 集合（候选页 → 选择宠物页）。
    @State private var selectedIdentifiers: Set<String> = []
    /// 选定的目标宠物（选择宠物页 → 导入）。
    @State private var selectedPetID: UUID?

    var body: some View {
        ZStack {
            Color.milensBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                flowHeader

                Group {
                    switch phase {
                    case .scanning:
                        AlbumScanStageView(vm: vm, isImport: false)
                    case .candidates:
                        AlbumCandidateListView(
                            vm: vm,
                            selectedIdentifiers: $selectedIdentifiers,
                            onContinue: { advanceToPetSelect() }
                        )
                    case .petSelect:
                        AlbumPetSelectView(
                            vm: vm,
                            selectedCount: selectedIdentifiers.count,
                            selectedPetID: $selectedPetID,
                            onConfirm: { startImport() },
                            onCreateNew: { startImportUnassigned() }
                        )
                    case .importing:
                        AlbumScanStageView(vm: vm, isImport: true)
                    case .success(let petName, let count):
                        AlbumImportSuccessView(
                            petName: petName,
                            count: count,
                            onViewPhotos: { dismiss() }
                        )
                    case .quotaExhausted:
                        AlbumQuotaExhaustedView(
                            vm: vm,
                            onDismiss: { dismiss() }
                        )
                    }
                }
            }
        }
        .onAppear {
            if !vm.isScanning && vm.candidateURIs.isEmpty {
                // 直接进入流程时触发扫描
                vm.startScan()
            }
        }
        .onChange(of: vm.isScanning) { _, isScanning in
            // 扫描结束 → 进入候选页
            if !isScanning && phase == .scanning && !vm.candidateURIs.isEmpty {
                selectedIdentifiers = Set(vm.candidateURIs)
                phase = .candidates
            } else if !isScanning && phase == .scanning {
                // 扫描无候选或失败 → 关闭流程
                dismiss()
            }
        }
        .onChange(of: vm.isImporting) { _, isImporting in
            // 导入结束 → 成功页或额度墙
            if !isImporting && phase == .importing {
                let imported = vm.lastImportResult?.imported ?? 0
                if imported > 0 {
                    let petName = vm.pets.first { $0.id == selectedPetID }?.name ?? "伙伴"
                    phase = .success(petName: petName, count: imported)
                } else if vm.lastImportResult?.hitQuota == true || vm.totalPhotoCount >= CommercialRules.freePhotoLimit {
                    phase = .quotaExhausted
                } else {
                    dismiss()
                }
            }
        }
    }

    // MARK: - 流程 Header（对照 Figma Header 组件）

    private var flowHeader: some View {
        let (overline, title, rightText) = headerContent
        return HStack(spacing: 11) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Sizing.iconMd, weight: .medium))
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                    .foregroundStyle(Color.milensTextPrimary)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(overline)
                    .font(.custom("JacquesFrancois-Regular", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(title)
                    .font(.uiTitle)
                    .foregroundStyle(Color.milensTextPrimary)
            }

            Spacer()

            if !rightText.isEmpty {
                Text(rightText)
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensActionPrimary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private var headerContent: (overline: String, title: String, rightText: String) {
        switch phase {
        case .scanning:
            let pct = Int(vm.scanProgressPercent * 100)
            return ("ALBUM / SCANNING", "正在浏览相册", "\(pct)%")
        case .candidates:
            let total = vm.candidateURIs.count
            let selected = selectedIdentifiers.count
            return ("ALBUM / CANDIDATES", "候选照片", "\(selected) / \(total)")
        case .petSelect:
            return ("ALBUM / ASSIGN", "选择伙伴档案", "")
        case .importing:
            let pct = Int(vm.importProgressPercent * 100)
            return ("ALBUM / IMPORTING", "照片归档中", "\(pct)%")
        case .success:
            return ("ARCHIVE / ENTRY", "归档完成", "")
        case .quotaExhausted:
            return ("FREE ARCHIVE / 50 OF 50", "导入额度", "")
        }
    }

    // MARK: - 流程推进

    private func advanceToPetSelect() {
        phase = .petSelect
    }

    private func startImport() {
        guard !selectedIdentifiers.isEmpty else { return }
        phase = .importing
        // 按候选列表顺序过滤选中项（Set 迭代序随机，见 OnboardingViewModel 同样处理）
        let identifiers = vm.candidateURIs.filter { selectedIdentifiers.contains($0) }
        vm.importCandidates(identifiers: identifiers, targetPetID: selectedPetID)
    }

    /// 用户选择"新建伙伴档案"时：导入为未归属照片（稍后手动建档归属）。
    private func startImportUnassigned() {
        guard !selectedIdentifiers.isEmpty else { return }
        phase = .importing
        let identifiers = vm.candidateURIs.filter { selectedIdentifiers.contains($0) }
        vm.importCandidates(identifiers: identifiers, targetPetID: nil)
    }
}
