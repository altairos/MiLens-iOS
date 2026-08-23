# -*- coding: utf-8 -*-
"""英文本地化母语级复审修正（2026-08-22 一轮 A–D 级修复 + 2026-08-23 二轮 R 级风格润色）。

审查范围：App 1206 / Widget 47 / InfoPlist 3 条 en 文案全量通读；
二轮 R 分区聚焦去除机翻感：隐藏 baseline/Laplacian 等 ML 术语、
找回丢失的语义与行动指引、被动句与中式开头自然化。
本文件是本轮修正的单一事实来源，由 apply_all_en.py 在 legacy 显式
覆盖之后应用（占位符一致性、复数完整性与 pal 术语校验随之生效）。

配套结构操作（dict 无法表达，由 tools/apply_en_corrections.py 执行）：
- 删除死 key：home.photoCount %lld（全库零代码引用，Gallery 用的是 gallery.photoCount）
- 新增 a11y.photoView.favorite：PhotoViewView 收藏按钮的独立 label，
  自 a11y.gallery.favorite 拆分 —— 后者专职 GalleryComponents 的
  VoiceOver 拼接（值带前导 ", "），不再一 key 两用。
"""

# ---------------------------------------------------------------------------
# 纯文本条目修正（key 为 xcstrings 中的完整 key，含占位符后缀）
# ---------------------------------------------------------------------------
CORRECTIONS: dict[str, str] = {
    # --- A 硬伤 -------------------------------------------------------------
    # A1 VoiceOver 拼接缺分隔符：GalleryComponents.swift 用 text += 直拼，
    #    zh 靠源文前导「，」分隔，en 需要相同机制（", " 前导）。
    "a11y.gallery.date %lld %lld": ", %lld/%lld",
    "a11y.gallery.selected": ", Selected",
    "a11y.gallery.favorite": ", Favorite",
    # A2 语法 + 逻辑矛盾："%lld pal profile" 单复数错误；且 onboarding 路径
    #    恒传 proPetLimit=20，"Free plan supports up to 20 … Upgrade to Pro
    #    for up to 20" 自相矛盾。忠实 zh「最多支持管理 %lld 只伙伴」。
    "pet.form.countLimit %lld": "You can manage up to %lld pals.",
    # A3 原译 "Colors · Beads Total" 把建议购买量标成总量。zh 源文
    #    「%1$lld 颗 → 建议准备 %2$lld 颗」。
    "create.bead.materialCount %lld %lld": "%1$lld beads · %2$lld recommended",
    # A5 zh 现行源文「去看看你们一起留下的回忆吧。」无时间范围，
    #    原译 "from the past year" 无中生有。2026-08-23 复核：代码实参
    #    传宠物名（AnniversaryLogic.swift），zh 源文已补 %@，en 同步。
    "notify.anniversary.adoption.body %@": "Take a look back at the memories you've made with %@.",

    # --- B 语义偏移 ---------------------------------------------------------
    # B1 原译丢失「备份文件」核心概念（backup file → digital archive）。
    "onboarding.import.keep.body": (
        "Every day you share with your pal deserves to be remembered in full. "
        "MiLens can pack those days into a dedicated backup file, so no warm "
        "moment gets lost as time goes by."
    ),
    # B2 zh 是行动指引（去开启），原译改述为 9:00 AM 通知细节（该细节
    #    已由 settings.notifications.footer 表达）。
    "reminders.empty.hint": "Turn on Memorial Reminders to receive system notifications.",
    # B3 原译丢失前提（添加档案和照片后）与「值得回看的回忆」。
    "reminders.empty.body": (
        "Once you add a pal profile and photos, you'll get reminders for "
        "birthdays, adoption days, and memories worth revisiting."
    ),
    # B4/B5 原译丢失「参考照片」概念 / 暴露 ML 术语 "feature baseline"。
    "timeline.reference.update.title %@": "Update %@'s Reference Photos",
    "timeline.reference.update.subtitle %@": "%@ is growing fast — it's time to refresh the reference photos",
    # B6 动态 key（RedPacketQualityLogic detailArgs 为空的分支）：
    #    严禁携带 %lld/%@。原译丢失行动指引「请重新抠图」。
    "redpacket.quality.cutout.unavailable.detail": "No valid cutout yet — please redo the cutout",
    # B7 原译丢失保存途径（Files / iCloud Drive / AirDrop）。
    "settings.backup.exportReadyHint": (
        "Choose where to save it: the Files app, iCloud Drive, or AirDrop to "
        "your computer. Keep this memory safe so the story is always with you."
    ),
    # B8 zh 是安抚语气「还在这里」，原译 "are Locked" 变成生硬的功能限制。
    "timeline.lockedEmptyTitle": "Your earlier stories are still here",
    # B9 "Now it's time for WeChat" 不自然。
    "upload.headline": "The cover is ready.\nThe rest happens in WeChat.",
    # B10 "Sign in in" 双介词。
    "upload.step.02.desc": "Sign in from your browser and open Personal Customization.",

    # --- C 一致性 -----------------------------------------------------------
    # C1 同一 zh「似乎有熟悉的伙伴」两译（album 侧 = Familiar Photos Found）。
    "onboarding.candidates.title": "Familiar Photos Found",
    # C2 「已保存到相册」三译统一（对齐 redpacket.export.saved）。
    "create.save.success": "✅ Saved to Photos",
    # C3-C7 直引号 → 弯引号（Apple 排版惯例）；app 内相册页 EN 名为
    #    "Photos"（gallery.title），"album page/album" 统一改 "Photos"。
    "help.a1": (
        "Tap “Scan” on the Photos page — MiLens finds photos that may contain "
        "your pal on your device, then lets you confirm and import them."
    ),
    "help.a2": (
        "Pick a pal when reviewing scan results; you can also select multiple "
        "photos in Photos and assign them to a pal."
    ),
    "help.a3": (
        "Go to the Create tab, choose “Bead Pattern”, pick a photo, adjust "
        "size and style, then generate and export."
    ),
    "onboarding.scan.incomplete.hint": "You can skip the scan and start it anytime from the Photos page.",
    "可在「设置 → 隐私 → 照片」中开启，也可以稍后在相册页授权": (
        "You can enable it in Settings → Privacy → Photos, or authorize later from the Photos page"
    ),
    "启用\"只拼主体\"时会自动抠图；失败后仍会使用原图继续生成": (
        "Enabling “Subject Only” automatically cuts out the pal subject; if "
        "that fails, generation continues with the original photo"
    ),
    # C8/C9 两个 key 的 EN 恰好交叉互换（照片记忆↔照片）。
    "timeline.memoryType.photo": "Photo Memory",
    "timeline.photo.title.default": "Photo",
    # C10 filter chip 与伙伴名对照，"All" 足够（对齐 Apple Photos 惯例）。
    "timeline.filterAll": "All",

    # --- D 自然度 -----------------------------------------------------------
    "editor.cutout.action.applied": "Redo Cutout",          # Re-cutout 生造词
    "picker.compare.start": "Start Comparison",             # Start Compare 动宾不搭
    "home.upcoming.days.adoption.family %@ %lld %lld": (    # "%@ family for" 缺动词
        "In %lld days · %@ has been family for %lld days"
    ),
    "a11y.home.bell": "Your Memories",  # 二轮再润（一轮 Memories to View 仍生硬；zh：待看的回忆）
    "reminders.section.memories": "Throwbacks",             # Past Flashbacks 冗余
    "redpacket.quality.recheck": "Check Again",             # Re-check Quality 拗口
    "redpacket.workshop.loadError.back": "Go Back",         # Return 欠自然
    "redpacket.style.elegant": "Elegant",                   # Graceful Elegance 同义堆叠
    "redpacket.template.petFresh.title": "Fresh & Cuddly",  # Pal Fresh 语序别扭
    "redpacket.workshop.cutoutHint": "Pick a photo and the smart cutout runs automatically",
    "redpacket.quality.readability.zone.detail": "Text is in a risk zone and may be covered by WeChat UI",
    "settings.backup.failed": "Backup Failed",              # Backup process encountered an error 冗长
    "保存后将以 PNG 格式保留透明背景": "Saves as PNG to keep the transparent background",

    # --- Widget -------------------------------------------------------------
    # 与 widget.lifeArchive.empty.noPhotos（"No photos yet"）撞车；zh 为祈使句。
    "widget.photoEcho.empty.noPhoto": "Leave a photo for today",
    # iOS 系统惯用语（Photos「往年今日」）。
    "widget.intents.photoEcho.source.yearsAgoToday": "On This Day",

    # --- R 二轮风格润色（2026-08-23 全量通读，去除机翻感） ---------------------
    # R1 概念词统一：onboarding / pet.edit 的「特征基准 / FEATURE REGISTER /
    #    注册」等 ML 术语对用户隐藏，与 timeline.reference.update（一轮
    #    B4/B5 已定名）统一为 references / reference photos。
    "onboarding.feature.badge": "Reference Photos",
    "onboarding.feature.baseline": "Reference Photos",
    "onboarding.feature.cta": "Build References",
    "onboarding.feature.intro.title": "Pick 8–15 photos\nto use as references",
    "onboarding.feature.processing.body %lld": (
        "Summing up %lld photos into a comparison baseline. Nothing is "
        "uploaded, and your library isn't scanned at this point."
    ),
    "onboarding.feature.processing.cta": "Building references…",
    "onboarding.feature.processing.status": "Building the reference set",
    "onboarding.feature.processing.title %@": "Building %@'s\nreferences on device",
    "onboarding.feature.ready.note %@": "Used only to build %@'s on-device references",
    "onboarding.feature.stage.summarize %@": "Summing up %@'s references",
    "onboarding.feature.registerFailed %@": "Couldn't save references: %@",
    "onboarding.feature.registered %lld": "%lld reference photos added",
    "onboarding.feature.done.count %lld": "%lld reference photos",
    "onboarding.feature.done.title %@": "%@'s reference photos\nare ready",
    "onboarding.feature.done.body": (
        "MiLens can now compare new photos against this baseline — "
        "candidates still aren't confirmed matches."
    ),
    "onboarding.feature.done.next.body": (
        "You'll need to allow access to all photos in Settings first. "
        "Scanning only finds candidates — nothing is imported automatically."
    ),
    "onboarding.overline.featureIntro": "References · 8–15 Photos",
    "onboarding.overline.featureProcessing": "References · Processing",
    "onboarding.overline.featureDone": "References · Ready",
    "onboarding.overline.fullScan": "Local Scan · References Ready",
    "onboarding.createArchive.note": (
        "Create the profile first, then add reference photos; scan results "
        "are never imported automatically."
    ),
    "onboarding.scan.body %@": (
        "Comparing against %@'s reference photos.\nEverything found still "
        "needs your confirmation."
    ),
    "onboarding.candidates.body %@": (
        "These are candidate photos that resemble %@ — confirm each one "
        "before importing."
    ),
    "onboarding.candidates.cta %lld %@": "Add %lld photos to %@'s archive",
    "pet.edit.feature.register": "Add Reference Photos",
    "pet.edit.feature.registered": "Reference Photos Added",
    "pet.edit.feature.failed %@": "Couldn't save references: %@",
    "pet.edit.feature.success %lld": "Added %lld reference photos",
    "pet.edit.feature.footer.new %lld %lld": (
        "Pick %lld–%lld photos with varied angles and lighting; new photos "
        "will be matched into this archive automatically."
    ),
    "pet.edit.feature.footer.update %lld %lld": (
        "To update the references, choose %lld–%lld photos again"
    ),

    # R2 质量面板：Laplacian 等算法术语隐藏；%lld%% 语义错位与丢失单位修复
    #    （%lld 是亮度值/占比而非超出量，原译 "is %lld%% overexposed" 误读）。
    "redpacket.quality.clarity.blur.detail": (
        "Sharpness score is low (%lld) — the photo may look blurry"
    ),
    "redpacket.quality.brightness.bright.detail": (
        "Photo looks bright (brightness %lld%%) and may be overexposed"
    ),
    "redpacket.quality.brightness.dark.detail": (
        "Photo looks dark (brightness %lld%%) — consider brightening it"
    ),
    "redpacket.quality.brightness.highlightClipping.detail": (
        "Highlights are clipped (%lld%%) — consider lowering exposure"
    ),
    "redpacket.quality.brightness.shadowClipping.detail": (
        "Shadow detail is lost (%lld%%) — consider lifting shadows slightly"
    ),
    "redpacket.quality.composition.clipped.detail": (
        "Subject is clipped near the edges (%lld%%) — adjust the crop"
    ),
    "redpacket.quality.cutout.retry.detail": (
        "Too little of the subject was detected (%lld%%) — the cutout may fail"
    ),
    "redpacket.quality.cutout.fragmented.detail": (
        "Cutout has scattered patches (%lld%%) — try again for a cleaner result"
    ),
    "redpacket.quality.cutout.rough.detail": (
        "Cutout edges look rough (%lld%%) — try again"
    ),
    "redpacket.quality.thisAdjustment": "Your Adjustments",

    # R3 语义偏移：找回丢失的行动指引/安抚语气，纠正与 zh 相悳的表述。
    "timeline.birthday.title %@ %lld": "Happy Birthday, %@! 🎂 Turning %lld today",
    "redpacket.export.openButton": "Open Button Safe Zone",
    "redpacket.export.loadFailed": "Couldn't load your draft",
    "redpacket.export.saveFailed": (
        "Couldn't save to Photos — check Photos permission and try again"
    ),
    "redpacket.export.shareFailed": "Couldn't prepare sharing — please try again",
    "redpacket.export.shareReady": "Ready to share — choose an app to continue",
    "redpacket.export.howToUse": (
        "Save to Photos, then choose it as a custom cover on WeChat's Red Packet page"
    ),
    "redpacket.export.editorialTitle": "From chat to the reveal,\nsee the full effect.",
    "redpacket.cutout.loading": "Loading…",
    "redpacket.cutout.ready": "Cutout ready — edit it in the workshop",
    "redpacket.cutout.failed": "Cutout failed — try again or choose a different photo",
    "redpacket.workshop.loadError.photo": "Couldn't load the photo — go back and pick another",
    "redpacket.workshop.loadError.template": "Couldn't load the template — go back and pick another",
    "settings.backup.confirmAction": "Start Export",
    "settings.backup.hint.body": (
        "Every day with your pal is worth keeping whole. Use Backup Export "
        "regularly to create a .milensbackup file, save it to iCloud Drive, "
        "or AirDrop it to your computer — one more layer of protection for "
        "precious memories."
    ),
    "settings.pro.card.headline": "Make Your Archive Complete",
    "settings.pro.card.headline.active": "All Features Unlocked",  # 与 active.title 撞车
    "settings.pro.card.body.active": (
        "Thanks for your support — your lifetime archive is now complete"
    ),
    "settings.subtitle.suffix": " · keeping every memory on your device",
    "share.sheet.subtitle": "Share it on social media so more people can see it",
    "home.loadError": "Couldn't load your photos — please try again later",
    "notify.anniversary.birthday.body %@": "Take a look back at %@'s birthday memories",
    "notify.milestone.title %lld": "%lld Days Home",
    "notify.milestone.body %@ %lld": "%@ has been home for %lld days!",
    "reminders.loadError": "Couldn't load memories — please try again later",
    "reminders.today.milestone %@ %lld": "%@ has been home for %lld days!",
    "onboarding.welcome.waypoint.confirm": "You stay in control",
    "onboarding.welcome.waypoint.organize": "Organized on device",
    "widget.upcoming.empty.missing": "This anniversary no longer exists",
    "widget.upcoming.description": (
        "Count down to an anniversary you pick — or the closest one, automatically"
    ),
    "widget.photoEcho.description": (
        "Rediscover a photo from today, years past, or just recently"
    ),
    "widget.intents.anniversary.auto": "Auto (nearest)",
    "widget.lockscreen.memory.createFile": "Add a Pal",

    # R4 机翻腔自然化：去被动句/中式开头，恢复母语句感。
    "home.backup.banner.body %lld": (
        "You've captured %1$lld precious moments — export a backup to keep "
        "every story safe."
    ),
    "create.header.subtitle": "Photos stay on your device · Generated locally",
    "create.bead.localProcessHint": (
        "Processed on device only · Falls back to the original photo if cutout fails"
    ),
    "memory.draft": "Draft autosaved",
    "gallery.empty.body": (
        "Scan your photo library and MiLens will find photos of your pal automatically"
    ),
    "timeline.empty.body": (
        "Add a pal profile and photos, and their growth timeline will appear "
        "here automatically"
    ),
    "timeline.lockedBannerTitle": "Stories from over a year ago are still saved for you",
    "pet.edit.avatar.footer": "Choose a photo and crop it to a circle",
    "preview.contentArea": "Content Area",

    # R5 recap 定名：life review 在英语中是临终回顾的固定术语，改用 Year in Review。
    "recap.title": "Year in Review",
    "recap.renderFailed": "Couldn't generate your recap",
    "recap.empty.body": "Import photos and your annual recap will appear here",
    "recap.totalPhotos %lld": "%lld photos in total",

    # R6 相册页术语：「先到相册…」的 album 与一轮 C3-C7 统一为 Photos page。
    "picker.bead.emptyDesc": (
        "Import photos on the Photos page first, then come back to create a bead pattern"
    ),
    "picker.compare.emptyDesc": (
        "Import photos on the Photos page first, then come back to create a comparison card"
    ),
    "picker.petCard.emptyDesc": (
        "Import photos on the Photos page first, then come back to create a pal card"
    ),
    "picker.redPacket.emptyDesc": (
        "Import photos on the Photos page first, then come back to create a Red Packet cover"
    ),

    # --- 新 key（结构操作见本文件头部说明；此值供 apply_all_en.py 校验与幂等注入） ---
    "a11y.photoView.favorite": "Favorite",
}

# ---------------------------------------------------------------------------
# 复数条目修正（one/other）。本轮无复数修正。
# ---------------------------------------------------------------------------
CORRECTION_PLURALS: dict[str, dict[str, str]] = {}

# ---------------------------------------------------------------------------
# 结构操作（由 tools/apply_en_corrections.py 消费）
# ---------------------------------------------------------------------------

# 死 key：全库零引用（Gallery 实际使用 gallery.photoCount %lld）。
DELETE_KEYS: list[str] = [
    "home.photoCount %lld",
]

# 新增条目：PhotoViewView 收藏按钮独立 label（自 a11y.gallery.favorite 拆分）。
# 五语言值参照 a11y.gallery.favorite 现有条目（de/fr/en 一致，zh 去掉拼接前导逗号）。
NEW_ENTRIES: dict[str, dict] = {
    "a11y.photoView.favorite": {
        "extractionState": "manual",
        "localizations": {
            "de": {"stringUnit": {"state": "translated", "value": "Favorit"}},
            "en": {"stringUnit": {"state": "translated", "value": "Favorite"}},
            "fr": {"stringUnit": {"state": "translated", "value": "Favori"}},
            "zh-Hans": {"stringUnit": {"state": "translated", "value": "收藏"}},
            "zh-Hant": {"stringUnit": {"state": "translated", "value": "收藏"}},
        },
    },
}
