# MiLens 全球本地化计划

最后更新：2026-08-10（首发 7 语言定案：zh-Hans / zh-Hant / ja / ko / en / fr / de）

> 本文档是 MiLens 全球首发本地化工作的唯一事实来源：语言矩阵、各国市场注意要点、翻译工作流、质量门禁、ASO 关键词策略与时间线。工具与命令见 [DEVELOPMENT.md](../DEVELOPMENT.md) §4.5，商店文案见 [AppStore-metadata.md](AppStore-metadata.md)，商业决策见 [ADR-0010](adr/0010-commercialization-and-emotion-triggers.md)。

## 1. 目标与原则

### 1.1 目标

首发即覆盖 7 种语言，对应全球主要宠物消费市场，实现"一份代码、一套资源、多语言上架"。多语言不是"上线后补"，而是首发的一部分——因为：

- 拼豆是覆盖全部首发市场的全球性手工艺品类（日本 Perler / 欧美 Hama / 韩台 DIY）；
- 隐私优先（照片不离开设备）的定位在德/日/法市场是付费理由本身；
- 开发者本身是本地化专业出身，多语言边际成本接近零，但构成竞品难以短期复制的壁垒。

### 1.2 原则

| 原则 | 说明 |
|---|---|
| 源语言唯一 | 简中（zh-Hans）是唯一事实来源，英文作为**第二参照语言**（用于校验译义漂移） |
| 工具链驱动 | 全部走 `tools/localization.py`（export/import/check）+ CI 门禁，不手工改 `.xcstrings` |
| 术语一致性 | 核心术语表（§8）先行定稿，7 语言对照，避免一义多译 |
| 诚实标注 | "计划加入"的能力不得在任一语言中写成已交付（沿用 ADR-0009 规则） |
| 文化适配优先于直译 | 各国市场注意要点（§4）逐条落实，不满足于"读得通" |

---

## 2. 语言覆盖矩阵

| 语言代码 | 覆盖区域 | 市场级别 | 优先级 | 首发 | 备注 |
|---|---|---|---|---|---|
| zh-Hans | 中国大陆 | 基本盘（源语言）| P0 | ✅ | 现有文案，需按 §4.7 校验 |
| en | 美/英/澳/加/新等 | S 级（体量最大）| P0 | ✅ | App 内统一美式英语 |
| ja | 日本 | S 级（拼豆文化原点）| P0 | ✅ | 最吃本地化质量的市场 |
| zh-Hant | 台湾、香港 | B 级（稳定）| P1 | ✅ | 以台湾用语为准，香港差异记录 |
| ko | 韩国 | A 级（高潜力）| P1 | ✅ | 必须用"반려동물" |
| de | 德国/奥地利/瑞士 | S 级（隐私杀手锏）| P1 | ✅ | 文案长度预算最大 |
| fr | 法国/魁北克/比利时 | A 级（低成本高回报）| P1 | ✅ | 以法国法语（fr-FR）为准 |

> 后续扩展候选（V1.x，工具链零改动）：es、pt、it、ru、id、th、vi。

### 2.1 新增语言的标准操作

```bash
# 1. project.yml knownRegions 追加语言代码（如 "ja"）
# 2. 导出待翻译 Excel（可一次导出多语言列）
python tools/localization.py export \
    MiLens/Resources/Localizable.xcstrings \
    MiLens/Resources/InfoPlist.xcstrings \
    build/loc.xlsx --lang en,ja,zh-Hant,ko,de,fr

# 3. 翻译后逐语言导入回写
python tools/localization.py import build/loc.xlsx \
    MiLens/Resources/Localizable.xcstrings --lang ja

# 4. 校验（0 缺译 / 0 多余 key / 格式一致），CI 同款命令
python tools/localization.py check \
    MiLens/Resources/Localizable.xcstrings \
    MiLens/Resources/InfoPlist.xcstrings \
    --project-yml project.yml --source-root MiLens
```

---

## 3. 本地化范围清单（6 类资产）

| # | 资产 | 位置 | 说明 | 状态 |
|---|---|---|---|---|
| 1 | App UI 文案 | `Localizable.xcstrings`（~150 key）| 全部 `String(localized:)`，结构已支持任意语言 | 待翻译 |
| 2 | 权限说明 + App 显示名 | `InfoPlist.xcstrings`（3 key）| 权限文案需按各国法规语感撰写，App 显示名按语言本地化 | 待翻译 |
| 3 | App Store 元数据 | [AppStore-metadata.md](AppStore-metadata.md) | 名称/副标题/描述/关键词/推广文本/审核备注，每语言一份 | 待制作 |
| 4 | 订阅产品本地化 | App Store Connect | 订阅组 + 3 个产品的本地化描述（§3.4）| 待录入 |
| 5 | 隐私政策网页 | `docs/privacy-policy.html` | 需提供多语言版本（建议按语言 URL 或 `?lang=`）| 待制作 |
| 6 | 截图/预览素材 | App Store Connect | 每语言 3-5 张截图 + 文案覆盖层 | 待制作 |

### 3.1 App 显示名（CFBundleDisplayName）按语言建议

| 语言 | 建议显示名 | 说明 |
|---|---|---|
| zh-Hans | 咪Lens - 宠物照片整理与拼豆创作 | 现有 |
| zh-Hant | 咪Lens - 寵物照片整理與拼豆創作 | 保留品牌，本地化用词 |
| en | MiLens - Pet Photos & Bead Art | 简洁，突出双卖点 |
| ja | 咪Lens - ペット写真整理とアイロンビーズ図案 | 品牌保留，用品类词 |
| ko | MiLens - 반려동물 사진 정리와 비즈 도안 | 品牌保留 |
| de | MiLens - Haustierfotos & Bügelperlen-Vorlagen | 用品类词 Bügelperlen |
| fr | MiLens - Photos animaux & perles à repasser | 用品类词 |

### 3.2 副标题（App Store 30 字符限制，每语言）

| 语言 | 建议副标题 |
|---|---|
| zh-Hans | 拾回散落的每一张照片，记住你与爱宠共度的一生（现有）|
| zh-Hant | 拾回散落的每一張照片，記住你與毛小孩共度的一生 |
| en | Every pet photo, organized & turned into bead art |
| ja | ペットの写真を整理して、アイロンビーズの図案に |
| ko | 반려동물 사진 정리와 비즈 도안 만들기 |
| de | Haustierfotos sortieren & Bügelperlen-Vorlagen |
| fr | Triez les photos d'animaux, créez des perles à repasser |

> 以上为方向性草案，定稿以 ASO 校验为准（§7）。

### 3.3 描述/推广文本/审核备注

- 描述：按 §2 工作流翻译 `AppStore-metadata.md` §2 的中文描述，每语言控制在 4000 字符内；
- 推广文本（170 字符）：每语言按市场热点可随时更新（App Store 无需审核）；
- 审核备注：**用英文撰写一份全球通用版**，另为 ja/ko/zh-Hant 各准备一份当地语言版（审核员阅读效率 = 过审速度）。

### 3.4 订阅产品本地化描述（App Store Connect 必填）

每个产品（月/年/永久）每种语言都要填写本地化描述与显示名。结构沿用 [AppStore-metadata.md](AppStore-metadata.md) §7.3 中文版，翻译时注意：

- 订阅权益描述按语言惯例调整（如日语加"自動更新はいつでも解除できます"）；
- 价格文案不写死金额（由 ASC 层级自动显示）；
- 永久版描述强调"一回購入、ずっと使える"式的本地化表达。

### 3.5 隐私政策多语言

- 策略：`privacy-policy.html` 增加语言切换（同页 `?lang=ja` 或独立子页），至少提供 en/ja/de（审核常见语言）+ 全部首发语言；
- 德语版需符合 GDPR 透明度习惯用语；日语版遵循日本個人情報保護法语境；
- 托管在现有 GitHub Pages（miovelle.cn）即可，无额外成本。

---

## 4. 各国市场注意要点（重点）

> 本节是本地化工作的核心质量要求。每条都需要在翻译与截图阶段逐项落实，并在 §9 验收时逐条打勾。

### 4.1 日本（ja）— S 级

**市场特征**
- 拼豆（アイロンビーズ / パーラービーズ）是昭和—平成世代集体记忆，手作市场成熟，付费意愿高；
- 猫文化极强，「猫の日 2/22」是天然营销节点；宠物 App 在日本商店有专属流量入口；
- iPhone 市占率全球最高梯队，iOS 付费习惯成熟；
- **对机翻零容忍**：一个不自然的表达就可能导致一星差评，本地化质量直接决定评分与榜单位置。

**语言与文案**
- 一律使用丁寧語（です/ます 体），禁用简体（だ/である）与过度亲密口语；
- 全角标点（。、「」、！？）必须正确；数字用半角；
- 日文汉字与中文汉字含义不同（手紙=信、娘=女儿、勉強=学习），**不得从中文直接替换汉字**；
- 长音（ー）、拗音小字、送假名细节要校对。

**产品与术语**
- 品类词用「アイロンビーズ」（熨烫珠），图纸用「図案 / デザイン」，生成用「作成」；
- 拼豆工作室 → ビーズスタジオ；成长时间线 → 成長タイムライン；
- 隐私叙事："写真は端末から出ません"（照片不离开设备）在日区是强卖点，必须出现在描述与付费墙；
- 彩虹桥（虹の橋）在日本宠物文化中非常普遍，可直接使用；
- 通知时间 09:00 合适；通知文案需要亲切（て形 + 絵文字适度，日区接受度高，但克制）。

**ASO 方向**
- 高价值词：ペット写真 / アイロンビーズ / パーラービーズ / 写真整理 / 猫 / 犬 / ペットアルバム；
- 「写真整理」竞争高，「アイロンビーズ」中等——是突破口；
- 截图上日文文案必须地道（日本用户会截图放大看文字）。

### 4.2 美国 / 英文区（en）— S 级

**市场特征**
- 全球最大市场，竞争也最激烈；Perler Beads / Melty Beads 是 Millennial 怀旧品类，Etsy/Pinterest 有海量 UGC；
- 订阅+买断混合模式接受度高，$24.99 永久版处于冲动购买区间；
- Family Sharing 在美区利用率高（已配置 ✅）。

**语言与文案**
- App 内统一美式英语（color / favorite / organize）；元数据可另备 en-GB 版本（colour / favourite），优先级低；
- 日期 MM/DD/YYYY，金额 $ 符号，千分位逗号；
- 语气：温暖但不油腻，避免过度营销化形容词（"adorable" 用在宠物语境可以，"revolutionary" 不行）；
- 注意 pet 与 companion animal 的语境差异：UI 用 pet，营销文案可提 companion。

**产品与术语**
- 图纸术语：bead pattern（通用）、perler pattern（用户搜索习惯词，可用于 ASO）；
- 隐私叙事："All photos stay on your device" 是 iOS 用户强感知卖点，放描述第二段；
- 彩虹桥（Rainbow Bridge）在英语宠物社区是常见正面概念，宠物卡片/纪念文案可直接用；
- 导出尺寸：A4 可用；美区可后续评估 Letter 适配（低优先级）。

**ASO 方向**
- 高价值词：pet photos / pet album / perler beads / bead pattern / photo organizer / cat / dog；
- "perler" 是品牌词，用 "perler beads" 长尾更安全；
- 关键词 100 字符限额，按搜索量×竞争度精选。

### 4.3 德语区（de）— S 级

**市场特征**
- GDPR 发源地，隐私敏感度全球最高——"照片不离开设备"在这里不是加分项而是**购买理由本身**；
- Hama Beads（丹麦品牌）在德语区是主流手工艺，Bügelperlen 认知度高；
- 德语区用户重视透明与细节，期望落差直接转化为差评。

**语言与文案**
- **德语复合词极长**：UI 必须预留 30-40% 长度空间，Tab、按钮、卡片逐项做截断测试；
- 术语：品类词必须是 **Bügelperlen**（熨烫珠）；Steckperlen 是另一种工艺（插珠），**不可混用**；图纸 = Vorlage / Muster；
- 称呼：消费级 App 惯例用 du（informal），但全文必须一致（设置页与弹窗不得混用 du/Sie）；
- 名词首字母大写规则必须正确；标点使用德式引号（„…"）；
- 动物名词词性：der Hund / die Katze——文案避免依赖性别表述，或统一用 Haustier（宠物）；
- 日期 DD.MM.YYYY，小数点用逗号（€14,99）。

**产品与术语**
- 隐私叙事：**德语版描述建议专门加一段**，用具体措辞（"Alle Fotos und Analysen bleiben auf Ihrem Gerät. Keine Cloud, kein Upload."）；
- 年度订阅（€14.99 级）必须突出节省比例（"über 55% sparen"），德语用户对价格透明敏感；
- 订阅取消条款写清楚（"jederzeit kündbar"），符合德国消费者习惯；
- 通知 09:00 合适；德语通知文案保持正式礼貌。

**ASO 方向**
- 高价值词：Bügelperlen / Bügelperlen Vorlagen / Haustier / Hund / Katze / Fotoalbum / Fotos sortieren；
- "Bügelperlen Vorlagen"（熨烫珠图纸）是强购买意图词，优先拿下。

### 4.4 韩国（ko）— A 级

**市场特征**
- 반려동물（伴侣动物）文化快速兴起，宠物经济高速增长；
- iPhone 市占率较高，iOS 付费习惯好；DIY/手工（비즈공예）在女性用户中流行。

**语言与文案**
- **必须用 반려동물（伴侣动物），禁用 애완동물（玩赏动物）**——后者被视为过时甚至冒犯，这是韩国市场的红线；
- 敬语：建议统一 합니다体（服务类 App 惯例，正式得体）；选定后全文一致，不得混用 해요体；
- 韩文单词间有空格（与中文不同），标点用韩式（마침표/쉼표 与西文同形）；
- 常用词：강아지（小狗）、고양이（猫）、반려동물 앨범（宠物相册）；멍냥이 等网络口语慎用（保持服务语气）。

**产品与术语**
- 拼豆术语：비즈 도안（珠子图纸）或 아이론 비즈 도안（熨烫珠图纸音译），建议统一 비즈 도안；
- 隐私叙事：韩区用户对数据收集敏感（PIPA 法律环境），"모든 분석은 기기에서 처리됩니다"（所有分析在设备上处理）是有效表述；
- 宠物离世话题较敏感：彩虹桥等纪念功能文案用词温和，避免直接殡葬化表达。

**ASO 方向**
- 高价值词：반려동물 / 강아지 / 고양이 / 비즈 도안 / 사진 정리 / 반려동물 앨범；
- 竞争度中等，반려동물 前缀词族是流量入口。

### 4.5 法国 / 法语区（fr）— A 级

**市场特征**
- 法国宠物数量欧洲第一（约 3000 万只）；perles à repasser 认知良好；
- 法国用户对 App 设计感与文字质量要求高，文案质量差会直接掉分。

**语言与文案**
- **阴阳性**：UI 文案避免依赖词性变化的结构（如孤立形容词 "Nouveau!"），改用中性句式（"Nouveau contenu disponible" 或动词结构）；
- **法语通常比英文长 20-30%**：所有文案按 +30% 长度预算设计，关键 UI 实测不截断；
- 标点：法语句末冒号/问号/感叹号前有窄空格（espace insécable）——App 内由系统排版处理，**网页与商店元数据必须手动处理**；
- 数字：1 234,56（空格千分位 + 逗号小数）；
- 魁北克（fr-CA）用词差异（courriel vs email 等）首发以 fr-FR 为准，差异记录在案待 V1.x 评估。

**产品与术语**
- 品类词：perles à repasser（熨烫珠）；图纸 = modèle / plan；
- 隐私叙事："Traitement 100 % local"（全本地处理）是法语区强表述；
- 通用表达：animal de compagnie（宠物）、chat / chien。

**ASO 方向**
- 高价值词：perles à repasser / photos animaux / album chat / album chien；
- 法语关键词竞争度低——低成本高回报市场，值得做满 100 字符。

### 4.6 台湾 / 香港繁中（zh-Hant）— B 级

**市场特征**
- 台湾宠物约 250 万只，"毛小孩"文化成熟；拼豆在文创市集/手作圈认知良好；
- 香港宠物家庭渗透率高，但人口规模小。

**语言与文案**
- **繁中不是简中的字符转换**：词汇差异必须逐条处理（範本/模板、儲存/保存、相片/照片、資訊/信息、刪除/删除）；
- 首发以台湾用语为准：毛小孩、浪浪（流浪动物）、領養、相簿；
- 香港差异记录（如量词与部分用词），暂不做第二套繁中；
- 全角标点正确使用。

**产品与术语**
- 拼豆术语：台灣普遍稱「拼豆」「拼拼豆豆」，图纸 = 拼豆圖紙；
- 彩虹橋概念在台湾宠物界普遍，纪念文案可直接使用；
- 隐私叙事：台湾用户对個資（个资）敏感，"照片不會離開手機"表述有效。

**ASO 方向**
- 高价值词：寵物照片 / 寵物相簿 / 拼豆 / 拼豆圖紙 / 毛小孩 / 貓咪 / 狗狗；
- 繁中区竞争低，长尾词易拿排名。

### 4.7 中国大陆（zh-Hans）— 源语言 / 基本盘

- 保持现有文案与术语（拼豆图纸、宠物档案、成长时间线、往日回忆、时光机）；
- 校验现有文案中无"拟上架但未交付"的能力描述（ADR-0009 诚实原则，已由 App Store 文案去重收口）；
- 国内称呼多样（拼豆/拼拼豆豆/豆豆画/熨豆），产品内统一"拼豆"建立品牌一致性。

### 4.8 跨市场通用注意（技术 + 文化）

**技术**
- 日期/数字/日历：UI 展示一律走系统 locale（`Date.FormatStyle` / `Number.FormatStyle`），禁止硬编码格式串（现有 `utcCalendar` 纯逻辑仅用于测试确定性，展示路径不受影响）；
- 时区：通知、纪念日全部按用户本地时区调度（现有实现已满足）；
- **字体策略**：霞鹜文楷子集仅覆盖 GB2312 简体字符——**zh-Hant / ja / ko 不能使用文楷**（缺字）。需要在 `Typography.swift` 引入 locale 感知的 display 字体策略：zh-Hans 用文楷、en 用 Fraunces（已实现）、其余语言回退系统字体（ja 可评估 Hiragino Mincho 作为 display 候选）。**这是首发前必做的技术改造**；
- 长度预算：UI 按德语/法语最坏情况预留 30-40%，每语言在模拟器走查 Tab 标题、按钮、卡片、付费墙；
- 换行规则：CJK 逐字换行 vs 西文断词，长文本测试；
- 订阅价格：由 App Store Connect 价格层级按地区自动生效，App 内不硬编码金额文案（现有实现已满足）。

**文化**
- 节日营销节点（通知/推广文本可复用）：日本猫の日 2/22、日本犬の日 11/1、国际宠物日、各国圣诞/新年/感恩节；
- 宠物照片审美差异：日韩偏好可爱系、欧美偏好纪实与自然光——**截图素材选择按市场调整**，不要一套截图换语言就上；
- 法律合规：GDPR（欧盟/德法）、PIPA（韩国）、个保法（中国）、個資法（台湾）——在"不收集数据"的产品定位下合规负担很轻，但**隐私政策需按市场法律语境撰写**，不是机械翻译；
- 宠物离世（彩虹桥）文化接受度：英语区/日本/台湾普遍正面，韩国需更谨慎措辞，中国大陆以温和表达为主。

---

## 5. 翻译工作流

### 5.1 流程

```
术语表定稿（§8）→ knownRegions 追加 → 生成资产工作簿（§5.4）
  → 在 Excel 中按语言分批翻译（开发者自主，质量最高）→ import 回写
  → check 门禁（0 缺译 / 0 多余 / 格式）→ 模拟器截图走查
  → 商店元数据 / 截图 / 隐私政策 / 订阅描述 并行
```

### 5.4 Excel 资产工作簿（与工具链配套）

`docs/localization/global-localization.xlsx` 是唯一的人工翻译/资产管理入口，由 `tools/localization-assets.py` 生成（幂等，重新生成不覆盖 `.xcstrings` 中已有译文）：

```
python tools/localization-assets.py        # 重新生成工作簿
python tools/localization.py import docs/localization/global-localization.xlsx MiLens/Resources/Localizable.xcstrings --lang en
python tools/localization.py import docs/localization/global-localization.xlsx MiLens/Resources/InfoPlist.xcstrings --lang ja
```

工作簿 9 个 sheet：

| sheet | 内容 | 与工具链关系 |
|---|---|---|
| `Localizable` / `InfoPlist` | 全部 key × 7 语言（列结构与 `localization.py export` 一致）| 可直接 `import` 回写 `.xcstrings`；其他 sheet 不影响 import（按 sheet 名匹配）|
| `状态总览` | 6 类资产 × 7 语言完成度 | 人工维护 |
| `AppStore元数据` | 名称/副标题/描述/关键词/推广文本/审核备注 | 录入 ASC 时人工搬运 |
| `订阅产品描述` | 3 产品 × 显示名/描述 | 同上 |
| `隐私政策` | 章节级译文 | 同步到 `privacy-policy.html` |
| `截图素材` | 5 张截图 × 画面说明/叠加文案 | 制作截图时人工搬运 |
| `ASO关键词` | 每语言关键词 + 竞争度/长尾备注 | 录入 ASC 时人工搬运 |
| `术语表` | §8 核心术语 × 7 语言 | 翻译时参照 |

**state 列语义**（工具链原生约定）：初译由脚本以 `needs_review` 状态写入（当前 en 列 150 条已就位）；人工审校后**清空该语言 state 列**再 `import`，工具即按 `translated` 落库。数值/占位符/换行符在 Excel 中保持不变。

> 不想碰命令行时可用桌面 GUI：`python tools/localization-gui.py`（tkinter 工作台，见 DEVELOPMENT.md §4.5）——语言进度总览、缺译清单、一键导出/导入/check/生成工作簿；无显示环境用 `--self-check` 自检。

### 5.2 翻译顺序（按市场优先级）

| 批次 | 语言 | 理由 |
|---|---|---|
| 批次 0 | en | 第二参照语言，锁定术语的英文形态，其他语言翻译时对照 |
| 批次 1 | ja、zh-Hant | 两个高价值东亚市场，与中文语法结构接近度高 |
| 批次 2 | ko、de、fr | 剩余首发市场，de/fr 需要长度与词性专项处理 |

### 5.3 翻译质量要求

- 每语言翻译完成后通读一遍（开发者专业能力直接兑现）；
- 对照 en 版复查译义漂移（源语言简中 + 参照 en 双校验）；
- 付费墙、订阅说明、权限文案是**最高优先级质量对象**（直接关系转化与审核）；
- 数值/占位符/换行符完整性由 `localization.py check` 守护，翻译时勿改动 `%`、`{placeholder}`、`\n`。

---

## 6. 质量保证与门禁

| 门禁 | 工具 | 触发时机 | 通过标准 |
|---|---|---|---|
| key 完整性 | `localization.py check` | CI Lint 作业 + 本地 | 0 缺 key / 0 多余 key / 0 格式问题（已接入）|
| 缺译检测 | `localization.py check` | 同上 | 每语言 0 缺译（新增断言项）|
| 术语一致性 | 术语表人工走查 | 每语言翻译完成 | 核心术语逐条对照 §8 |
| 长度/截断 | 模拟器截图走查 | 每语言导入后 | 无截断、无溢出、无重叠（de/fr 必查）|
| 字体缺字 | 模拟器截图走查 | zh-Hant/ja/ko 导入后 | display 字体回退正确（§4.8 技术项）|
| 商店文案一致性 | 人工核对 | 上架前 | 描述/截图/审核备注与实际功能一致（诚实原则）|
| 隐私政策可访问 | 人工核对 | 上架前 | 各语言 URL 可访问、内容与 App 行为一致 |

> CI 需新增：`localization.py check` 增加"每语言缺译计数"输出并在 Lint 作业断言（当前 check 已支持多语言，补充断言即可，工作项见 §10）。

---

## 7. ASO 关键词策略（每语言）

| 语言 | 核心词族 | 长尾机会 | 竞争度 |
|---|---|---|---|
| zh-Hans | 宠物照片、宠物相册、拼豆、拼豆图纸 | 拼豆图纸（低竞争高意图）| 中 |
| zh-Hant | 寵物照片、拼豆、毛小孩、貓咪 | 拼豆圖紙、寵物相簿 | 低 |
| ja | ペット写真、アイロンビーズ、写真整理 | アイロンビーズ図案 | 中（ビーズ词族低）|
| ko | 반려동물、강아지、고양이、비즈 도안 | 비즈 도안、반려동물 앨범 | 中 |
| en | pet photos、perler beads、bead pattern | perler bead pattern（长尾）| 高 |
| fr | perles à repasser、photos animaux | album chat、perles à repasser modèle | 低 |
| de | Bügelperlen、Haustier、Fotoalbum | Bügelperlen Vorlagen | 低-中 |

**ASO 执行规则**
- 每语言 100 字符限额内做满，词间用逗号（App Store 语法）；
- 品牌词（MiLens/咪Lens）不占关键词位置；
- 首发后 2 周按搜索量数据调整一次，之后每月复查；
- 每个市场至少 5 条关键词覆盖"品类词 + 场景词 + 长尾意图词"。

---

## 8. 核心术语表（草案，翻译前定稿）

> 以下为方向性草案，实际定稿需在批次 0 翻译时锁定；一经定稿全文统一，不再改动。

| 中文（源）| en | ja | ko | de | fr | zh-Hant |
|---|---|---|---|---|---|---|
| 拼豆图纸 | bead pattern | アイロンビーズ図案 | 비즈 도안 | Bügelperlen-Vorlage | modèle de perles à repasser | 拼豆圖紙 |
| 拼豆工作室 | bead studio | ビーズスタジオ | 비즈 스튜디오 | Bead-Studio | studio de perles | 拼豆工作室 |
| 宠物档案 | pet profile | ペットのプロフィール | 반려동물 프로필 | Haustierprofil | profil de l'animal | 寵物檔案 |
| 成长时间线 | growth timeline | 成長タイムライン | 성장 타임라인 | Wachstumszeitleiste | chronologie de croissance | 成長時間軸 |
| 往日回忆 | memories | 思い出 | 추억 | Erinnerungen | souvenirs | 往日回憶 |
| 时光机 | time machine | タイムマシン | 타임머신 | Zeitmaschine | machine à remonter le temps | 時光機 |
| 照片不离开设备 | photos stay on device | 写真は端末から出ません | 모든 분석은 기기에서 처리됩니다 | Alle Fotos bleiben auf Ihrem Gerät | traitement 100 % local | 照片不會離開手機 |

---

## 9. 验收标准（首发前逐条打勾）

- [ ] `project.yml` knownRegions 含 7 语言，CI 构建通过
- [ ] 150+3 key × 6 语言全部翻译完成，`localization.py check` 0 缺译
- [ ] Typography locale 感知字体回退落地（文楷仅 zh-Hans，ja/ko/zh-Hant 不缺字）
- [ ] de/fr 长度专项走查：Tab/按钮/付费墙/卡片无截断溢出
- [ ] 术语表定稿且全文一致（§8 清单）
- [ ] App Store 元数据 7 语言录入（名称/副标题/描述/关键词/推广文本/审核备注）
- [ ] 订阅产品 3 个 × 7 语言本地化描述录入
- [ ] 截图 6 语言（或至少 en/ja/zh-Hans + 其余复用英文，后续补齐）文案覆盖层走查
- [ ] 隐私政策 7 语言可访问且与 App 行为一致
- [ ] 审核备注：英文通用版 + ja/ko/zh-Hant 当地语言版
- [ ] 各国注意要点 §4 逐条落实

---

## 10. 工作项清单（落地顺序）

| # | 工作项 | 依赖 | 预计 |
|---|---|---|---|
| 1 | knownRegions 追加 6 语言 | — | ✅ 已完成 |
| 2 | Typography locale 感知字体回退 | #1 | ✅ 已完成 |
| 2.5 | Excel 资产工作簿（`localization-assets.py` + 9 sheet，en 初译 150 条）| #1 | ✅ 已完成 |
| 3 | 术语表定稿（批次 0 前）| — | 0.5 天 |
| 4 | en 全量审校 + 导入 + check | #3 | 1 天 |
| 5 | ja + zh-Hant 翻译 | #4 | 1-2 天 |
| 6 | ko + de + fr 翻译（de/fr 长度专项）| #4 | 1-2 天 |
| 7 | `localization.py check` 补"每语言缺译"断言 + CI 接入 | #4 | 0.5 天 |
| 8 | 模拟器截图走查 × 7 语言（长度/字体/截断）| #5 #6 | 1 天 |
| 9 | 商店元数据 7 语言 + 订阅描述 + 审核备注 | #5 #6 | 1 天 |
| 10 | 截图素材本地化（文案覆盖层）| #9 | 1-2 天 |
| 11 | 隐私政策多语言 + 部署 | #9 | 1 天 |
| 12 | 首发后 2 周 ASO 复查 + 用户反馈迭代 | 上线 | 持续 |

> 合计约 8-11 个工作日（开发者自主翻译，外包/并行可压缩；截图与 ASC 录入可在等待翻译期间并行）。
