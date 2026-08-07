// 此文件由 .tmp_gen_mard.py 从源端 BeadPaletteMard.ets 自动生成。
// 不要手动编辑；源端 MARD 色卡变更后重新运行生成脚本并核对条目数。
// 数据来源：beadcolors (github.com/maxcleme/beadcolors)，source: community, confidence: 0.7。
import Foundation

// MARK: - BeadColorTag

/// MARD 宠物色卡基础标签。对应源端 `BeadColorTag`。
public enum BeadColorTag: String, Sendable {
    case warmWhite = "warm_white"
    case neutralWhite = "neutral_white"
    case cream
    case warmGray = "warm_gray"
    case coolGray = "cool_gray"
    case black
    case softBlack = "soft_black"
    case orangeFur = "orange_fur"
    case brownFur = "brown_fur"
    case pinkNose = "pink_nose"
    case eyeColor = "eye_color"
    case background
    case avoidForFur = "avoid_for_fur"
    case blueTint = "blue_tint"
    case fluorescent
}

// MARK: - MARD 全部 291 色定义

/// MARD 全部 291 色。对应源端 `MARD_ALL_COLORS`。
public let mardAllColors: [BeadColor] = [
    BeadColor(id: "A1", name: "奶油黄", rgb: RGBColor(250, 244, 200), symbol: "A1", brand: "MARD"),
    BeadColor(id: "A2", name: "浅奶黄", rgb: RGBColor(255, 255, 213), symbol: "A2", brand: "MARD"),
    BeadColor(id: "A3", name: "浅黄", rgb: RGBColor(254, 255, 139), symbol: "A3", brand: "MARD"),
    BeadColor(id: "A4", name: "明黄", rgb: RGBColor(251, 237, 86), symbol: "A4", brand: "MARD"),
    BeadColor(id: "A5", name: "深黄", rgb: RGBColor(244, 215, 56), symbol: "A5", brand: "MARD"),
    BeadColor(id: "A6", name: "浅橘", rgb: RGBColor(254, 172, 76), symbol: "A6", brand: "MARD"),
    BeadColor(id: "A7", name: "橘黄", rgb: RGBColor(254, 139, 76), symbol: "A7", brand: "MARD"),
    BeadColor(id: "A8", name: "金黄", rgb: RGBColor(255, 218, 69), symbol: "A8", brand: "MARD"),
    BeadColor(id: "A9", name: "橘色", rgb: RGBColor(255, 153, 91), symbol: "A9", brand: "MARD"),
    BeadColor(id: "A10", name: "深橘", rgb: RGBColor(247, 124, 49), symbol: "A10", brand: "MARD"),
    BeadColor(id: "A11", name: "淡黄", rgb: RGBColor(255, 221, 153), symbol: "A11", brand: "MARD"),
    BeadColor(id: "A12", name: "浅橘肉", rgb: RGBColor(254, 159, 114), symbol: "A12", brand: "MARD"),
    BeadColor(id: "A13", name: "暖橘", rgb: RGBColor(255, 195, 101), symbol: "A13", brand: "MARD"),
    BeadColor(id: "A14", name: "橘红", rgb: RGBColor(253, 84, 61), symbol: "A14", brand: "MARD"),
    BeadColor(id: "A15", name: "柠檬黄", rgb: RGBColor(255, 243, 101), symbol: "A15", brand: "MARD"),
    BeadColor(id: "A16", name: "浅柠檬", rgb: RGBColor(255, 255, 159), symbol: "A16", brand: "MARD"),
    BeadColor(id: "A17", name: "黄橘", rgb: RGBColor(255, 227, 110), symbol: "A17", brand: "MARD"),
    BeadColor(id: "A18", name: "暖杏橘", rgb: RGBColor(254, 190, 125), symbol: "A18", brand: "MARD"),
    BeadColor(id: "A19", name: "珊瑚橘", rgb: RGBColor(253, 124, 114), symbol: "A19", brand: "MARD"),
    BeadColor(id: "A20", name: "琥珀", rgb: RGBColor(255, 213, 104), symbol: "A20", brand: "MARD"),
    BeadColor(id: "A21", name: "杏橘", rgb: RGBColor(255, 227, 149), symbol: "A21", brand: "MARD"),
    BeadColor(id: "A22", name: "黄绿", rgb: RGBColor(244, 245, 125), symbol: "A22", brand: "MARD"),
    BeadColor(id: "A23", name: "沙色", rgb: RGBColor(230, 201, 183), symbol: "A23", brand: "MARD"),
    BeadColor(id: "A24", name: "青柠", rgb: RGBColor(247, 248, 162), symbol: "A24", brand: "MARD"),
    BeadColor(id: "A25", name: "蜜橘", rgb: RGBColor(255, 214, 125), symbol: "A25", brand: "MARD"),
    BeadColor(id: "A26", name: "向日葵", rgb: RGBColor(255, 200, 48), symbol: "A26", brand: "MARD"),
    BeadColor(id: "B1", name: "黄绿", rgb: RGBColor(230, 238, 49), symbol: "B1", brand: "MARD"),
    BeadColor(id: "B2", name: "亮绿", rgb: RGBColor(99, 243, 71), symbol: "B2", brand: "MARD"),
    BeadColor(id: "B3", name: "浅绿", rgb: RGBColor(158, 247, 128), symbol: "B3", brand: "MARD"),
    BeadColor(id: "B4", name: "草绿", rgb: RGBColor(93, 224, 53), symbol: "B4", brand: "MARD"),
    BeadColor(id: "B5", name: "翠绿", rgb: RGBColor(53, 227, 82), symbol: "B5", brand: "MARD"),
    BeadColor(id: "B6", name: "薄荷绿", rgb: RGBColor(101, 226, 166), symbol: "B6", brand: "MARD"),
    BeadColor(id: "B7", name: "青绿", rgb: RGBColor(61, 175, 128), symbol: "B7", brand: "MARD"),
    BeadColor(id: "B8", name: "深绿", rgb: RGBColor(28, 156, 79), symbol: "B8", brand: "MARD"),
    BeadColor(id: "B9", name: "墨绿", rgb: RGBColor(39, 82, 58), symbol: "B9", brand: "MARD"),
    BeadColor(id: "B10", name: "浅青绿", rgb: RGBColor(149, 211, 194), symbol: "B10", brand: "MARD"),
    BeadColor(id: "B11", name: "橄榄绿", rgb: RGBColor(93, 114, 42), symbol: "B11", brand: "MARD"),
    BeadColor(id: "B12", name: "深墨绿", rgb: RGBColor(22, 111, 65), symbol: "B12", brand: "MARD"),
    BeadColor(id: "B13", name: "嫩绿", rgb: RGBColor(202, 235, 123), symbol: "B13", brand: "MARD"),
    BeadColor(id: "B14", name: "荧光绿", rgb: RGBColor(173, 233, 70), symbol: "B14", brand: "MARD"),
    BeadColor(id: "B15", name: "暗绿", rgb: RGBColor(46, 81, 50), symbol: "B15", brand: "MARD"),
    BeadColor(id: "B16", name: "淡草绿", rgb: RGBColor(197, 237, 156), symbol: "B16", brand: "MARD"),
    BeadColor(id: "B17", name: "军绿", rgb: RGBColor(155, 177, 58), symbol: "B17", brand: "MARD"),
    BeadColor(id: "B18", name: "酸绿", rgb: RGBColor(230, 238, 73), symbol: "B18", brand: "MARD"),
    BeadColor(id: "B19", name: "碧绿", rgb: RGBColor(36, 184, 140), symbol: "B19", brand: "MARD"),
    BeadColor(id: "B20", name: "冰绿", rgb: RGBColor(194, 240, 204), symbol: "B20", brand: "MARD"),
    BeadColor(id: "B21", name: "深青", rgb: RGBColor(21, 106, 107), symbol: "B21", brand: "MARD"),
    BeadColor(id: "B22", name: "暗青", rgb: RGBColor(11, 60, 67), symbol: "B22", brand: "MARD"),
    BeadColor(id: "B23", name: "暗橄榄", rgb: RGBColor(48, 58, 33), symbol: "B23", brand: "MARD"),
    BeadColor(id: "B24", name: "嫩黄绿", rgb: RGBColor(238, 252, 165), symbol: "B24", brand: "MARD"),
    BeadColor(id: "B25", name: "灰绿", rgb: RGBColor(78, 132, 109), symbol: "B25", brand: "MARD"),
    BeadColor(id: "B26", name: "芥末绿", rgb: RGBColor(141, 122, 53), symbol: "B26", brand: "MARD"),
    BeadColor(id: "B27", name: "豆绿", rgb: RGBColor(204, 225, 175), symbol: "B27", brand: "MARD"),
    BeadColor(id: "B28", name: "水绿", rgb: RGBColor(158, 229, 185), symbol: "B28", brand: "MARD"),
    BeadColor(id: "B29", name: "苔绿", rgb: RGBColor(197, 226, 84), symbol: "B29", brand: "MARD"),
    BeadColor(id: "B30", name: "嫩叶绿", rgb: RGBColor(226, 252, 177), symbol: "B30", brand: "MARD"),
    BeadColor(id: "B31", name: "草黄绿", rgb: RGBColor(176, 231, 146), symbol: "B31", brand: "MARD"),
    BeadColor(id: "B32", name: "黄绿灰", rgb: RGBColor(156, 171, 90), symbol: "B32", brand: "MARD"),
    BeadColor(id: "C1", name: "浅冰蓝", rgb: RGBColor(232, 255, 231), symbol: "C1", brand: "MARD"),
    BeadColor(id: "C2", name: "水蓝", rgb: RGBColor(169, 249, 252), symbol: "C2", brand: "MARD"),
    BeadColor(id: "C3", name: "天蓝", rgb: RGBColor(160, 226, 251), symbol: "C3", brand: "MARD"),
    BeadColor(id: "C4", name: "亮蓝", rgb: RGBColor(65, 204, 255), symbol: "C4", brand: "MARD"),
    BeadColor(id: "C5", name: "湖蓝", rgb: RGBColor(1, 172, 235), symbol: "C5", brand: "MARD"),
    BeadColor(id: "C6", name: "钴蓝", rgb: RGBColor(80, 170, 240), symbol: "C6", brand: "MARD"),
    BeadColor(id: "C7", name: "宝蓝", rgb: RGBColor(54, 119, 210), symbol: "C7", brand: "MARD"),
    BeadColor(id: "C8", name: "深蓝", rgb: RGBColor(15, 84, 192), symbol: "C8", brand: "MARD"),
    BeadColor(id: "C9", name: "藏蓝", rgb: RGBColor(50, 75, 202), symbol: "C9", brand: "MARD"),
    BeadColor(id: "C10", name: "青蓝", rgb: RGBColor(62, 188, 226), symbol: "C10", brand: "MARD"),
    BeadColor(id: "C11", name: "蓝绿", rgb: RGBColor(40, 221, 222), symbol: "C11", brand: "MARD"),
    BeadColor(id: "C12", name: "暗深蓝", rgb: RGBColor(28, 51, 77), symbol: "C12", brand: "MARD"),
    BeadColor(id: "C13", name: "浅蓝", rgb: RGBColor(205, 232, 255), symbol: "C13", brand: "MARD"),
    BeadColor(id: "C14", name: "冰蓝", rgb: RGBColor(213, 253, 255), symbol: "C14", brand: "MARD"),
    BeadColor(id: "C15", name: "蒂芙尼", rgb: RGBColor(34, 196, 198), symbol: "C15", brand: "MARD"),
    BeadColor(id: "C16", name: "靛蓝", rgb: RGBColor(21, 87, 168), symbol: "C16", brand: "MARD"),
    BeadColor(id: "C17", name: "亮湖蓝", rgb: RGBColor(4, 209, 246), symbol: "C17", brand: "MARD"),
    BeadColor(id: "C18", name: "深藏青", rgb: RGBColor(29, 51, 68), symbol: "C18", brand: "MARD"),
    BeadColor(id: "C19", name: "中青", rgb: RGBColor(24, 135, 162), symbol: "C19", brand: "MARD"),
    BeadColor(id: "C20", name: "海蓝", rgb: RGBColor(23, 109, 175), symbol: "C20", brand: "MARD"),
    BeadColor(id: "C21", name: "雾蓝", rgb: RGBColor(190, 221, 255), symbol: "C21", brand: "MARD"),
    BeadColor(id: "C22", name: "灰蓝", rgb: RGBColor(103, 180, 190), symbol: "C22", brand: "MARD"),
    BeadColor(id: "C23", name: "浅雾蓝", rgb: RGBColor(200, 226, 255), symbol: "C23", brand: "MARD"),
    BeadColor(id: "C24", name: "晴蓝", rgb: RGBColor(124, 196, 255), symbol: "C24", brand: "MARD"),
    BeadColor(id: "C25", name: "浅青", rgb: RGBColor(169, 229, 229), symbol: "C25", brand: "MARD"),
    BeadColor(id: "C26", name: "蔚蓝", rgb: RGBColor(60, 174, 216), symbol: "C26", brand: "MARD"),
    BeadColor(id: "C27", name: "淡紫蓝", rgb: RGBColor(211, 223, 250), symbol: "C27", brand: "MARD"),
    BeadColor(id: "C28", name: "灰蓝调", rgb: RGBColor(187, 207, 237), symbol: "C28", brand: "MARD"),
    BeadColor(id: "C29", name: "暗蓝紫", rgb: RGBColor(52, 72, 142), symbol: "C29", brand: "MARD"),
    BeadColor(id: "D1", name: "浅紫", rgb: RGBColor(174, 180, 242), symbol: "D1", brand: "MARD"),
    BeadColor(id: "D2", name: "丁香紫", rgb: RGBColor(133, 142, 221), symbol: "D2", brand: "MARD"),
    BeadColor(id: "D3", name: "蓝紫", rgb: RGBColor(47, 84, 175), symbol: "D3", brand: "MARD"),
    BeadColor(id: "D4", name: "深紫蓝", rgb: RGBColor(24, 42, 132), symbol: "D4", brand: "MARD"),
    BeadColor(id: "D5", name: "紫罗兰", rgb: RGBColor(184, 67, 197), symbol: "D5", brand: "MARD"),
    BeadColor(id: "D6", name: "中紫", rgb: RGBColor(172, 123, 222), symbol: "D6", brand: "MARD"),
    BeadColor(id: "D7", name: "暗紫", rgb: RGBColor(136, 84, 179), symbol: "D7", brand: "MARD"),
    BeadColor(id: "D8", name: "淡紫", rgb: RGBColor(226, 211, 255), symbol: "D8", brand: "MARD"),
    BeadColor(id: "D9", name: "粉紫", rgb: RGBColor(213, 185, 248), symbol: "D9", brand: "MARD"),
    BeadColor(id: "D10", name: "暗深紫", rgb: RGBColor(54, 24, 81), symbol: "D10", brand: "MARD"),
    BeadColor(id: "D11", name: "灰紫", rgb: RGBColor(185, 186, 225), symbol: "D11", brand: "MARD"),
    BeadColor(id: "D12", name: "浅粉紫", rgb: RGBColor(222, 154, 212), symbol: "D12", brand: "MARD"),
    BeadColor(id: "D13", name: "品红", rgb: RGBColor(185, 0, 149), symbol: "D13", brand: "MARD"),
    BeadColor(id: "D14", name: "紫红", rgb: RGBColor(139, 39, 155), symbol: "D14", brand: "MARD"),
    BeadColor(id: "D15", name: "靛紫", rgb: RGBColor(47, 31, 144), symbol: "D15", brand: "MARD"),
    BeadColor(id: "D16", name: "淡灰紫", rgb: RGBColor(227, 225, 238), symbol: "D16", brand: "MARD"),
    BeadColor(id: "D17", name: "蓝灰紫", rgb: RGBColor(196, 212, 246), symbol: "D17", brand: "MARD"),
    BeadColor(id: "D18", name: "亮紫", rgb: RGBColor(164, 94, 199), symbol: "D18", brand: "MARD"),
    BeadColor(id: "D19", name: "藕紫", rgb: RGBColor(216, 195, 215), symbol: "D19", brand: "MARD"),
    BeadColor(id: "D20", name: "深紫红", rgb: RGBColor(156, 50, 178), symbol: "D20", brand: "MARD"),
    BeadColor(id: "D21", name: "洋红", rgb: RGBColor(154, 0, 155), symbol: "D21", brand: "MARD"),
    BeadColor(id: "D22", name: "藏蓝紫", rgb: RGBColor(51, 58, 149), symbol: "D22", brand: "MARD"),
    BeadColor(id: "D23", name: "极浅紫", rgb: RGBColor(235, 218, 252), symbol: "D23", brand: "MARD"),
    BeadColor(id: "D24", name: "蓝紫灰", rgb: RGBColor(119, 134, 229), symbol: "D24", brand: "MARD"),
    BeadColor(id: "D25", name: "暗蓝紫", rgb: RGBColor(73, 79, 199), symbol: "D25", brand: "MARD"),
    BeadColor(id: "D26", name: "薰衣草", rgb: RGBColor(223, 194, 248), symbol: "D26", brand: "MARD"),
    BeadColor(id: "E1", name: "浅珊瑚", rgb: RGBColor(253, 211, 204), symbol: "E1", brand: "MARD"),
    BeadColor(id: "E2", name: "粉色", rgb: RGBColor(254, 192, 223), symbol: "E2", brand: "MARD"),
    BeadColor(id: "E3", name: "亮粉", rgb: RGBColor(255, 183, 231), symbol: "E3", brand: "MARD"),
    BeadColor(id: "E4", name: "玫粉", rgb: RGBColor(232, 100, 158), symbol: "E4", brand: "MARD"),
    BeadColor(id: "E5", name: "玫红", rgb: RGBColor(245, 81, 162), symbol: "E5", brand: "MARD"),
    BeadColor(id: "E6", name: "桃红", rgb: RGBColor(241, 61, 116), symbol: "E6", brand: "MARD"),
    BeadColor(id: "E7", name: "暗玫红", rgb: RGBColor(198, 52, 120), symbol: "E7", brand: "MARD"),
    BeadColor(id: "E8", name: "浅粉白", rgb: RGBColor(255, 219, 233), symbol: "E8", brand: "MARD"),
    BeadColor(id: "E9", name: "亮玫红", rgb: RGBColor(233, 112, 204), symbol: "E9", brand: "MARD"),
    BeadColor(id: "E10", name: "紫粉", rgb: RGBColor(211, 55, 147), symbol: "E10", brand: "MARD"),
    BeadColor(id: "E11", name: "肉粉", rgb: RGBColor(252, 221, 210), symbol: "E11", brand: "MARD"),
    BeadColor(id: "E12", name: "暖粉", rgb: RGBColor(247, 143, 195), symbol: "E12", brand: "MARD"),
    BeadColor(id: "E13", name: "深玫红", rgb: RGBColor(181, 0, 109), symbol: "E13", brand: "MARD"),
    BeadColor(id: "E14", name: "肤色", rgb: RGBColor(255, 209, 186), symbol: "E14", brand: "MARD"),
    BeadColor(id: "E15", name: "暖灰粉", rgb: RGBColor(248, 199, 201), symbol: "E15", brand: "MARD"),
    BeadColor(id: "E16", name: "暖白", rgb: RGBColor(255, 243, 235), symbol: "E16", brand: "MARD"),
    BeadColor(id: "E17", name: "浅粉", rgb: RGBColor(255, 226, 234), symbol: "E17", brand: "MARD"),
    BeadColor(id: "E18", name: "淡粉", rgb: RGBColor(255, 199, 219), symbol: "E18", brand: "MARD"),
    BeadColor(id: "E19", name: "樱花粉", rgb: RGBColor(254, 186, 213), symbol: "E19", brand: "MARD"),
    BeadColor(id: "E20", name: "灰粉", rgb: RGBColor(216, 199, 209), symbol: "E20", brand: "MARD"),
    BeadColor(id: "E21", name: "褐粉", rgb: RGBColor(189, 157, 161), symbol: "E21", brand: "MARD"),
    BeadColor(id: "E22", name: "暗粉", rgb: RGBColor(183, 133, 161), symbol: "E22", brand: "MARD"),
    BeadColor(id: "E23", name: "深灰粉", rgb: RGBColor(147, 122, 141), symbol: "E23", brand: "MARD"),
    BeadColor(id: "E24", name: "浅藕粉", rgb: RGBColor(225, 188, 232), symbol: "E24", brand: "MARD"),
    BeadColor(id: "F1", name: "珊瑚红", rgb: RGBColor(253, 149, 123), symbol: "F1", brand: "MARD"),
    BeadColor(id: "F2", name: "红色", rgb: RGBColor(252, 61, 70), symbol: "F2", brand: "MARD"),
    BeadColor(id: "F3", name: "亮红", rgb: RGBColor(247, 73, 65), symbol: "F3", brand: "MARD"),
    BeadColor(id: "F4", name: "正红", rgb: RGBColor(252, 40, 60), symbol: "F4", brand: "MARD"),
    BeadColor(id: "F5", name: "深红", rgb: RGBColor(231, 0, 47), symbol: "F5", brand: "MARD"),
    BeadColor(id: "F6", name: "暗红", rgb: RGBColor(148, 54, 48), symbol: "F6", brand: "MARD"),
    BeadColor(id: "F7", name: "酒红", rgb: RGBColor(151, 25, 55), symbol: "F7", brand: "MARD"),
    BeadColor(id: "F8", name: "暗深红", rgb: RGBColor(188, 0, 40), symbol: "F8", brand: "MARD"),
    BeadColor(id: "F9", name: "玫粉红", rgb: RGBColor(226, 103, 122), symbol: "F9", brand: "MARD"),
    BeadColor(id: "F10", name: "深棕红", rgb: RGBColor(138, 69, 38), symbol: "F10", brand: "MARD"),
    BeadColor(id: "F11", name: "近黑红", rgb: RGBColor(90, 33, 33), symbol: "F11", brand: "MARD"),
    BeadColor(id: "F12", name: "水红", rgb: RGBColor(253, 78, 106), symbol: "F12", brand: "MARD"),
    BeadColor(id: "F13", name: "橘红", rgb: RGBColor(243, 87, 68), symbol: "F13", brand: "MARD"),
    BeadColor(id: "F14", name: "浅红", rgb: RGBColor(255, 169, 173), symbol: "F14", brand: "MARD"),
    BeadColor(id: "F15", name: "大红", rgb: RGBColor(211, 0, 34), symbol: "F15", brand: "MARD"),
    BeadColor(id: "F16", name: "浅肉橘", rgb: RGBColor(254, 194, 166), symbol: "F16", brand: "MARD"),
    BeadColor(id: "F17", name: "暖橘红", rgb: RGBColor(230, 156, 121), symbol: "F17", brand: "MARD"),
    BeadColor(id: "F18", name: "棕红", rgb: RGBColor(211, 124, 70), symbol: "F18", brand: "MARD"),
    BeadColor(id: "F19", name: "暗红褐", rgb: RGBColor(193, 68, 74), symbol: "F19", brand: "MARD"),
    BeadColor(id: "F20", name: "灰红", rgb: RGBColor(205, 147, 145), symbol: "F20", brand: "MARD"),
    BeadColor(id: "F21", name: "粉红", rgb: RGBColor(247, 180, 198), symbol: "F21", brand: "MARD"),
    BeadColor(id: "F22", name: "浅玫红", rgb: RGBColor(253, 192, 208), symbol: "F22", brand: "MARD"),
    BeadColor(id: "F23", name: "暖珊瑚", rgb: RGBColor(246, 126, 102), symbol: "F23", brand: "MARD"),
    BeadColor(id: "F24", name: "玫瑰灰", rgb: RGBColor(230, 152, 170), symbol: "F24", brand: "MARD"),
    BeadColor(id: "F25", name: "砖红", rgb: RGBColor(229, 75, 79), symbol: "F25", brand: "MARD"),
    BeadColor(id: "G1", name: "浅驼", rgb: RGBColor(255, 226, 206), symbol: "G1", brand: "MARD"),
    BeadColor(id: "G2", name: "浅杏", rgb: RGBColor(255, 196, 170), symbol: "G2", brand: "MARD"),
    BeadColor(id: "G3", name: "驼色", rgb: RGBColor(244, 195, 165), symbol: "G3", brand: "MARD"),
    BeadColor(id: "G4", name: "中驼", rgb: RGBColor(225, 179, 131), symbol: "G4", brand: "MARD"),
    BeadColor(id: "G5", name: "焦糖", rgb: RGBColor(237, 176, 69), symbol: "G5", brand: "MARD"),
    BeadColor(id: "G6", name: "深焦糖", rgb: RGBColor(233, 156, 23), symbol: "G6", brand: "MARD"),
    BeadColor(id: "G7", name: "中棕", rgb: RGBColor(157, 91, 62), symbol: "G7", brand: "MARD"),
    BeadColor(id: "G8", name: "深棕", rgb: RGBColor(117, 56, 50), symbol: "G8", brand: "MARD"),
    BeadColor(id: "G9", name: "暖棕", rgb: RGBColor(230, 180, 131), symbol: "G9", brand: "MARD"),
    BeadColor(id: "G10", name: "橘棕", rgb: RGBColor(217, 140, 57), symbol: "G10", brand: "MARD"),
    BeadColor(id: "G11", name: "浅棕", rgb: RGBColor(224, 197, 147), symbol: "G11", brand: "MARD"),
    BeadColor(id: "G12", name: "奶棕", rgb: RGBColor(255, 200, 144), symbol: "G12", brand: "MARD"),
    BeadColor(id: "G13", name: "红棕", rgb: RGBColor(183, 113, 74), symbol: "G13", brand: "MARD"),
    BeadColor(id: "G14", name: "灰棕", rgb: RGBColor(141, 97, 76), symbol: "G14", brand: "MARD"),
    BeadColor(id: "G15", name: "米白", rgb: RGBColor(252, 249, 224), symbol: "G15", brand: "MARD"),
    BeadColor(id: "G16", name: "暖米", rgb: RGBColor(242, 217, 186), symbol: "G16", brand: "MARD"),
    BeadColor(id: "G17", name: "暗棕", rgb: RGBColor(120, 82, 75), symbol: "G17", brand: "MARD"),
    BeadColor(id: "G18", name: "浅暖棕", rgb: RGBColor(255, 228, 204), symbol: "G18", brand: "MARD"),
    BeadColor(id: "G19", name: "锈橘", rgb: RGBColor(224, 121, 53), symbol: "G19", brand: "MARD"),
    BeadColor(id: "G20", name: "深红棕", rgb: RGBColor(169, 64, 35), symbol: "G20", brand: "MARD"),
    BeadColor(id: "G21", name: "黄棕", rgb: RGBColor(184, 133, 88), symbol: "G21", brand: "MARD"),
    BeadColor(id: "H1", name: "暖白", rgb: RGBColor(253, 251, 255), symbol: "H1", brand: "MARD"),
    BeadColor(id: "H2", name: "纯白", rgb: RGBColor(254, 255, 255), symbol: "H2", brand: "MARD"),
    BeadColor(id: "H3", name: "中灰", rgb: RGBColor(182, 177, 186), symbol: "H3", brand: "MARD"),
    BeadColor(id: "H4", name: "深灰", rgb: RGBColor(137, 133, 140), symbol: "H4", brand: "MARD"),
    BeadColor(id: "H5", name: "近黑灰", rgb: RGBColor(72, 70, 78), symbol: "H5", brand: "MARD"),
    BeadColor(id: "H6", name: "深炭灰", rgb: RGBColor(47, 43, 47), symbol: "H6", brand: "MARD"),
    BeadColor(id: "H7", name: "黑色", rgb: RGBColor(0, 0, 0), symbol: "H7", brand: "MARD"),
    BeadColor(id: "H8", name: "暖灰粉", rgb: RGBColor(231, 214, 219), symbol: "H8", brand: "MARD"),
    BeadColor(id: "H9", name: "浅灰", rgb: RGBColor(237, 237, 237), symbol: "H9", brand: "MARD"),
    BeadColor(id: "H10", name: "灰白", rgb: RGBColor(238, 233, 234), symbol: "H10", brand: "MARD"),
    BeadColor(id: "H11", name: "冷灰", rgb: RGBColor(206, 205, 213), symbol: "H11", brand: "MARD"),
    BeadColor(id: "H12", name: "米白暖", rgb: RGBColor(255, 245, 237), symbol: "H12", brand: "MARD"),
    BeadColor(id: "H13", name: "暖浅灰", rgb: RGBColor(245, 236, 210), symbol: "H13", brand: "MARD"),
    BeadColor(id: "H14", name: "冷浅灰", rgb: RGBColor(207, 215, 211), symbol: "H14", brand: "MARD"),
    BeadColor(id: "H15", name: "中冷灰", rgb: RGBColor(152, 166, 168), symbol: "H15", brand: "MARD"),
    BeadColor(id: "H16", name: "深棕黑", rgb: RGBColor(29, 20, 20), symbol: "H16", brand: "MARD"),
    BeadColor(id: "H17", name: "暖浅灰2", rgb: RGBColor(241, 237, 237), symbol: "H17", brand: "MARD"),
    BeadColor(id: "H18", name: "奶白", rgb: RGBColor(255, 253, 240), symbol: "H18", brand: "MARD"),
    BeadColor(id: "H19", name: "米灰", rgb: RGBColor(246, 239, 226), symbol: "H19", brand: "MARD"),
    BeadColor(id: "H20", name: "蓝灰", rgb: RGBColor(148, 159, 163), symbol: "H20", brand: "MARD"),
    BeadColor(id: "H21", name: "黄白", rgb: RGBColor(255, 251, 225), symbol: "H21", brand: "MARD"),
    BeadColor(id: "H22", name: "银灰", rgb: RGBColor(202, 202, 212), symbol: "H22", brand: "MARD"),
    BeadColor(id: "H23", name: "绿灰", rgb: RGBColor(154, 157, 148), symbol: "H23", brand: "MARD"),
    BeadColor(id: "M1", name: "灰绿", rgb: RGBColor(188, 198, 184), symbol: "M1", brand: "MARD"),
    BeadColor(id: "M2", name: "暗灰绿", rgb: RGBColor(138, 163, 134), symbol: "M2", brand: "MARD"),
    BeadColor(id: "M3", name: "青灰", rgb: RGBColor(105, 125, 128), symbol: "M3", brand: "MARD"),
    BeadColor(id: "M4", name: "暖米灰", rgb: RGBColor(227, 210, 188), symbol: "M4", brand: "MARD"),
    BeadColor(id: "M5", name: "灰米", rgb: RGBColor(208, 204, 170), symbol: "M5", brand: "MARD"),
    BeadColor(id: "M6", name: "暗米灰", rgb: RGBColor(176, 167, 130), symbol: "M6", brand: "MARD"),
    BeadColor(id: "M7", name: "褐灰", rgb: RGBColor(180, 164, 151), symbol: "M7", brand: "MARD"),
    BeadColor(id: "M8", name: "灰红", rgb: RGBColor(179, 130, 129), symbol: "M8", brand: "MARD"),
    BeadColor(id: "M9", name: "暖棕灰", rgb: RGBColor(165, 135, 103), symbol: "M9", brand: "MARD"),
    BeadColor(id: "M10", name: "灰紫粉", rgb: RGBColor(197, 178, 188), symbol: "M10", brand: "MARD"),
    BeadColor(id: "M11", name: "暗紫灰", rgb: RGBColor(159, 117, 148), symbol: "M11", brand: "MARD"),
    BeadColor(id: "M12", name: "暗红灰", rgb: RGBColor(100, 71, 73), symbol: "M12", brand: "MARD"),
    BeadColor(id: "M13", name: "暖橘灰", rgb: RGBColor(209, 144, 102), symbol: "M13", brand: "MARD"),
    BeadColor(id: "M14", name: "灰红棕", rgb: RGBColor(199, 115, 98), symbol: "M14", brand: "MARD"),
    BeadColor(id: "M15", name: "暗灰", rgb: RGBColor(117, 125, 120), symbol: "M15", brand: "MARD"),
    BeadColor(id: "P1", name: "柔白", rgb: RGBColor(252, 247, 248), symbol: "P1", brand: "MARD"),
    BeadColor(id: "P2", name: "柔灰", rgb: RGBColor(176, 169, 172), symbol: "P2", brand: "MARD"),
    BeadColor(id: "P3", name: "柔绿", rgb: RGBColor(175, 220, 171), symbol: "P3", brand: "MARD"),
    BeadColor(id: "P4", name: "柔粉", rgb: RGBColor(254, 164, 159), symbol: "P4", brand: "MARD"),
    BeadColor(id: "P5", name: "柔橘", rgb: RGBColor(238, 140, 62), symbol: "P5", brand: "MARD"),
    BeadColor(id: "P6", name: "柔青绿", rgb: RGBColor(95, 208, 167), symbol: "P6", brand: "MARD"),
    BeadColor(id: "P7", name: "柔珊瑚", rgb: RGBColor(235, 146, 112), symbol: "P7", brand: "MARD"),
    BeadColor(id: "P8", name: "柔黄", rgb: RGBColor(240, 217, 88), symbol: "P8", brand: "MARD"),
    BeadColor(id: "P9", name: "中灰2", rgb: RGBColor(217, 217, 217), symbol: "P9", brand: "MARD"),
    BeadColor(id: "P10", name: "柔紫", rgb: RGBColor(217, 199, 234), symbol: "P10", brand: "MARD"),
    BeadColor(id: "P11", name: "柔米", rgb: RGBColor(243, 236, 201), symbol: "P11", brand: "MARD"),
    BeadColor(id: "P12", name: "柔蓝", rgb: RGBColor(230, 238, 242), symbol: "P12", brand: "MARD"),
    BeadColor(id: "P13", name: "柔天蓝", rgb: RGBColor(170, 203, 239), symbol: "P13", brand: "MARD"),
    BeadColor(id: "P14", name: "深青绿", rgb: RGBColor(51, 118, 128), symbol: "P14", brand: "MARD"),
    BeadColor(id: "P15", name: "灰绿2", rgb: RGBColor(102, 133, 117), symbol: "P15", brand: "MARD"),
    BeadColor(id: "P16", name: "亮橘", rgb: RGBColor(254, 191, 69), symbol: "P16", brand: "MARD"),
    BeadColor(id: "P17", name: "深橘", rgb: RGBColor(254, 163, 36), symbol: "P17", brand: "MARD"),
    BeadColor(id: "P18", name: "肉色", rgb: RGBColor(254, 184, 159), symbol: "P18", brand: "MARD"),
    BeadColor(id: "P19", name: "象牙白", rgb: RGBColor(255, 254, 236), symbol: "P19", brand: "MARD"),
    BeadColor(id: "P20", name: "暖粉2", rgb: RGBColor(254, 190, 207), symbol: "P20", brand: "MARD"),
    BeadColor(id: "P21", name: "玫瑰", rgb: RGBColor(236, 190, 191), symbol: "P21", brand: "MARD"),
    BeadColor(id: "P22", name: "暖珊瑚2", rgb: RGBColor(228, 168, 159), symbol: "P22", brand: "MARD"),
    BeadColor(id: "P23", name: "暗玫红2", rgb: RGBColor(165, 98, 104), symbol: "P23", brand: "MARD"),
    BeadColor(id: "Q1", name: "亮粉紫", rgb: RGBColor(242, 165, 232), symbol: "Q1", brand: "MARD"),
    BeadColor(id: "Q2", name: "黄绿2", rgb: RGBColor(233, 236, 145), symbol: "Q2", brand: "MARD"),
    BeadColor(id: "Q3", name: "纯黄", rgb: RGBColor(255, 255, 0), symbol: "Q3", brand: "MARD"),
    BeadColor(id: "Q4", name: "浅粉白2", rgb: RGBColor(255, 235, 250), symbol: "Q4", brand: "MARD"),
    BeadColor(id: "Q5", name: "浅青", rgb: RGBColor(118, 206, 222), symbol: "Q5", brand: "MARD"),
    BeadColor(id: "R1", name: "正红2", rgb: RGBColor(213, 13, 33), symbol: "R1", brand: "MARD"),
    BeadColor(id: "R2", name: "品红2", rgb: RGBColor(249, 47, 131), symbol: "R2", brand: "MARD"),
    BeadColor(id: "R3", name: "明橘", rgb: RGBColor(253, 131, 36), symbol: "R3", brand: "MARD"),
    BeadColor(id: "R4", name: "明黄2", rgb: RGBColor(248, 236, 49), symbol: "R4", brand: "MARD"),
    BeadColor(id: "R5", name: "翠绿2", rgb: RGBColor(53, 199, 91), symbol: "R5", brand: "MARD"),
    BeadColor(id: "R6", name: "青色", rgb: RGBColor(35, 136, 145), symbol: "R6", brand: "MARD"),
    BeadColor(id: "R7", name: "深青蓝", rgb: RGBColor(25, 119, 157), symbol: "R7", brand: "MARD"),
    BeadColor(id: "R8", name: "亮蓝2", rgb: RGBColor(26, 96, 195), symbol: "R8", brand: "MARD"),
    BeadColor(id: "R9", name: "紫色2", rgb: RGBColor(154, 86, 180), symbol: "R9", brand: "MARD"),
    BeadColor(id: "R10", name: "明黄3", rgb: RGBColor(255, 219, 76), symbol: "R10", brand: "MARD"),
    BeadColor(id: "R11", name: "浅粉白3", rgb: RGBColor(255, 235, 250), symbol: "R11", brand: "MARD"),
    BeadColor(id: "R12", name: "暖灰2", rgb: RGBColor(216, 213, 206), symbol: "R12", brand: "MARD"),
    BeadColor(id: "R13", name: "暗灰2", rgb: RGBColor(85, 81, 76), symbol: "R13", brand: "MARD"),
    BeadColor(id: "R14", name: "浅水绿", rgb: RGBColor(159, 228, 223), symbol: "R14", brand: "MARD"),
    BeadColor(id: "R15", name: "浅蓝2", rgb: RGBColor(119, 206, 233), symbol: "R15", brand: "MARD"),
    BeadColor(id: "R16", name: "碧绿2", rgb: RGBColor(62, 207, 202), symbol: "R16", brand: "MARD"),
    BeadColor(id: "R17", name: "暗青绿", rgb: RGBColor(74, 134, 122), symbol: "R17", brand: "MARD"),
    BeadColor(id: "R18", name: "浅绿2", rgb: RGBColor(127, 205, 157), symbol: "R18", brand: "MARD"),
    BeadColor(id: "R19", name: "苔绿2", rgb: RGBColor(205, 229, 93), symbol: "R19", brand: "MARD"),
    BeadColor(id: "R20", name: "暖米2", rgb: RGBColor(232, 199, 180), symbol: "R20", brand: "MARD"),
    BeadColor(id: "R21", name: "中棕2", rgb: RGBColor(173, 111, 60), symbol: "R21", brand: "MARD"),
    BeadColor(id: "R22", name: "深棕2", rgb: RGBColor(108, 55, 47), symbol: "R22", brand: "MARD"),
    BeadColor(id: "R23", name: "暖杏橘2", rgb: RGBColor(254, 184, 114), symbol: "R23", brand: "MARD"),
    BeadColor(id: "R24", name: "浅粉红", rgb: RGBColor(243, 193, 192), symbol: "R24", brand: "MARD"),
    BeadColor(id: "R25", name: "暗红2", rgb: RGBColor(201, 103, 94), symbol: "R25", brand: "MARD"),
    BeadColor(id: "R26", name: "灰紫2", rgb: RGBColor(210, 147, 190), symbol: "R26", brand: "MARD"),
    BeadColor(id: "R27", name: "粉红2", rgb: RGBColor(234, 140, 177), symbol: "R27", brand: "MARD"),
    BeadColor(id: "R28", name: "蓝紫2", rgb: RGBColor(156, 135, 214), symbol: "R28", brand: "MARD"),
    BeadColor(id: "T1", name: "白色", rgb: RGBColor(255, 255, 255), symbol: "T1", brand: "MARD"),
    BeadColor(id: "Y1", name: "柔粉红", rgb: RGBColor(253, 111, 180), symbol: "Y1", brand: "MARD"),
    BeadColor(id: "Y2", name: "柔杏", rgb: RGBColor(254, 180, 129), symbol: "Y2", brand: "MARD"),
    BeadColor(id: "Y3", name: "柔绿2", rgb: RGBColor(215, 250, 160), symbol: "Y3", brand: "MARD"),
    BeadColor(id: "Y4", name: "柔蓝2", rgb: RGBColor(139, 219, 250), symbol: "Y4", brand: "MARD"),
    BeadColor(id: "Y5", name: "柔紫2", rgb: RGBColor(233, 135, 234), symbol: "Y5", brand: "MARD"),
    BeadColor(id: "ZG1", name: "暖灰粉2", rgb: RGBColor(218, 171, 179), symbol: "ZG1", brand: "MARD"),
    BeadColor(id: "ZG2", name: "暖灰棕", rgb: RGBColor(214, 170, 135), symbol: "ZG2", brand: "MARD"),
    BeadColor(id: "ZG3", name: "灰绿3", rgb: RGBColor(193, 189, 141), symbol: "ZG3", brand: "MARD"),
    BeadColor(id: "ZG4", name: "灰紫3", rgb: RGBColor(150, 134, 159), symbol: "ZG4", brand: "MARD"),
    BeadColor(id: "ZG5", name: "蓝灰2", rgb: RGBColor(132, 144, 166), symbol: "ZG5", brand: "MARD"),
    BeadColor(id: "ZG6", name: "浅蓝灰", rgb: RGBColor(148, 191, 226), symbol: "ZG6", brand: "MARD"),
    BeadColor(id: "ZG7", name: "灰粉2", rgb: RGBColor(226, 169, 210), symbol: "ZG7", brand: "MARD"),
    BeadColor(id: "ZG8", name: "灰蓝紫", rgb: RGBColor(171, 145, 192), symbol: "ZG8", brand: "MARD"),
]

// MARK: - 套装色号集合

/// MARD 套装色号集合。对应源端 `MARD_SETS`。
public let mardSets: [String: [String]] = [
    "MARD_72": ["H1", "H2", "H9", "H11", "H4", "H5", "H6", "H7", "H16", "A1", "A2", "A3", "A4", "A6", "A7", "A9", "A15", "A26", "B2", "B4", "B5", "B8", "B9", "B10", "B20", "C4", "C5", "C7", "C8", "C13", "C16", "C20", "D1", "D3", "D14", "D21", "E2", "E4", "E6", "E17", "E18", "F2", "F3", "F5", "F15", "G1", "G3", "G5", "G7", "G8", "G10", "T1"],
    "MARD_96": ["H1", "H2", "H9", "H10", "H11", "H3", "H4", "H5", "H6", "H7", "H16", "H17", "H18", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A15", "A16", "A17", "A26", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B14", "B20", "B28", "C4", "C5", "C6", "C7", "C8", "C9", "C13", "C16", "C20", "C26", "D1", "D2", "D3", "D5", "D14", "D18", "D21", "E2", "E3", "E4", "E5", "E6", "E12", "E17", "E18", "F2", "F3", "F5", "F11", "F15", "G1", "G2", "G3", "G5", "G6", "G7", "G8", "G10", "G11", "G16", "T1"],
    "MARD_120": ["H1", "H2", "H9", "H10", "H11", "H3", "H4", "H5", "H6", "H7", "H12", "H13", "H14", "H15", "H16", "H17", "H18", "H19", "H20", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A12", "A13", "A15", "A16", "A17", "A18", "A20", "A21", "A25", "A26", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B13", "B14", "B16", "B19", "B20", "B28", "B30", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C13", "C15", "C16", "C17", "C20", "C21", "C26", "D1", "D2", "D3", "D5", "D6", "D7", "D9", "D14", "D18", "D21", "D23", "E2", "E3", "E4", "E5", "E6", "E8", "E11", "E12", "E14", "E17", "E18", "E19", "F2", "F3", "F5", "F6", "F9", "F11", "F14", "F15", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11", "G12", "G13", "G16", "G19", "M1", "M2", "M3", "M9", "M13", "T1"],
    "MARD_144": ["H1", "H2", "H9", "H10", "H11", "H3", "H4", "H5", "H6", "H7", "H8", "H12", "H13", "H14", "H15", "H16", "H17", "H18", "H19", "H20", "H21", "H22", "H23", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A12", "A13", "A14", "A15", "A16", "A17", "A18", "A19", "A20", "A21", "A22", "A23", "A24", "A25", "A26", "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B11", "B13", "B14", "B16", "B17", "B19", "B20", "B25", "B27", "B28", "B29", "B30", "B31", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C13", "C14", "C15", "C16", "C17", "C19", "C20", "C21", "C23", "C24", "C25", "C26", "C27", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D11", "D12", "D14", "D16", "D17", "D18", "D19", "D21", "D23", "D24", "D26", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E11", "E12", "E14", "E15", "E17", "E18", "E19", "E20", "E22", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F9", "F10", "F11", "F13", "F14", "F15", "F16", "F17", "F23", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11", "G12", "G13", "G14", "G15", "G16", "G17", "G18", "G19", "G20", "G21", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M13", "P1", "P9", "P16", "P17", "P19", "T1"],
    "MARD_221": ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A12", "A13", "A14", "A15", "A16", "A17", "A18", "A19", "A20", "A21", "A22", "A23", "A24", "A25", "A26", "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B11", "B12", "B13", "B14", "B15", "B16", "B17", "B18", "B19", "B20", "B21", "B22", "B23", "B24", "B25", "B26", "B27", "B28", "B29", "B30", "B31", "B32", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C12", "C13", "C14", "C15", "C16", "C17", "C18", "C19", "C20", "C21", "C22", "C23", "C24", "C25", "C26", "C27", "C28", "C29", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10", "D11", "D12", "D14", "D15", "D16", "D17", "D18", "D19", "D20", "D21", "D22", "D23", "D24", "D25", "D26", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10", "E11", "E12", "E13", "E14", "E15", "E17", "E18", "E19", "E20", "E21", "E22", "E23", "E24", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24", "F25", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11", "G12", "G13", "G14", "G15", "G16", "G17", "G18", "G19", "G20", "G21", "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "H10", "H11", "H12", "H13", "H14", "H15", "H16", "H17", "H18", "H19", "H20", "H21", "H22", "H23", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M11", "M12", "M13", "M14", "M15", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11", "P12", "P13", "P14", "P15", "P16", "P17", "P18", "P19", "P20", "P21", "P22", "P23", "Q1", "Q2", "Q3", "Q4", "Q5", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10", "R14", "R15", "R16", "R18", "R19", "T1", "Y1", "Y2", "Y3", "Y4", "Y5", "ZG1", "ZG2", "ZG3", "ZG4", "ZG5", "ZG6", "ZG7", "ZG8"],
    "MARD_291": [],  // 空数组 = 全部 291 色
]

// MARK: - 宠物专用子集

/// 宠物专用 96 色子集。对应源端 `MARD_PET_96_CODES`。
public let mardPet96Codes: [String] = ["T1", "H1", "H2", "H18", "H12", "H19", "H9", "H10", "H17", "H3", "H22", "H4", "H20", "H15", "H13", "H14", "H23", "H8", "H21", "A23", "H5", "H6", "H16", "H7", "A1", "A2", "A3", "G15", "A11", "H11", "A6", "A7", "A9", "A10", "A4", "A8", "A12", "A17", "A26", "A13", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G13", "G14", "G11", "G17", "G19", "G20", "G21", "F10", "M1", "M2", "M3", "M7", "M9", "M6", "E1", "E14", "E11", "E17", "E18", "E8", "E21", "E22", "E23", "F24", "F2", "F3", "F7", "F11", "C8", "A5", "C13", "C20", "C7", "B20", "B9", "P1", "P19", "P18", "P20", "P12", "M10", "M5", "ZG5", "G12", "G16", "G18"]

/// 宠物专用 160 色子集额外色号（concat 到 96 色上）。对应源端 `MARD_PET_160_CODES`。
public let mardPet160ExtraCodes: [String] = ["P1", "P19", "H11", "M10", "M5", "ZG5", "A13", "A18", "A20", "A21", "A25", "A24", "G12", "G16", "G18", "M13", "M8", "M11", "F18", "F17", "ZG1", "ZG2", "ZG3", "ZG4", "E2", "E4", "E19", "E15", "F5", "F15", "F25", "C5", "C21", "C26", "B10", "B7", "D1", "D8", "P2", "P3", "P9", "P13", "P16", "P17", "R20", "R23", "Y2", "Y4", "R24", "R25"]
public let mardPet160Codes: [String] = mardPet96Codes + mardPet160ExtraCodes

// MARK: - 标签色号映射

private let warmWhiteCodes: Set<String> = ["H1", "H2", "H18", "H12", "H19", "A1", "A2"]
private let neutralWhiteCodes: Set<String> = ["T1", "H1", "H2"]
private let creamCodes: Set<String> = ["H13", "H14", "H23", "A1", "A2", "A11"]
private let warmGrayCodes: Set<String> = ["H9", "H10", "H17", "H3", "H22", "M1", "M2", "M3"]
private let coolGrayCodes: Set<String> = ["H4", "H20", "H15", "ZG5"]
private let blackCodes: Set<String> = ["H7"]
private let softBlackCodes: Set<String> = ["H5", "H6", "H16"]
private let orangeFurCodes: Set<String> = ["A6", "A7", "A9", "A10", "A12", "A17", "A26"]
private let brownFurCodes: Set<String> = ["G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11", "G13", "G14", "G17", "G19", "G20", "G21", "F10"]
private let pinkNoseCodes: Set<String> = ["E21", "E22", "E23", "F24"]
private let eyeColorCodes: Set<String> = ["F7", "F11", "C8", "A5"]
private let blueTintCodes: Set<String> = ["C13", "C20", "C7", "C5", "C21", "C26"]
private let avoidForFurCodes: Set<String> = ["C13", "C20", "C7", "C5", "C21", "C26", "B20", "B9", "B10", "B7", "D1", "D8"]

/// 获取色号的宠物标签。对应源端 `getMardPetColorTags`。
public func getMardPetColorTags(_ code: String) -> [BeadColorTag] {
    var tags: [BeadColorTag] = []
    if warmWhiteCodes.contains(code) { tags.append(.warmWhite) }
    if neutralWhiteCodes.contains(code) { tags.append(.neutralWhite) }
    if creamCodes.contains(code) { tags.append(.cream) }
    if warmGrayCodes.contains(code) { tags.append(.warmGray) }
    if coolGrayCodes.contains(code) { tags.append(.coolGray) }
    if blackCodes.contains(code) { tags.append(.black) }
    if softBlackCodes.contains(code) { tags.append(.softBlack) }
    if orangeFurCodes.contains(code) { tags.append(.orangeFur) }
    if brownFurCodes.contains(code) { tags.append(.brownFur) }
    if pinkNoseCodes.contains(code) { tags.append(.pinkNose) }
    if eyeColorCodes.contains(code) { tags.append(.eyeColor) }
    if blueTintCodes.contains(code) { tags.append(.blueTint) }
    if avoidForFurCodes.contains(code) { tags.append(.avoidForFur) }
    return tags
}

// MARK: - 套装标签

/// 套装显示名。对应源端 `MARD_SET_LABELS`。
public let mardSetLabels: [String: String] = [
    "MARD_72": "72 色（入门套装）",
    "MARD_96": "96 色（基础套装）",
    "MARD_120": "120 色（进阶套装）",
    "MARD_144": "144 色（丰富套装）",
    "MARD_221": "221 色（专业套装）",
    "MARD_291": "291 色（全部色号）",
    "MARD_PET_96": "宠物精选 96 色",
    "MARD_PET_160": "宠物精选 160 色",
]

// MARK: - 查询函数

/// 根据套装 ID 获取该套装的所有颜色。对应源端 `getMardColorsBySet`。
/// 未知 setId 回退到全部 291 色（源端 fallback 行为）。
public func getMardColorsBySet(_ setId: String) -> [BeadColor] {
    if setId == "MARD_291" {
        return mardAllColors.map { withPetTags($0) }
    }
    let codes = mardSets[setId]
    guard let codes, !codes.isEmpty else {
        return mardAllColors  // fallback: 未知 setId 返回全部
    }
    let codeSet = Set(codes)
    return mardAllColors.filter { codeSet.contains($0.id) }.map { withPetTags($0) }
}

/// 获取宠物专用子集颜色。对应源端 `getMardPetColors`。
/// 注意源端 fallback：非 'MARD_PET_160' 的任意值都回退到 96 色。
public func getMardPetColors(_ subsetId: String) -> [BeadColor] {
    let codes = subsetId == "MARD_PET_160" ? mardPet160Codes : mardPet96Codes
    let codeSet = Set(codes)
    return mardAllColors.filter { codeSet.contains($0.id) }.map { withPetTags($0) }
}

/// 获取色号显示文本：MARD A6 浅橘。对应源端 `getMardDisplayText`。
public func getMardDisplayText(_ color: BeadColor) -> String {
    color.brand == "MARD" ? "MARD \(color.id) \(color.name)" : color.name
}

/// 获取色号短文本：MARD A6。对应源端 `getMardShortCode`。
public func getMardShortCode(_ color: BeadColor) -> String {
    color.brand == "MARD" ? "MARD \(color.id)" : color.id
}

// MARK: - 标签辅助

/// 给颜色附加宠物标签（私有）。对应源端 `withPetTags`。
/// tags 字段当前 BeadColor 尚未持有；后续 BeadPalette 扩展时补 tags 属性。
/// 为保持行为一致，这里通过 getMardPetColorTags 计算但不存储（等价于源端赋值后回传）。
func withPetTags(_ color: BeadColor) -> BeadColor {
    _ = getMardPetColorTags(color.id)
    return color
}
