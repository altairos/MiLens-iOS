//  MiLens Museum Fix —— 「01 · Museum Archive / 博物馆典藏」(#692:1316)设计稿批量修正插件。
//
//  使用方式(本地开发插件):
//  1. Figma 桌面端 → Plugins → Development → Import plugin from manifest…
//  2. 选择本目录 manifest.json
//  3. 打开 MiLens iOS 文件的「01 · Museum Archive」页,Run「MiLens Museum Fix」
//  4. 勾选要应用的改动组(默认全开)→ Apply;一次运行生效,可整体 Ctrl+Z 撤销
//
//  依据:2026-08-14 设计评审(docs 待归档),节点数据取自 figma MCP get_figma_data。
//  原则:改属性为主;替换类改动「隐藏原节点 + 克隆新节点」,全部可逆;重名守卫支持安全重跑。
//
//  节点参考表(自查):
//  ─ Keepsake 4×5 (#695:1317)
//    696:1313 照片 308×286 @(26,26)        696:1314 朱砂藏印 26×26 @(26,323)
//    696:1315 Archive Rule 308×1 @(26,357)  696:1316 「MILENS · LIFE ARCHIVE」12/Medium #A89F97 @(62,327)
//    696:1317 「小满」32 LXGW @(26,365)      696:1318 「2026 · 夏」30 LXGW @(201,367) #1F1B18→#BC4727
//    696:1319 「喵星人 · 5 岁」13 #6B625B   696:1320 「XM—0521」13 #A89F97→#6B625B @(275,416)
//    710:1313 纸纤维 opacity .42→.34        711:1313 墨拓 opacity .40→.30
//    712:1313 藏印「M」Fraunces Bold 13 @(32.5,327)
//  ─ Namecard 16×10 (#695:1318)
//    696:1321 照片 320×398 @(26,26)         696:1322 Spine Rule 1×398 @(372,26) #ECE7E1→#E5DFD8
//    696:1323 Coral Tick 3×40 @(371,26)     696:1324 头行 14/Medium @(402,30)(去尾号 0521)
//    696:1325 「2026 · 夏」15 #BC4727        696:1326 「小满」44 LXGW @(402,62)
//    696:1327 身份 18 | 696:1328 擅长(富文本 22/Medium) | 696:1329 性格 16 #6B625B
//    696:1330 照护人 16 #A89F97 | 696:1331 MILENS ID 16 #A89F97  (1327-1331 隐藏,克隆两段式)
//    710:1380 纸纤维 .32 | 711:1317 墨拓 .28(不动,作对齐基准)
//  ─ Device Note (#695:1319): 695:1320 Overline | 695:1321 正文(克隆追加实现说明)

/* global figma */

// ---------- 常量 ----------

const COLORS = {
  coral: '#BC4727', // milensActionPrimary
  ink: '#1F1B18', // milensTextPrimary
  gray: '#6B625B', // milensTextSecondary
  faint: '#A89F97', // milensTextTertiary(仅装饰)
  rule: '#E5DFD8', // milensBorder
};

// 名片右栏两段式字段(x=402,内容宽 280)
const FIELD_X = 402;
const FIELD_CONTENT_W = 280;
const FIELD_LABEL_W = 200;
const FIELD_ROWS = [
  { label: '身份', content: '喵星人 · 5 岁 · 女孩子', labelY: 128, contentY: 150, style: 'regular16ink' },
  { label: '擅长', content: '窗边观察 · 晒太阳', labelY: 188, contentY: 208, style: 'medium22ink' },
  { label: '性格', content: '温柔 · 慢热 · 爱罐头', labelY: 250, contentY: 270, style: 'regular16ink' },
  { label: '照护人', content: 'MONA', labelY: 310, contentY: 330, style: 'regular16ink' },
  { label: 'MILENS ID', content: 'XM—0521', labelY: 392, contentY: 408, style: 'regular16gray' },
];

const G9_NOTES =
  '实现备注:\n' +
  '· MILENS ID 规则:XM = 名字拼音首字母,0521 = 生日 MMDD;缺生日回退建档日期。\n' +
  '· 照片裁切:Keepsake 横裁 308×286 / Namecard 竖裁 320×398,圆角 14。\n' +
  '· 字体映射:LXGW WenKai TC → App 内 GB 版;Noto Sans SC → 系统苹方。\n' +
  '· 导出基准:Keepsake 360×450 = 1080×1350 的 1/3;Namecard 720×450 → 2× = 1440×900。';

// ---------- 工具 ----------

function paint(hex) {
  const v = hex.replace('#', '');
  const num = parseInt(v, 16);
  return {
    type: 'SOLID',
    color: { r: ((num >> 16) & 255) / 255, g: ((num >> 8) & 255) / 255, b: (num & 255) / 255 },
  };
}

async function node(id) {
  const n = await figma.getNodeByIdAsync(id);
  return n;
}

/** 读取文本节点首字符字体并确保已加载(设置 characters 前必须)。 */
async function ensureFont(t) {
  if (!('getRangeFontName' in t)) return;
  const len = Math.max(t.characters.length, 1);
  let f = null;
  try {
    f = t.getRangeFontName(0, len);
  } catch (e) {
    f = null;
  }
  if (f && typeof f === 'object') await figma.loadFontAsync(f);
}

/** 克隆源文本节点并覆写样式(字体继承源节点,规避 createText 的字体缺失问题)。 */
async function makeText(opts) {
  const c = opts.source.clone();
  c.visible = true;
  c.name = opts.name;
  await ensureFont(c);
  if (opts.characters !== undefined) c.characters = opts.characters;
  if (opts.fontSize) c.fontSize = opts.fontSize;
  if (opts.hex) c.fills = [paint(opts.hex)];
  if (opts.lineHeightPx) c.lineHeight = { unit: 'PIXELS', value: opts.lineHeightPx };
  if (opts.letterSpacing0) c.letterSpacing = { unit: 'PIXELS', value: 0 };
  if (opts.width) {
    try {
      c.textAutoResize = 'HEIGHT';
      c.resize(opts.width, c.height);
    } catch (e) {
      /* 固定尺寸文本 resize 失败可容忍 */
    }
  }
  if (opts.x !== undefined && opts.y !== undefined) {
    c.x = opts.x;
    c.y = opts.y;
  }
  return c;
}

/** 按名称查找兄弟节点(重跑守卫)。 */
function findNamed(parent, name) {
  return parent ? parent.children.find((ch) => ch.name === name) : null;
}

// ---------- 各改动组 ----------

// G1 纹理强度统一(Keepsake → 与名片拉平)
async function applyG1(res) {
  const targets = [
    { id: '710:1313', opacity: 0.34, what: '纸纤维 opacity 0.42→0.34' },
    { id: '711:1313', opacity: 0.3, what: '墨拓 opacity 0.40→0.30' },
  ];
  for (const t of targets) {
    const n = await node(t.id);
    if (!n) {
      res.skip(t.what + '(节点不存在)');
      continue;
    }
    n.opacity = t.opacity;
    res.ok(t.what);
  }
}

// G2 季节统一朱砂 + 与名字同顶(Keepsake「2026 · 夏」)
async function applyG2(res) {
  const n = await node('696:1318');
  if (!n) {
    res.skip('季节朱砂(696:1318 不存在)');
    return;
  }
  n.fills = [paint(COLORS.coral)];
  n.y = 365;
  res.ok('「2026 · 夏」→ 朱砂 #BC4727,y 367→365');
}

// G3 分隔线 token 统一 #ECE7E1→#E5DFD8
async function applyG3(res) {
  const targets = [
    { id: '696:1315', what: 'Archive Rule' },
    { id: '696:1322', what: 'Spine Rule' },
  ];
  for (const t of targets) {
    const n = await node(t.id);
    if (!n) {
      res.skip(t.what + '(节点不存在)');
      continue;
    }
    n.fills = [paint(COLORS.rule)];
    res.ok(t.what + ' → #E5DFD8');
  }
}

// G4 名片右栏两段式重构(隐藏 5 个内联字段,克隆 5×标签 + 5×内容)
async function applyG4(res) {
  const parent = await node('695:1318');
  if (!parent) {
    res.skip('右栏两段式(名片画板 695:1318 不存在)');
    return;
  }
  // 克隆源:标签 ← 696:1316(12pt Medium #A89F97 带字距);内容 ← 696:1329(16pt Regular);擅长 ← 标签源改 22pt Medium
  const labelSrc = await node('696:1316');
  const contentSrc = await node('696:1329');
  if (!labelSrc || !contentSrc) {
    res.skip('右栏两段式(克隆源 696:1316 / 696:1329 不存在)');
    return;
  }

  const created = [];
  for (const row of FIELD_ROWS) {
    const labelName = 'Field / Label · ' + row.label;
    const contentName = 'Field / Content · ' + row.label;
    if (findNamed(parent, labelName) && findNamed(parent, contentName)) {
      res.skip(row.label + ' 两段式(已存在,跳过)');
      continue;
    }
    const label = await makeText({
      source: labelSrc, name: labelName, characters: row.label,
      x: FIELD_X, y: row.labelY, width: FIELD_LABEL_W,
    });
    let contentOpts;
    if (row.style === 'medium22ink') {
      contentOpts = {
        source: labelSrc, name: contentName, characters: row.content,
        x: FIELD_X, y: row.contentY, width: FIELD_CONTENT_W,
        fontSize: 22, hex: COLORS.ink, lineHeightPx: 24, letterSpacing0: true,
      };
    } else {
      contentOpts = {
        source: contentSrc, name: contentName, characters: row.content,
        x: FIELD_X, y: row.contentY, width: FIELD_CONTENT_W,
        fontSize: 16, hex: row.style === 'regular16gray' ? COLORS.gray : COLORS.ink,
        letterSpacing0: true,
      };
    }
    const content = await makeText(contentOpts);
    parent.appendChild(label);
    parent.appendChild(content);
    created.push(row.label);
  }
  if (created.length) res.ok('右栏两段式 ×' + created.length + '(' + created.join('/') + ')');

  // 隐藏原内联字段(克隆完成后再隐藏;1329 为克隆源,必须后置)
  const hideIds = ['696:1327', '696:1328', '696:1329', '696:1330', '696:1331'];
  for (const id of hideIds) {
    const n = await node(id);
    if (!n) {
      res.skip('隐藏 ' + id + '(不存在)');
      continue;
    }
    if (n.visible) {
      n.visible = false;
      res.ok('隐藏原字段 ' + id);
    }
  }
}

// G5 头行去重复编号
async function applyG5(res) {
  const n = await node('696:1324');
  if (!n) {
    res.skip('头行去编号(696:1324 不存在)');
    return;
  }
  await ensureFont(n);
  n.characters = 'MILENS PET PROFILE';
  res.ok('头行 →「MILENS PET PROFILE」(编号只在 ID 行出现一次)');
}

// G6 信息行对比度升档(#A89F97→#6B625B;G4 开启时 1330/1331 已隐藏,跳过)
async function applyG6(res, g4) {
  const targets = [{ id: '696:1320', what: 'Keepsake「XM—0521」' }];
  if (!g4) {
    targets.push({ id: '696:1330', what: '「照护人|MONA」' });
    targets.push({ id: '696:1331', what: '「MILENS ID|XM—0521」' });
  }
  for (const t of targets) {
    const n = await node(t.id);
    if (!n) {
      res.skip(t.what + '(节点不存在)');
      continue;
    }
    n.fills = [paint(COLORS.gray)];
    res.ok(t.what + ' → #6B625B');
  }
}

// G7 Keepsake 下部节奏微调(4px 基数)
async function applyG7(res) {
  const targets = [
    { id: '696:1314', y: 321, what: '藏印 y 323→321' },
    { id: '712:1313', y: 325, what: '藏印 M y 327→325' },
    { id: '696:1316', y: 325, what: 'LIFE ARCHIVE 行 y 327→325' },
    { id: '696:1319', y: 413, what: '物种行 y 414→413' },
    { id: '696:1320', y: 415, what: '编号行 y 416→415' },
  ];
  for (const t of targets) {
    const n = await node(t.id);
    if (!n) {
      res.skip(t.what + '(节点不存在)');
      continue;
    }
    n.y = t.y;
    res.ok(t.what);
  }
}

// G8 名片右上小藏印(朱砂方块 + Fraunces M)
async function applyG8(res) {
  const parent = await node('695:1318');
  const sealSrc = await node('696:1314');
  const mSrc = await node('712:1313');
  if (!parent || !sealSrc || !mSrc) {
    res.skip('小藏印(源节点或画板不存在)');
    return;
  }
  if (findNamed(parent, 'Seal / Mini')) {
    res.skip('小藏印(已存在)');
    return;
  }
  const seal = sealSrc.clone();
  seal.name = 'Seal / Mini';
  seal.visible = true;
  seal.resize(16, 16);
  seal.x = 600;
  seal.y = 30;
  parent.appendChild(seal);

  const m = mSrc.clone();
  m.name = 'Seal / Mini M';
  m.visible = true;
  m.fontSize = 8;
  m.x = 604;
  m.y = 32.5;
  parent.appendChild(m);
  res.ok('名片右上小藏印(16×16 @600,30 + 8pt M)');
}

// G10 纹理精修重绘 —— 用 createNodeFromSvg 生成原生矢量替换原 IMAGE-SVG。
// 原节点隐藏不删(可逆);新节点命名守卫;insertChild 保持原 z 序(纹理在照片之下)。

/** 确定性伪随机(mulberry32),重跑结果一致。 */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 全向纤维弧线:随机方向二次曲线,返回路径与中点/角度(供分叉)。 */
function fiber(rnd, w, h, lenMin, lenMax) {
  const x0 = rnd() * w;
  const y0 = rnd() * h;
  const len = lenMin + rnd() * (lenMax - lenMin);
  const ang = rnd() * Math.PI * 2; // 全向(纸浆纤维无主导走向)
  const bow = (rnd() - 0.5) * 16;
  const x1 = x0 + Math.cos(ang) * len;
  const y1 = y0 + Math.sin(ang) * len;
  const px = Math.cos(ang + Math.PI / 2) * bow;
  const py = Math.sin(ang + Math.PI / 2) * bow;
  return {
    y0: y0,
    mx: (x0 + x1) / 2 + px,
    my: (y0 + y1) / 2 + py,
    ang: ang,
    d:
      'M' + x0.toFixed(1) + ' ' + y0.toFixed(1) +
      ' Q' + ((x0 + x1) / 2 + px).toFixed(1) + ' ' + ((y0 + y1) / 2 + py).toFixed(1) +
      ' ' + x1.toFixed(1) + ' ' + y1.toFixed(1),
  };
}

/** 从纤维中点斜出的短枝(纸浆交织感)。 */
function branchFrom(rnd, f) {
  const a = f.ang + (rnd() < 0.5 ? 1 : -1) * (0.9 + rnd() * 0.7);
  const len = 7 + rnd() * 9;
  return (
    'M' + f.mx.toFixed(1) + ' ' + f.my.toFixed(1) +
    ' L' + (f.mx + Math.cos(a) * len).toFixed(1) + ' ' + (f.my + Math.sin(a) * len).toFixed(1)
  );
}

/**
 * 纸纤维 SVG 生成器(2026-08-14 截图评审精修)。
 * 诊断:连续均匀横线帘纹读作「信纸横格线」→ 廉价感。
 * 精修:帘纹退为断续残影(约 44px 一行,每行 1-2 段、段宽 24-60%);
 * 主视觉改为全向纤维束(长弧 18% 分叉 + 短绒底噪)+ 云状浆斑(手工纸分布不均)。
 * opts.reserved: [{y0,y1}] 文字保护区(纵区内只留帘纹与浆斑,不加杂纤维)。
 */
function buildFibersSvg(w, h, seed, opts) {
  const rnd = mulberry32(seed);
  const reserved = opts.reserved || [];
  let paths = ''; // 纤维色 #85796B(暖灰褐,卡底 #F2EFEA 上的纸浆色),各层内联

  // 云状浆斑:3 层同心椭圆叠透明度模拟软边(Figma 不支持 SVG blur)
  const clouds = 2 + Math.round(rnd() * 2);
  for (let i = 0; i < clouds; i++) {
    const cx = rnd() * w;
    const cy = rnd() * h;
    const rx = 34 + rnd() * 26;
    const rot = rnd() * 180;
    [
      [1, 0.028],
      [0.7, 0.04],
      [0.42, 0.05],
    ].forEach(function (l) {
      paths +=
        '<ellipse cx="' + cx.toFixed(1) + '" cy="' + cy.toFixed(1) +
        '" rx="' + (rx * l[0]).toFixed(1) + '" ry="' + (rx * l[0] * 0.34).toFixed(1) +
        '" transform="rotate(' + rot.toFixed(0) + ' ' + cx.toFixed(1) + ' ' + cy.toFixed(1) +
        ')" fill="#85796B" opacity="' + l[1] + '"/>';
    });
  }

  // 主纤维(全向长弧,纸面结构主视觉)
  const n1 = Math.round(w * h * (opts.density || 0.0038));
  for (let i = 0; i < n1; i++) {
    const f = fiber(rnd, w, h, 22, 56);
    if (inReserved(reserved, f.my)) continue;
    paths += '<path d="' + f.d + '" stroke="#85796B" stroke-width="0.9" opacity="0.32" fill="none" stroke-linecap="round"/>';
    if (rnd() < 0.18) {
      paths += '<path d="' + branchFrom(rnd, f) + '" stroke="#85796B" stroke-width="0.8" opacity="0.26" fill="none" stroke-linecap="round"/>';
    }
  }
  // 短绒纤维(细密底噪)
  const n2 = Math.round(n1 * 0.8);
  for (let i = 0; i < n2; i++) {
    const f = fiber(rnd, w, h, 9, 20);
    if (inReserved(reserved, f.my)) continue;
    paths += '<path d="' + f.d + '" stroke="#85796B" stroke-width="1.2" opacity="0.18" fill="none" stroke-linecap="round"/>';
  }
  // 帘纹(断续残影:近不可见,只留潜意识层「纸」的骨架;保护区也保留)
  const rows = Math.max(3, Math.round(h / 44));
  for (let i = 0; i < rows; i++) {
    const y = ((i + 0.5) * h) / rows + (rnd() - 0.5) * 6;
    const segs = rnd() < 0.55 ? 1 : 2;
    for (let s = 0; s < segs; s++) {
      const x0 = rnd() * w * 0.5;
      const x1 = Math.min(w, x0 + w * (0.24 + rnd() * 0.36));
      const dy = (rnd() - 0.5) * 2.2;
      paths +=
        '<path d="M' + x0.toFixed(1) + ' ' + y.toFixed(1) +
        ' C' + ((x0 + x1) / 3).toFixed(1) + ' ' + (y + dy).toFixed(1) +
        ' ' + (((x0 + x1) * 2) / 3).toFixed(1) + ' ' + (y - dy).toFixed(1) +
        ' ' + x1.toFixed(1) + ' ' + (y + dy * 0.4).toFixed(1) +
        '" stroke="#85796B" stroke-width="0.7" opacity="0.1" fill="none"/>';
    }
  }
  // 纤维结(短粗小段,最少量)
  const n3 = Math.round(w * h * 0.0006);
  for (let i = 0; i < n3; i++) {
    const x = rnd() * w;
    const y = rnd() * h;
    if (inReserved(reserved, y)) continue;
    const a = rnd() * Math.PI;
    const dx = Math.cos(a) * 2.2;
    const dy = Math.sin(a) * 2.2;
    paths +=
      '<path d="M' + (x - dx).toFixed(1) + ' ' + (y - dy).toFixed(1) +
      ' L' + (x + dx).toFixed(1) + ' ' + (y + dy).toFixed(1) +
      '" stroke="#85796B" stroke-width="1.6" opacity="0.3" stroke-linecap="round"/>';
  }
  return (
    '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">' +
    paths + '</svg>'
  );
}

function inReserved(reserved, y) {
  if (!reserved) return false;
  return reserved.some((r) => y >= r.y0 && y <= r.y1);
}

/** 单片竹叶:基窄、约 25% 最宽、先端急尖,叶身带轻微横弯(cv),两侧明显不对称
 *  (一侧较直一侧较弧——对称梭形读作矢量叶)。真墨竹图对照五修 2026-08-15。 */
function leafPath(x, y, len, angDeg, wid, cv) {
  const rad = (angDeg * Math.PI) / 180;
  const dx = Math.cos(rad);
  const dy = Math.sin(rad);
  const nx = -dy; // 法向
  const ny = dx;
  const c = cv || 0;
  const tx = x + dx * len + nx * len * c; // 叶尖横弯
  const ty = y + dy * len + ny * len * c + len * 0.05; // 略下垂
  const P = function (t, off) {
    return (x + dx * len * t + nx * off).toFixed(1) + ' ' + (y + dy * len * t + ny * off).toFixed(1);
  };
  return (
    'M' + x.toFixed(1) + ' ' + y.toFixed(1) +
    ' C' + P(0.18, wid * 0.95) + ' ' + P(0.5, wid * 0.4) + ' ' + tx.toFixed(1) + ' ' + ty.toFixed(1) +
    ' C' + P(0.52, -wid * 0.65) + ' ' + P(0.2, -wid * 0.5) + ' ' + x.toFixed(1) + ' ' + y.toFixed(1) + ' Z'
  );
}

/** 竹节:浓墨横钩笔。横笔带随机倾角/长短,两端钩笔为外弯 Q 曲线(真画钩有弹性,
 *  直 L 钩读作机械卡扣——2026-08-15 视觉反馈)。 */
function nodeMark(rnd, INK, x, y, w, hx, hy, sx, sy, op) {
  const tilt = (rnd() - 0.5) * 0.14;
  const ca = Math.cos(tilt), sa = Math.sin(tilt);
  const hx2 = hx * ca - hy * sa, hy2 = hx * sa + hy * ca;
  const hw = (w / 2) * (0.9 + rnd() * 0.2);
  const x0 = x - hx2 * hw, y0 = y - hy2 * hw;
  const x1 = x + hx2 * hw, y1 = y + hy2 * hw;
  const bow = w * 0.16;
  // 钩=横笔两端的顿笔回锋:短(长钩读作卡扣腿)、微外挑
  const hk = w * (0.14 + rnd() * 0.1);
  return (
    // 横笔洇垫:断口虚线宽笔(连续宽笔读作描边)
    '<path d="M' + x0.toFixed(1) + ' ' + y0.toFixed(1) +
    ' Q' + (x + sx * bow).toFixed(1) + ' ' + (y + sy * bow).toFixed(1) +
    ' ' + x1.toFixed(1) + ' ' + y1.toFixed(1) +
    '" stroke="' + INK + '" stroke-width="' + (w * 0.5).toFixed(2) +
    '" opacity="0.16" fill="none" stroke-linecap="round" stroke-dasharray="1.8 2.4" stroke-dashoffset="' + (rnd() * 3).toFixed(1) + '"/>' +
    '<path d="M' + x0.toFixed(1) + ' ' + y0.toFixed(1) +
    ' Q' + (x + sx * bow).toFixed(1) + ' ' + (y + sy * bow).toFixed(1) +
    ' ' + x1.toFixed(1) + ' ' + y1.toFixed(1) +
    '" stroke="' + INK + '" stroke-width="' + (w * 0.24).toFixed(2) +
    '" opacity="' + op + '" fill="none" stroke-linecap="round"/>' +
    '<path d="M' + x0.toFixed(1) + ' ' + y0.toFixed(1) +
    ' Q' + (x0 + sx * hk * 0.4 - hx2 * w * 0.1).toFixed(1) + ' ' + (y0 + sy * hk * 0.4 - hy2 * w * 0.1).toFixed(1) +
    ' ' + (x0 + sx * hk).toFixed(1) + ' ' + (y0 + sy * hk).toFixed(1) +
    '" stroke="' + INK + '" stroke-width="' + (w * 0.32).toFixed(2) +
    '" opacity="' + op + '" fill="none" stroke-linecap="round"/>' +
    '<path d="M' + x1.toFixed(1) + ' ' + y1.toFixed(1) +
    ' Q' + (x1 + sx * hk * 0.4 + hx2 * w * 0.1).toFixed(1) + ' ' + (y1 + sy * hk * 0.4 + hy2 * w * 0.1).toFixed(1) +
    ' ' + (x1 + sx * hk).toFixed(1) + ' ' + (y1 + sy * hk).toFixed(1) +
    '" stroke="' + INK + '" stroke-width="' + (w * 0.32).toFixed(2) +
    '" opacity="' + op + '" fill="none" stroke-linecap="round"/>'
  );
}

/** 淡墨主竿:三条平行笔道拼成宽竿(笔道间细缝=竖向飞白丝,真画竿面笔触);
 *  节位画浓墨横钩。竿淡叶浓是真墨竹的基本墨阶(2026-08-15 真画对照)。 */
function stalkInk(rnd, INK, st) {
  const rx = st.tip[0] - st.root[0];
  const ry = st.tip[1] - st.root[1];
  const L = Math.sqrt(rx * rx + ry * ry) || 1;
  const ux = rx / L, uy = ry / L;
  const nx = -uy, ny = ux; // 法向(横笔方向)
  const sx = -ux, sy = -uy; // 钩向(朝根/下)
  let out = '';
  const offs = [-0.31, 0, 0.31], ws = [0.36, 0.4, 0.36], ops = [0.11, 0.13, 0.11];
  for (let sI = 0; sI < 3; sI++) {
    for (let seg = 0; seg < 2; seg++) {
      // 笔锋参差:起/收笔沿竿向随机伸缩(齐头齐尾读作几何圆柱)
      let t0 = seg / 2, t1 = (seg + 1) / 2;
      if (seg === 0) t0 -= rnd() * 0.025;
      if (seg === 1) t1 += rnd() * 0.025;
      const tm = (t0 + t1) / 2;
      const wSeg = (st.wBase + (st.wTop - st.wBase) * tm) * ws[sI];
      const off = offs[sI] * (st.wBase + (st.wTop - st.wBase) * tm);
      const ax = st.root[0] + rx * t0 + nx * off;
      const ay = st.root[1] + ry * t0 + ny * off;
      const bx = st.root[0] + rx * t1 + nx * off;
      const by = st.root[1] + ry * t1 + ny * off;
      const bow = (rnd() - 0.5) * 3;
      out +=
        '<path d="M' + ax.toFixed(1) + ' ' + ay.toFixed(1) +
        ' Q' + ((ax + bx) / 2 + nx * bow).toFixed(1) + ' ' + ((ay + by) / 2 + ny * bow).toFixed(1) +
        ' ' + bx.toFixed(1) + ' ' + by.toFixed(1) +
        '" stroke="' + INK + '" stroke-width="' + wSeg.toFixed(2) +
        '" opacity="' + ops[sI] + '" fill="none" stroke-linecap="round"/>';
    }
  }
  // 边缘溢笔:竿缘外断口淡笔(笔毛出界破整齐边缘;连续细线读作描边)
  [-0.46, 0.46].forEach(function (o) {
    const off = o * st.wBase;
    out +=
      '<path d="M' + (st.root[0] + nx * off).toFixed(1) + ' ' + (st.root[1] + ny * off).toFixed(1) +
      ' L' + (st.tip[0] + nx * off * (st.wTop / st.wBase)).toFixed(1) + ' ' + (st.tip[1] + ny * off * (st.wTop / st.wBase)).toFixed(1) +
      '" stroke="' + INK + '" stroke-width="' + (st.wBase * 0.22).toFixed(2) +
      '" opacity="0.07" fill="none" stroke-linecap="round" stroke-dasharray="' + (5 + rnd() * 5).toFixed(1) + ' ' + (4 + rnd() * 6).toFixed(1) +
      '" stroke-dashoffset="' + (rnd() * 8).toFixed(1) + '"/>';
  });
  (st.nodes || []).forEach(function (t) {
    const x = st.root[0] + rx * t;
    const y = st.root[1] + ry * t;
    out += nodeMark(rnd, INK, x, y, (st.wBase + (st.wTop - st.wBase) * t) * 0.95, nx, ny, sx, sy, 0.55);
  });
  return out;
}

/** 浓墨细枝/细竿:分段、节间留断口、节处短粗钩笔(真画枝有节、断笔取势);
 *  每段拆两小段粗→细(起笔顿、收笔提),并垫一道宽淡洇边(破铁丝感)。 */
function branchInk(rnd, INK, pts, w) {
  let out = '';
  for (let i = 0; i < pts.length - 1; i++) {
    const ax = pts[i][0], ay = pts[i][1];
    const bx = pts[i + 1][0], by = pts[i + 1][1];
    const ddx = bx - ax, ddy = by - ay;
    const L = Math.sqrt(ddx * ddx + ddy * ddy) || 1;
    const ux = ddx / L, uy = ddy / L;
    const gap = i > 0 ? 1.6 : 0;
    const px = ax + ux * gap, py = ay + uy * gap;
    const bow = (rnd() - 0.5) * 4;
    const mx = (px + bx) / 2 - uy * bow, my = (py + by) / 2 + ux * bow;
    const wSeg = w * (1 - i * 0.14);
    // 洇边垫笔:断口宽虚线=笔毛洇墨碎边(连续宽笔读作描边)
    out +=
      '<path d="M' + px.toFixed(1) + ' ' + py.toFixed(1) +
      ' Q' + mx.toFixed(1) + ' ' + my.toFixed(1) + ' ' + bx.toFixed(1) + ' ' + by.toFixed(1) +
      '" stroke="' + INK + '" stroke-width="' + (wSeg * 2.4).toFixed(2) +
      '" opacity="0.1" fill="none" stroke-linecap="round" stroke-dasharray="' + (2 + rnd() * 2).toFixed(1) + ' ' + (3 + rnd() * 3).toFixed(1) +
      '" stroke-dashoffset="' + (rnd() * 4).toFixed(1) + '"/>';
    // 主笔:粗→细两小段
    out +=
      '<path d="M' + px.toFixed(1) + ' ' + py.toFixed(1) +
      ' Q' + ((px + mx) / 2).toFixed(1) + ' ' + ((py + my) / 2).toFixed(1) + ' ' + mx.toFixed(1) + ' ' + my.toFixed(1) +
      '" stroke="' + INK + '" stroke-width="' + (wSeg * 1.2).toFixed(2) +
      '" opacity="0.5" fill="none" stroke-linecap="round"/>' +
      '<path d="M' + mx.toFixed(1) + ' ' + my.toFixed(1) +
      ' Q' + ((mx + bx) / 2).toFixed(1) + ' ' + ((my + by) / 2).toFixed(1) + ' ' + bx.toFixed(1) + ' ' + by.toFixed(1) +
      '" stroke="' + INK + '" stroke-width="' + (wSeg * 0.8).toFixed(2) +
      '" opacity="0.5" fill="none" stroke-linecap="round"/>';
    if (i > 0) {
      // 节处顿笔:短粗 Q 钩(微弯,非直 L)
      out +=
        '<path d="M' + ax.toFixed(1) + ' ' + ay.toFixed(1) +
        ' Q' + (ax + ux * 1.5 - uy * 1.2).toFixed(1) + ' ' + (ay + uy * 1.5 + ux * 1.2).toFixed(1) +
        ' ' + (ax + ux * 3).toFixed(1) + ' ' + (ay + uy * 3).toFixed(1) +
        '" stroke="' + INK + '" stroke-width="' + (w * 1.7).toFixed(2) +
        '" opacity="0.55" fill="none" stroke-linecap="round"/>';
    }
  }
  return out;
}

/** 细梢:竿节到叶组锚点的细枝,中段两折点(真画梢多折、非直弧),叶生梢头。 */
function twigInk(rnd, INK, tw) {
  const m1x = tw.from[0] + (tw.to[0] - tw.from[0]) * 0.38 + (rnd() - 0.5) * 7;
  const m1y = tw.from[1] + (tw.to[1] - tw.from[1]) * 0.38 + (rnd() - 0.5) * 7;
  const m2x = tw.from[0] + (tw.to[0] - tw.from[0]) * 0.72 + (rnd() - 0.5) * 6;
  const m2y = tw.from[1] + (tw.to[1] - tw.from[1]) * 0.72 + (rnd() - 0.5) * 6;
  return branchInk(rnd, INK, [tw.from, [m1x, m1y], [m2x, m2y], tw.to], tw.w || 1.4);
}

/**
 * 竹叶墨拓 SVG 生成器(2026-08-15 五修:照真墨竹图重构墨阶与结构)。
 * 真画形式语言:淡墨宽竿(竖向飞白)+ 浓墨横钩节 + 浓墨细枝有节 + 细长叶(≈4.5:1)交叉叠压;
 * 墨阶:叶最浓 > 枝/节浓 > 竿淡。此前「深色实心竿+椭圆节+宽叶」全反。
 * 叶叠压处因半透明自然加深=真画积墨,不再刻意排布扇形。
 */
function buildBambooSvg(w, h, seed, layout) {
  const rnd = mulberry32(seed);
  const INK = '#1F1B18';
  let paths = '';
  // z 序:淡竿 → 浓细竿 → 细梢 → 叶(叶最上最浓)
  if (layout.stalk) paths += stalkInk(rnd, INK, layout.stalk);
  if (layout.darkStalk) paths += branchInk(rnd, INK, layout.darkStalk.pts, layout.darkStalk.w);
  (layout.twigs || []).forEach(function (tw) {
    paths += twigInk(rnd, INK, tw);
  });
  (layout.groups || []).forEach(function (g) {
    g.leaves.forEach(function (lf) {
      const len = lf.len * (0.94 + rnd() * 0.12);
      const wid = len * 0.22; // 细长叶 ~4.5:1(真画对照,0.3 过宽)
      const ang = lf.ang + (rnd() - 0.5) * 16; // 角度扰动破规律排布
      const cv = (rnd() - 0.5) * 0.2; // 叶身横弯方向/幅度随机
      const op = lf.tone === 0 ? 0.8 : lf.tone === 1 ? 0.45 : 0.26;
      // 洇墨:放大半透明垫底(真画叶缘墨涇)
      paths +=
        '<path d="' + leafPath(g.x, g.y, len * 1.05, ang, wid * 1.15, cv) +
        '" fill="' + INK + '" opacity="' + (op * 0.15).toFixed(2) + '"/>';
      paths += '<path d="' + leafPath(g.x, g.y, len, ang, wid, cv) + '" fill="' + INK + '" opacity="' + op + '"/>';
      // 叶缘洇毛:断口轮廓笔(墨从叶缘洇出的碎毛边)
      paths +=
        '<path d="' + leafPath(g.x, g.y, len, ang, wid, cv) + '" fill="none" stroke="' + INK +
        '" stroke-width="1.3" stroke-dasharray="' + (1.6 + rnd() * 1.4).toFixed(1) + ' ' + (2 + rnd() * 2).toFixed(1) +
        '" stroke-dashoffset="' + (rnd() * 3).toFixed(1) + '" opacity="' + (op * 0.22).toFixed(2) + '"/>';
      // 笔毛擦影:错位窄半透明叶(真画叶缘笔毛分叉感)
      paths +=
        '<path d="' + leafPath(g.x + 0.8, g.y + 0.6, len * 0.96, ang + 2.5, wid * 0.75, cv) +
        '" fill="' + INK + '" opacity="' + (op * 0.35).toFixed(2) + '"/>';
    });
  });
  return (
    '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">' +
    paths + '</svg>'
  );
}

// 四张纹理的布局参数(z 序:先纤维后墨拓,均插在照片之下)
// 竹叶 = 显式「个字形」叶组:每组中间叶长、外侧叶短、角度非均匀;
// Keepsake 竹叶缩到右下角空区(x∈[300,360] y∈[403,450]),避开「2026·夏」(x∈[201,333] y∈[365,401])。
// 出底/出右的叶尖被 viewBox 裁切,读作拓片贴边,自然。
const TEXTURE_JOBS = [
  {
    boardId: '695:1317', oldId: '710:1313', name: 'Paper Fibers / Refined',
    x: 0, y: 312, w: 360, h: 138, opacity: 0.5,
    kind: 'fibers', seed: 20260814, density: 0.0038,
    // 保护区覆盖下半部全部文字行(印/LIFE/小满/2026·夏/喵星人,绝对 y∈[323,428]):
    // 这些行上只留帘纹与浆斑,纤维(长纤维/短绒/纤维结)全部避开——
    // 纤维从文字上穿过是「视觉不干净」的另一半来源(2026-08-14 用户反馈)。
    reserved: [{ y0: 8, y1: 120 }],
  },
  {
    boardId: '695:1317', oldId: '711:1313', name: 'Bamboo Rubbing / Refined',
    x: 290, y: 395, w: 70, h: 55, opacity: 0.68,
    kind: 'bamboo', seed: 7211,
    layout: {
      // 角落小簇:一根细梢(右缘长入、中段微折)+ 梢头/梢中两簇叶,无竿(70x55 容不下竿);
      // 全部叶片与「2026·夏」框(x≤333,y≤401)保持 ≥12pt 间隙。
      twigs: [{ from: [66, 18], to: [30, 33] }],
      groups: [
        { x: 30, y: 33, leaves: [
          { ang: 140, len: 26, tone: 0 },
          { ang: 172, len: 22, tone: 0 },
          { ang: 108, len: 18, tone: 1 },
          { ang: 205, len: 15, tone: 2 },
        ] },
        { x: 52, y: 25, leaves: [
          { ang: 96, len: 16, tone: 1 },
          { ang: 132, len: 13, tone: 2 },
        ] },
      ],
    },
  },
  {
    boardId: '695:1318', oldId: '710:1380', name: 'Paper Fibers / Refined',
    x: 374, y: 0, w: 346, h: 450, opacity: 0.32,
    kind: 'fibers', seed: 20260815, density: 0.0018, // 右栏有墨竹主体时纸纹让位:0.45 读作「乱草脏底」(2026-08-15 语境验证)
    reserved: [
      { y0: 28, y1: 48 }, // 头行 MiLens · PAL-FILE
      { y0: 60, y1: 112 }, // 「小满」44pt 大字
    ],
  },
  {
    boardId: '695:1318', oldId: '711:1317', name: 'Bamboo Rubbing / Refined',
    x: 506, y: 0, w: 214, h: 450, opacity: 0.72,
    kind: 'bamboo', seed: 7212,
    layout: {
      // 真墨竹图式(2026-08-15 五修):淡墨宽竿三节 + 浓墨细竿(有节)右侧并行 +
      // 细梢从竿节伸向叶组;叶细长交叉、浓淡混排。竿淡(0.11-0.13)、枝节浓(0.5-0.55)、叶最浓(0.8)。
      stalk: { root: [64, 456], tip: [118, -6], wBase: 15, wTop: 10.5, nodes: [0.2, 0.48, 0.76] },
      darkStalk: { pts: [[170, 456], [152, 356], [140, 262], [130, 168], [122, 84]], w: 2.4 },
      twigs: [
        { from: [75, 364], to: [44, 340] },
        { from: [90, 234], to: [150, 214] },
        { from: [105, 105], to: [62, 84] },
        { from: [105, 105], to: [164, 62] },
        { from: [130, 168], to: [96, 142] },
      ],
      groups: [
        // 节1 梢头·左垂簇
        { x: 44, y: 340, leaves: [
          { ang: 150, len: 34, tone: 0 },
          { ang: 178, len: 30, tone: 1 },
          { ang: 118, len: 24, tone: 1 },
          { ang: 205, len: 20, tone: 2 },
        ] },
        // 节2 梢头·右展簇
        { x: 150, y: 214, leaves: [
          { ang: 20, len: 36, tone: 0 },
          { ang: 52, len: 30, tone: 1 },
          { ang: -6, len: 26, tone: 1 },
          { ang: 82, len: 22, tone: 2 },
        ] },
        // 节3 双梢·左上簇
        { x: 62, y: 84, leaves: [
          { ang: 160, len: 32, tone: 0 },
          { ang: 128, len: 26, tone: 1 },
          { ang: 192, len: 24, tone: 2 },
        ] },
        // 节3 双梢·右上簇
        { x: 164, y: 62, leaves: [
          { ang: 30, len: 30, tone: 0 },
          { ang: 62, len: 24, tone: 1 },
          { ang: 2, len: 22, tone: 2 },
        ] },
        // 浓细竿中段·左簇
        { x: 96, y: 142, leaves: [
          { ang: 140, len: 28, tone: 0 },
          { ang: 170, len: 24, tone: 1 },
          { ang: 108, len: 18, tone: 2 },
        ] },
        // 浓细竿下节·右小簇
        { x: 152, y: 356, leaves: [
          { ang: 40, len: 26, tone: 1 },
          { ang: 72, len: 20, tone: 2 },
        ] },
      ],
    },
  },
];

async function applyG10(res) {
  // 先清理历史孤儿:此前异常运行残留在页面根的 Refined 节点(它们不在画板内,重跑会堆积)
  const names = TEXTURE_JOBS.map(function (j) {
    return j.name;
  });
  figma.currentPage.children.forEach(function (n) {
    if (names.indexOf(n.name) >= 0) {
      try {
        n.remove();
        res.ok('清理残留孤儿 ' + n.name);
      } catch (e) {
        /* 容忍 */
      }
    }
  });
  for (const job of TEXTURE_JOBS) {
    const board = await node(job.boardId);
    const old = await node(job.oldId);
    if (!board) {
      res.skip(job.name + '(画板不存在)');
      continue;
    }
    // 幂等替换:重跑时先删旧 Refined 节点再重建(否则迭代期间永远看不到新版)
    const existing = findNamed(board, job.name);
    if (existing) {
      try {
        existing.remove();
        res.ok('替换旧版 ' + job.name);
      } catch (e) {
        res.skip(job.name + '(旧节点删除失败:' + (e && e.message) + ')');
        continue;
      }
    }
    let svg;
    try {
      svg =
        job.kind === 'fibers'
          ? buildFibersSvg(job.w, job.h, job.seed, { density: job.density, reserved: job.reserved })
          : buildBambooSvg(job.w, job.h, job.seed, job.layout);
    } catch (e) {
      res.skip(job.name + '(SVG 生成失败:' + (e && e.message) + ')');
      continue;
    }
    let created;
    try {
      created = figma.createNodeFromSvg(svg);
    } catch (e) {
      res.skip(job.name + '(createNodeFromSvg 失败:' + (e && e.message) + ')');
      continue;
    }
    created.name = job.name;
    created.opacity = job.opacity;
    // 顺序关键:必须「先 reparent 再设坐标」。insertChild 会保持节点在画布上的绝对位置,
    // 若先设 x/y,页面根的 (0,312) 会被换算成相对画板的负坐标,纹理飞出画板。
    // 签名是 insertChild(index, child)——index 在前(2026-08-14 官方文档核对,旧记忆里的 (node,index) 是错的)
    const idx = old && old.parent === board ? board.children.indexOf(old) : 0;
    try {
      board.insertChild(idx, created);
    } catch (e) {
      res.skip(job.name + '(insertChild 失败:' + (e && e.message) + ')');
      try {
        created.remove();
      } catch (e2) {
        /* 容忍 */
      }
      continue;
    }
    created.x = job.x;
    created.y = job.y;
    try {
      created.resize(job.w, job.h);
    } catch (e) {
      /* SVG 自带正确尺寸,resize 失败容忍 */
    }
    if (old) old.visible = false;
    res.ok(job.name + ' ' + job.w + '×' + job.h + ' @(' + job.x + ',' + job.y + ') opacity ' + job.opacity);
  }
}

// G9 Device Note 追加实现说明(克隆 695:1321,auto-layout 自动排到末尾)
async function applyG9(res) {
  const src = await node('695:1321');
  if (!src) {
    res.skip('Device Note 说明(695:1321 不存在)');
    return;
  }
  const parent = src.parent;
  if (findNamed(parent, 'Device Note · Implementation Notes')) {
    res.skip('Device Note 说明(已存在)');
    return;
  }
  const note = await makeText({
    source: src,
    name: 'Device Note · Implementation Notes',
    characters: G9_NOTES,
    width: 416,
  });
  res.ok('Device Note 追加实现说明(ID 规则/裁切/字体映射/导出基准)');
}

// ---------- 入口 ----------

figma.showUI(__html__, { width: 340, height: 520, themeColors: true });

figma.ui.onmessage = async (msg) => {
  if (msg.type === 'close') {
    figma.closePlugin();
    return;
  }
  if (msg.type !== 'apply') return;

  const g = msg.groups;
  const res = {
    applied: 0,
    skipped: 0,
    notes: [],
    ok(what) {
      this.applied++;
      this.notes.push('✓ ' + what);
    },
    skip(why) {
      this.skipped++;
      this.notes.push('– ' + why);
    },
  };

  try {
    if (g.g1) await applyG1(res);
    if (g.g2) await applyG2(res);
    if (g.g3) await applyG3(res);
    if (g.g4) await applyG4(res);
    if (g.g5) await applyG5(res);
    if (g.g6) await applyG6(res, !!g.g4);
    if (g.g7) await applyG7(res);
    if (g.g8) await applyG8(res);
    if (g.g9) await applyG9(res);
    if (g.g10) await applyG10(res);
    figma.notify('MiLens Museum Fix:应用 ' + res.applied + ' 项,跳过 ' + res.skipped + ' 项');
  } catch (e) {
    // 异常也必须发回 result,否则 UI 的 Apply 按钮永久禁用(「点了没反应」的根因)
    res.notes.push('✗ 运行出错:' + (e && e.message ? e.message : String(e)));
    figma.notify('MiLens Museum Fix:出错,详见面板', { error: true });
  }
  figma.ui.postMessage({ type: 'result', applied: res.applied, skipped: res.skipped, notes: res.notes });
};
