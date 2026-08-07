import Foundation

// 色板定义与查询。翻译自源端 shared/.../bead/BeadPalette.ets。
// 4 个通用/宠物静态色板（24/48/96/160）+ getBeadPalette/getAvailablePalettes。
// MARD 色卡见 BeadPaletteMard.swift（自动生成）。

// MARK: - 色板定义类型

/// 色卡定义。对应源端 `BeadPaletteDef`。
public struct BeadPaletteDef: Equatable, Sendable {
    public var id: String
    public var name: String
    public var colors: [BeadColor]

    public init(id: String, name: String, colors: [BeadColor]) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}

/// 可用色板信息（列表项）。对应源端 `PaletteInfo`。
public struct PaletteInfo: Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - 通用 24 色（兼容旧版）

public let paletteGeneric24 = BeadPaletteDef(id: "generic_24", name: "通用 24 色", colors: [
    BeadColor(id: "C01", name: "白色", rgb: RGBColor(255, 255, 255), symbol: "A", brand: "generic"),
    BeadColor(id: "C02", name: "浅灰", rgb: RGBColor(192, 192, 192), symbol: "B", brand: "generic"),
    BeadColor(id: "C03", name: "深灰", rgb: RGBColor(96, 96, 96), symbol: "C", brand: "generic"),
    BeadColor(id: "C04", name: "黑色", rgb: RGBColor(0, 0, 0), symbol: "D", brand: "generic"),
    BeadColor(id: "C05", name: "奶油白", rgb: RGBColor(255, 253, 240), symbol: "E", brand: "generic"),
    BeadColor(id: "C06", name: "米色", rgb: RGBColor(245, 235, 220), symbol: "F", brand: "generic"),
    BeadColor(id: "C07", name: "浅黄", rgb: RGBColor(255, 255, 150), symbol: "G", brand: "generic"),
    BeadColor(id: "C08", name: "浅橘", rgb: RGBColor(255, 200, 130), symbol: "H", brand: "generic"),
    BeadColor(id: "C09", name: "橘黄", rgb: RGBColor(255, 165, 50), symbol: "I", brand: "generic"),
    BeadColor(id: "C10", name: "浅棕", rgb: RGBColor(180, 140, 100), symbol: "J", brand: "generic"),
    BeadColor(id: "C11", name: "深棕", rgb: RGBColor(101, 67, 33), symbol: "K", brand: "generic"),
    BeadColor(id: "C12", name: "浅粉", rgb: RGBColor(255, 200, 210), symbol: "L", brand: "generic"),
    BeadColor(id: "C13", name: "粉色", rgb: RGBColor(255, 140, 170), symbol: "M", brand: "generic"),
    BeadColor(id: "C14", name: "红色", rgb: RGBColor(220, 50, 50), symbol: "N", brand: "generic"),
    BeadColor(id: "C15", name: "浅蓝", rgb: RGBColor(150, 200, 255), symbol: "O", brand: "generic"),
    BeadColor(id: "C16", name: "蓝色", rgb: RGBColor(50, 100, 200), symbol: "P", brand: "generic"),
    BeadColor(id: "C17", name: "浅绿", rgb: RGBColor(160, 220, 160), symbol: "Q", brand: "generic"),
    BeadColor(id: "C18", name: "绿色", rgb: RGBColor(50, 150, 50), symbol: "R", brand: "generic"),
    BeadColor(id: "C19", name: "浅紫", rgb: RGBColor(200, 180, 230), symbol: "S", brand: "generic"),
    BeadColor(id: "C20", name: "暖灰", rgb: RGBColor(170, 160, 150), symbol: "T", brand: "generic"),
    BeadColor(id: "C21", name: "褐灰", rgb: RGBColor(140, 120, 110), symbol: "U", brand: "generic"),
    BeadColor(id: "C22", name: "巧克力", rgb: RGBColor(75, 45, 25), symbol: "V", brand: "generic"),
    BeadColor(id: "C23", name: "桃色", rgb: RGBColor(255, 180, 140), symbol: "W", brand: "generic"),
    BeadColor(id: "C24", name: "驼色", rgb: RGBColor(210, 180, 140), symbol: "X", brand: "generic"),
])

// MARK: - 通用 48 色（兼容旧版）

public let paletteGeneric48 = BeadPaletteDef(id: "generic_48", name: "通用 48 色", colors: [
    BeadColor(id: "C01", name: "白色", rgb: RGBColor(255, 255, 255), symbol: "A", brand: "generic"),
    BeadColor(id: "C02", name: "奶白", rgb: RGBColor(255, 250, 240), symbol: "B", brand: "generic"),
    BeadColor(id: "C03", name: "浅灰", rgb: RGBColor(200, 200, 200), symbol: "C", brand: "generic"),
    BeadColor(id: "C04", name: "中灰", rgb: RGBColor(140, 140, 140), symbol: "D", brand: "generic"),
    BeadColor(id: "C05", name: "深灰", rgb: RGBColor(80, 80, 80), symbol: "E", brand: "generic"),
    BeadColor(id: "C06", name: "黑色", rgb: RGBColor(0, 0, 0), symbol: "F", brand: "generic"),
    BeadColor(id: "C07", name: "奶油白", rgb: RGBColor(255, 253, 235), symbol: "G", brand: "generic"),
    BeadColor(id: "C08", name: "米色", rgb: RGBColor(245, 235, 215), symbol: "H", brand: "generic"),
    BeadColor(id: "C09", name: "象牙白", rgb: RGBColor(255, 245, 225), symbol: "I", brand: "generic"),
    BeadColor(id: "C10", name: "浅黄", rgb: RGBColor(255, 255, 160), symbol: "J", brand: "generic"),
    BeadColor(id: "C11", name: "黄色", rgb: RGBColor(255, 230, 60), symbol: "K", brand: "generic"),
    BeadColor(id: "C12", name: "浅橘", rgb: RGBColor(255, 210, 150), symbol: "L", brand: "generic"),
    BeadColor(id: "C13", name: "橘黄", rgb: RGBColor(255, 180, 80), symbol: "M", brand: "generic"),
    BeadColor(id: "C14", name: "橘色", rgb: RGBColor(255, 140, 40), symbol: "N", brand: "generic"),
    BeadColor(id: "C15", name: "深橘", rgb: RGBColor(220, 110, 30), symbol: "O", brand: "generic"),
    BeadColor(id: "C16", name: "杏色", rgb: RGBColor(255, 195, 160), symbol: "P", brand: "generic"),
    BeadColor(id: "C17", name: "浅棕", rgb: RGBColor(195, 160, 120), symbol: "Q", brand: "generic"),
    BeadColor(id: "C18", name: "驼色", rgb: RGBColor(210, 180, 140), symbol: "R", brand: "generic"),
    BeadColor(id: "C19", name: "中棕", rgb: RGBColor(160, 120, 80), symbol: "S", brand: "generic"),
    BeadColor(id: "C20", name: "深棕", rgb: RGBColor(110, 75, 45), symbol: "T", brand: "generic"),
    BeadColor(id: "C21", name: "巧克力", rgb: RGBColor(80, 50, 30), symbol: "U", brand: "generic"),
    BeadColor(id: "C22", name: "咖啡", rgb: RGBColor(60, 35, 20), symbol: "V", brand: "generic"),
    BeadColor(id: "C23", name: "暖灰", rgb: RGBColor(185, 175, 165), symbol: "W", brand: "generic"),
    BeadColor(id: "C24", name: "褐灰", rgb: RGBColor(150, 135, 125), symbol: "X", brand: "generic"),
    BeadColor(id: "C25", name: "暖深灰", rgb: RGBColor(110, 100, 90), symbol: "Y", brand: "generic"),
    BeadColor(id: "C26", name: "冷灰", rgb: RGBColor(160, 165, 175), symbol: "Z", brand: "generic"),
    BeadColor(id: "C27", name: "浅粉", rgb: RGBColor(255, 210, 220), symbol: "a", brand: "generic"),
    BeadColor(id: "C28", name: "粉色", rgb: RGBColor(255, 150, 180), symbol: "b", brand: "generic"),
    BeadColor(id: "C29", name: "玫红", rgb: RGBColor(230, 80, 130), symbol: "c", brand: "generic"),
    BeadColor(id: "C30", name: "红色", rgb: RGBColor(220, 50, 50), symbol: "d", brand: "generic"),
    BeadColor(id: "C31", name: "深红", rgb: RGBColor(160, 30, 30), symbol: "e", brand: "generic"),
    BeadColor(id: "C32", name: "浅蓝", rgb: RGBColor(160, 210, 255), symbol: "f", brand: "generic"),
    BeadColor(id: "C33", name: "天蓝", rgb: RGBColor(100, 170, 240), symbol: "g", brand: "generic"),
    BeadColor(id: "C34", name: "蓝色", rgb: RGBColor(50, 100, 200), symbol: "h", brand: "generic"),
    BeadColor(id: "C35", name: "深蓝", rgb: RGBColor(30, 50, 140), symbol: "i", brand: "generic"),
    BeadColor(id: "C36", name: "浅绿", rgb: RGBColor(170, 225, 170), symbol: "j", brand: "generic"),
    BeadColor(id: "C37", name: "草绿", rgb: RGBColor(100, 190, 80), symbol: "k", brand: "generic"),
    BeadColor(id: "C38", name: "绿色", rgb: RGBColor(50, 140, 50), symbol: "l", brand: "generic"),
    BeadColor(id: "C39", name: "深绿", rgb: RGBColor(25, 90, 30), symbol: "m", brand: "generic"),
    BeadColor(id: "C40", name: "浅紫", rgb: RGBColor(210, 190, 235), symbol: "n", brand: "generic"),
    BeadColor(id: "C41", name: "紫色", rgb: RGBColor(150, 100, 200), symbol: "o", brand: "generic"),
    BeadColor(id: "C42", name: "深紫", rgb: RGBColor(90, 50, 140), symbol: "p", brand: "generic"),
    BeadColor(id: "C43", name: "桃色", rgb: RGBColor(255, 185, 150), symbol: "q", brand: "generic"),
    BeadColor(id: "C44", name: "肉色", rgb: RGBColor(255, 220, 195), symbol: "r", brand: "generic"),
    BeadColor(id: "C45", name: "腮红", rgb: RGBColor(240, 150, 140), symbol: "s", brand: "generic"),
    BeadColor(id: "C46", name: "砖红", rgb: RGBColor(170, 75, 55), symbol: "t", brand: "generic"),
    BeadColor(id: "C47", name: "卡其", rgb: RGBColor(190, 175, 130), symbol: "u", brand: "generic"),
    BeadColor(id: "C48", name: "橄榄", rgb: RGBColor(110, 120, 60), symbol: "v", brand: "generic"),
])

// MARK: - 宠物基础 96 色

public let palettePetBasic96 = BeadPaletteDef(id: "pet_basic_96", name: "宠物基础 96 色", colors: [
    BeadColor(id: "P01", name: "纯白", rgb: RGBColor(255, 255, 255), symbol: "A", brand: "pet"),
    BeadColor(id: "P02", name: "暖白", rgb: RGBColor(255, 252, 245), symbol: "B", brand: "pet"),
    BeadColor(id: "P03", name: "奶油白", rgb: RGBColor(255, 250, 235), symbol: "C", brand: "pet"),
    BeadColor(id: "P04", name: "象牙白", rgb: RGBColor(255, 245, 225), symbol: "D", brand: "pet"),
    BeadColor(id: "P05", name: "奶白", rgb: RGBColor(255, 248, 240), symbol: "E", brand: "pet"),
    BeadColor(id: "P06", name: "极浅灰", rgb: RGBColor(230, 230, 230), symbol: "F", brand: "pet"),
    BeadColor(id: "P07", name: "浅灰", rgb: RGBColor(200, 200, 200), symbol: "G", brand: "pet"),
    BeadColor(id: "P08", name: "中灰", rgb: RGBColor(150, 150, 150), symbol: "H", brand: "pet"),
    BeadColor(id: "P09", name: "暖灰", rgb: RGBColor(185, 178, 170), symbol: "I", brand: "pet"),
    BeadColor(id: "P10", name: "冷灰", rgb: RGBColor(165, 170, 180), symbol: "J", brand: "pet"),
    BeadColor(id: "P11", name: "褐灰", rgb: RGBColor(155, 142, 132), symbol: "K", brand: "pet"),
    BeadColor(id: "P12", name: "深灰", rgb: RGBColor(90, 90, 90), symbol: "L", brand: "pet"),
    BeadColor(id: "P13", name: "暖深灰", rgb: RGBColor(115, 105, 95), symbol: "M", brand: "pet"),
    BeadColor(id: "P14", name: "炭黑", rgb: RGBColor(45, 40, 40), symbol: "N", brand: "pet"),
    BeadColor(id: "P15", name: "近黑", rgb: RGBColor(30, 28, 26), symbol: "O", brand: "pet"),
    BeadColor(id: "P16", name: "纯黑", rgb: RGBColor(0, 0, 0), symbol: "P", brand: "pet"),
    BeadColor(id: "P17", name: "浅米", rgb: RGBColor(250, 242, 225), symbol: "Q", brand: "pet"),
    BeadColor(id: "P18", name: "米黄", rgb: RGBColor(245, 232, 200), symbol: "R", brand: "pet"),
    BeadColor(id: "P19", name: "浅麦", rgb: RGBColor(240, 225, 185), symbol: "S", brand: "pet"),
    BeadColor(id: "P20", name: "小麦色", rgb: RGBColor(235, 218, 175), symbol: "T", brand: "pet"),
    BeadColor(id: "P21", name: "淡黄", rgb: RGBColor(255, 255, 175), symbol: "U", brand: "pet"),
    BeadColor(id: "P22", name: "浅黄", rgb: RGBColor(255, 245, 120), symbol: "V", brand: "pet"),
    BeadColor(id: "P23", name: "浅橘", rgb: RGBColor(255, 215, 160), symbol: "W", brand: "pet"),
    BeadColor(id: "P24", name: "浅橘黄", rgb: RGBColor(255, 200, 120), symbol: "X", brand: "pet"),
    BeadColor(id: "P25", name: "橘黄", rgb: RGBColor(255, 185, 80), symbol: "Y", brand: "pet"),
    BeadColor(id: "P26", name: "橘色", rgb: RGBColor(255, 160, 50), symbol: "Z", brand: "pet"),
    BeadColor(id: "P27", name: "深橘", rgb: RGBColor(240, 135, 35), symbol: "a", brand: "pet"),
    BeadColor(id: "P28", name: "暗橘", rgb: RGBColor(220, 120, 40), symbol: "b", brand: "pet"),
    BeadColor(id: "P29", name: "杏色", rgb: RGBColor(255, 200, 165), symbol: "c", brand: "pet"),
    BeadColor(id: "P30", name: "桃色", rgb: RGBColor(255, 190, 145), symbol: "d", brand: "pet"),
    BeadColor(id: "P31", name: "浅棕", rgb: RGBColor(200, 170, 130), symbol: "e", brand: "pet"),
    BeadColor(id: "P32", name: "驼色", rgb: RGBColor(210, 185, 145), symbol: "f", brand: "pet"),
    BeadColor(id: "P33", name: "卡其", rgb: RGBColor(195, 178, 135), symbol: "g", brand: "pet"),
    BeadColor(id: "P34", name: "黄棕", rgb: RGBColor(185, 150, 100), symbol: "h", brand: "pet"),
    BeadColor(id: "P35", name: "中棕", rgb: RGBColor(165, 130, 85), symbol: "i", brand: "pet"),
    BeadColor(id: "P36", name: "橘棕", rgb: RGBColor(175, 125, 75), symbol: "j", brand: "pet"),
    BeadColor(id: "P37", name: "红棕", rgb: RGBColor(160, 100, 65), symbol: "k", brand: "pet"),
    BeadColor(id: "P38", name: "深棕", rgb: RGBColor(120, 80, 50), symbol: "l", brand: "pet"),
    BeadColor(id: "P39", name: "巧克力", rgb: RGBColor(90, 58, 35), symbol: "m", brand: "pet"),
    BeadColor(id: "P40", name: "咖啡", rgb: RGBColor(70, 42, 25), symbol: "n", brand: "pet"),
    BeadColor(id: "P41", name: "深咖啡", rgb: RGBColor(50, 30, 18), symbol: "o", brand: "pet"),
    BeadColor(id: "P42", name: "近黑棕", rgb: RGBColor(40, 28, 22), symbol: "p", brand: "pet"),
    BeadColor(id: "P43", name: "灰米", rgb: RGBColor(215, 205, 190), symbol: "q", brand: "pet"),
    BeadColor(id: "P44", name: "灰棕", rgb: RGBColor(170, 155, 140), symbol: "r", brand: "pet"),
    BeadColor(id: "P45", name: "暗灰棕", rgb: RGBColor(135, 120, 108), symbol: "s", brand: "pet"),
    BeadColor(id: "P46", name: "冷灰棕", rgb: RGBColor(145, 140, 138), symbol: "t", brand: "pet"),
    BeadColor(id: "P47", name: "蓝灰", rgb: RGBColor(140, 148, 162), symbol: "u", brand: "pet"),
    BeadColor(id: "P48", name: "暗蓝灰", rgb: RGBColor(100, 108, 122), symbol: "v", brand: "pet"),
    BeadColor(id: "P49", name: "浅粉", rgb: RGBColor(255, 215, 222), symbol: "w", brand: "pet"),
    BeadColor(id: "P50", name: "粉色", rgb: RGBColor(255, 160, 185), symbol: "x", brand: "pet"),
    BeadColor(id: "P51", name: "肉粉", rgb: RGBColor(255, 200, 185), symbol: "y", brand: "pet"),
    BeadColor(id: "P52", name: "玫红", rgb: RGBColor(230, 85, 130), symbol: "z", brand: "pet"),
    BeadColor(id: "P53", name: "腮红", rgb: RGBColor(242, 155, 142), symbol: "0", brand: "pet"),
    BeadColor(id: "P54", name: "砖红", rgb: RGBColor(175, 78, 58), symbol: "1", brand: "pet"),
    BeadColor(id: "P55", name: "红色", rgb: RGBColor(220, 55, 55), symbol: "2", brand: "pet"),
    BeadColor(id: "P56", name: "深红", rgb: RGBColor(165, 35, 35), symbol: "3", brand: "pet"),
    BeadColor(id: "P57", name: "暗红", rgb: RGBColor(130, 30, 30), symbol: "4", brand: "pet"),
    BeadColor(id: "P58", name: "浅蓝", rgb: RGBColor(165, 215, 255), symbol: "5", brand: "pet"),
    BeadColor(id: "P59", name: "天蓝", rgb: RGBColor(105, 175, 242), symbol: "6", brand: "pet"),
    BeadColor(id: "P60", name: "蓝色", rgb: RGBColor(55, 105, 200), symbol: "7", brand: "pet"),
    BeadColor(id: "P61", name: "深蓝", rgb: RGBColor(35, 55, 145), symbol: "8", brand: "pet"),
    BeadColor(id: "P62", name: "藏青", rgb: RGBColor(25, 35, 90), symbol: "9", brand: "pet"),
    BeadColor(id: "P63", name: "浅绿", rgb: RGBColor(175, 228, 175), symbol: "+", brand: "pet"),
    BeadColor(id: "P64", name: "草绿", rgb: RGBColor(105, 192, 82), symbol: "-", brand: "pet"),
    BeadColor(id: "P65", name: "绿色", rgb: RGBColor(55, 142, 55), symbol: "*", brand: "pet"),
    BeadColor(id: "P66", name: "深绿", rgb: RGBColor(28, 95, 32), symbol: "=", brand: "pet"),
    BeadColor(id: "P67", name: "浅紫", rgb: RGBColor(215, 195, 238), symbol: "@", brand: "pet"),
    BeadColor(id: "P68", name: "紫色", rgb: RGBColor(155, 105, 205), symbol: "#", brand: "pet"),
    BeadColor(id: "P69", name: "深紫", rgb: RGBColor(95, 55, 145), symbol: "$", brand: "pet"),
    BeadColor(id: "P70", name: "肉色", rgb: RGBColor(255, 222, 198), symbol: "%", brand: "pet"),
    BeadColor(id: "P71", name: "橄榄", rgb: RGBColor(115, 125, 65), symbol: "^", brand: "pet"),
    BeadColor(id: "P72", name: "芥末", rgb: RGBColor(195, 180, 60), symbol: "&", brand: "pet"),
    BeadColor(id: "P73", name: "橡皮粉", rgb: RGBColor(240, 200, 210), symbol: "~", brand: "pet"),
    BeadColor(id: "P74", name: "近黑灰", rgb: RGBColor(55, 55, 55), symbol: "!", brand: "pet"),
    BeadColor(id: "P75", name: "暖炭", rgb: RGBColor(65, 55, 48), symbol: "?", brand: "pet"),
    BeadColor(id: "P76", name: "冷炭", rgb: RGBColor(48, 52, 58), symbol: "<", brand: "pet"),
    BeadColor(id: "P77", name: "鼻粉", rgb: RGBColor(235, 175, 170), symbol: ">", brand: "pet"),
    BeadColor(id: "P78", name: "鼻棕", rgb: RGBColor(140, 95, 80), symbol: "[", brand: "pet"),
    BeadColor(id: "P79", name: "鼻黑", rgb: RGBColor(35, 30, 30), symbol: "]", brand: "pet"),
    BeadColor(id: "P80", name: "眼棕", rgb: RGBColor(85, 55, 35), symbol: "{", brand: "pet"),
    BeadColor(id: "P81", name: "眼琥珀", rgb: RGBColor(185, 135, 55), symbol: "}", brand: "pet"),
    BeadColor(id: "P82", name: "眼绿", rgb: RGBColor(120, 165, 80), symbol: "|", brand: "pet"),
    BeadColor(id: "P83", name: "眼蓝", rgb: RGBColor(95, 145, 195), symbol: ";", brand: "pet"),
    BeadColor(id: "P84", name: "眼黄", rgb: RGBColor(225, 195, 60), symbol: ":", brand: "pet"),
    BeadColor(id: "P85", name: "浅橘灰", rgb: RGBColor(215, 195, 175), symbol: ",", brand: "pet"),
    BeadColor(id: "P86", name: "暗橘灰", rgb: RGBColor(175, 155, 135), symbol: ".", brand: "pet"),
    BeadColor(id: "P87", name: "暖米灰", rgb: RGBColor(225, 215, 200), symbol: "/", brand: "pet"),
    BeadColor(id: "P88", name: "冷米灰", rgb: RGBColor(210, 212, 218), symbol: "(", brand: "pet"),
    BeadColor(id: "P89", name: "浅茶", rgb: RGBColor(190, 160, 125), symbol: ")", brand: "pet"),
    BeadColor(id: "P90", name: "暗茶", rgb: RGBColor(145, 115, 85), symbol: "_", brand: "pet"),
    BeadColor(id: "P91", name: "焦糖", rgb: RGBColor(195, 120, 55), symbol: "`", brand: "pet"),
    BeadColor(id: "P92", name: "锈红", rgb: RGBColor(180, 70, 40), symbol: "'", brand: "pet"),
    BeadColor(id: "P93", name: "灰白", rgb: RGBColor(238, 238, 238), symbol: "\"", brand: "pet"),
    BeadColor(id: "P94", name: "银灰", rgb: RGBColor(192, 196, 200), symbol: "\\", brand: "pet"),
    BeadColor(id: "P95", name: "鼠灰", rgb: RGBColor(128, 128, 128), symbol: "§", brand: "pet"),
    BeadColor(id: "P96", name: "铁灰", rgb: RGBColor(72, 75, 80), symbol: "°", brand: "pet"),
])

// MARK: - 宠物全色 160 色（pet_basic_96 + 64 过渡色）

public let palettePetFull160 = BeadPaletteDef(id: "pet_full_160", name: "宠物全色 160 色", colors:
    palettePetBasic96.colors + [
    BeadColor(id: "X01", name: "珍珠白", rgb: RGBColor(252, 250, 248), symbol: "aa", brand: "pet"),
    BeadColor(id: "X02", name: "雪白", rgb: RGBColor(250, 250, 252), symbol: "ab", brand: "pet"),
    BeadColor(id: "X03", name: "米白", rgb: RGBColor(248, 245, 235), symbol: "ac", brand: "pet"),
    BeadColor(id: "X04", name: "粉白", rgb: RGBColor(255, 248, 245), symbol: "ad", brand: "pet"),
    BeadColor(id: "X05", name: "极浅暖灰", rgb: RGBColor(222, 218, 214), symbol: "ae", brand: "pet"),
    BeadColor(id: "X06", name: "浅暖灰", rgb: RGBColor(198, 192, 186), symbol: "af", brand: "pet"),
    BeadColor(id: "X07", name: "中暖灰", rgb: RGBColor(168, 160, 152), symbol: "ag", brand: "pet"),
    BeadColor(id: "X08", name: "深暖灰", rgb: RGBColor(128, 120, 112), symbol: "ah", brand: "pet"),
    BeadColor(id: "X09", name: "极浅冷灰", rgb: RGBColor(218, 220, 225), symbol: "ai", brand: "pet"),
    BeadColor(id: "X10", name: "中冷灰", rgb: RGBColor(148, 152, 162), symbol: "aj", brand: "pet"),
    BeadColor(id: "X11", name: "极浅橘", rgb: RGBColor(255, 225, 185), symbol: "ak", brand: "pet"),
    BeadColor(id: "X12", name: "淡橘黄", rgb: RGBColor(255, 210, 145), symbol: "al", brand: "pet"),
    BeadColor(id: "X13", name: "浅橘棕", rgb: RGBColor(230, 175, 100), symbol: "am", brand: "pet"),
    BeadColor(id: "X14", name: "橘红", rgb: RGBColor(245, 120, 45), symbol: "an", brand: "pet"),
    BeadColor(id: "X15", name: "深橘红", rgb: RGBColor(215, 95, 35), symbol: "ao", brand: "pet"),
    BeadColor(id: "X16", name: "极暗橘", rgb: RGBColor(185, 85, 35), symbol: "ap", brand: "pet"),
    BeadColor(id: "X17", name: "极浅棕", rgb: RGBColor(215, 190, 155), symbol: "aq", brand: "pet"),
    BeadColor(id: "X18", name: "浅驼", rgb: RGBColor(225, 200, 162), symbol: "ar", brand: "pet"),
    BeadColor(id: "X19", name: "沙棕", rgb: RGBColor(205, 180, 145), symbol: "as", brand: "pet"),
    BeadColor(id: "X20", name: "中黄棕", rgb: RGBColor(175, 142, 95), symbol: "at", brand: "pet"),
    BeadColor(id: "X21", name: "暗棕", rgb: RGBColor(135, 95, 60), symbol: "au", brand: "pet"),
    BeadColor(id: "X22", name: "极深棕", rgb: RGBColor(80, 48, 28), symbol: "av", brand: "pet"),
    BeadColor(id: "X23", name: "焦棕", rgb: RGBColor(100, 60, 32), symbol: "aw", brand: "pet"),
    BeadColor(id: "X24", name: "栗棕", rgb: RGBColor(110, 68, 42), symbol: "ax", brand: "pet"),
    BeadColor(id: "X25", name: "浅灰棕", rgb: RGBColor(192, 182, 170), symbol: "ay", brand: "pet"),
    BeadColor(id: "X26", name: "中灰棕", rgb: RGBColor(162, 148, 135), symbol: "az", brand: "pet"),
    BeadColor(id: "X27", name: "深灰棕", rgb: RGBColor(122, 108, 95), symbol: "ba", brand: "pet"),
    BeadColor(id: "X28", name: "冷灰棕", rgb: RGBColor(138, 140, 148), symbol: "bb", brand: "pet"),
    BeadColor(id: "X29", name: "浅蓝灰", rgb: RGBColor(188, 195, 208), symbol: "bc", brand: "pet"),
    BeadColor(id: "X30", name: "深蓝灰", rgb: RGBColor(108, 118, 138), symbol: "bd", brand: "pet"),
    BeadColor(id: "X31", name: "浅米黄", rgb: RGBColor(248, 240, 210), symbol: "be", brand: "pet"),
    BeadColor(id: "X32", name: "深米黄", rgb: RGBColor(238, 225, 188), symbol: "bf", brand: "pet"),
    BeadColor(id: "X33", name: "暖杏", rgb: RGBColor(242, 215, 182), symbol: "bg", brand: "pet"),
    BeadColor(id: "X34", name: "暗杏", rgb: RGBColor(228, 195, 158), symbol: "bh", brand: "pet"),
    BeadColor(id: "X35", name: "极深灰", rgb: RGBColor(60, 58, 56), symbol: "bi", brand: "pet"),
    BeadColor(id: "X36", name: "暖黑", rgb: RGBColor(38, 32, 28), symbol: "bj", brand: "pet"),
    BeadColor(id: "X37", name: "冷黑", rgb: RGBColor(22, 25, 30), symbol: "bk", brand: "pet"),
    BeadColor(id: "X38", name: "棕黑", rgb: RGBColor(32, 22, 18), symbol: "bl", brand: "pet"),
    BeadColor(id: "X39", name: "极浅粉", rgb: RGBColor(255, 230, 235), symbol: "bm", brand: "pet"),
    BeadColor(id: "X40", name: "暖粉", rgb: RGBColor(248, 185, 175), symbol: "bn", brand: "pet"),
    BeadColor(id: "X41", name: "暗粉", rgb: RGBColor(210, 130, 140), symbol: "bo", brand: "pet"),
    BeadColor(id: "X42", name: "深玫红", rgb: RGBColor(195, 60, 100), symbol: "bp", brand: "pet"),
    BeadColor(id: "X43", name: "极浅蓝", rgb: RGBColor(200, 228, 255), symbol: "bq", brand: "pet"),
    BeadColor(id: "X44", name: "灰蓝", rgb: RGBColor(135, 158, 195), symbol: "br", brand: "pet"),
    BeadColor(id: "X45", name: "深灰蓝", rgb: RGBColor(75, 88, 135), symbol: "bs", brand: "pet"),
    BeadColor(id: "X46", name: "宝蓝", rgb: RGBColor(40, 70, 180), symbol: "bt", brand: "pet"),
    BeadColor(id: "X47", name: "极浅绿", rgb: RGBColor(210, 240, 210), symbol: "bu", brand: "pet"),
    BeadColor(id: "X48", name: "灰绿", rgb: RGBColor(140, 175, 140), symbol: "bv", brand: "pet"),
    BeadColor(id: "X49", name: "深灰绿", rgb: RGBColor(80, 110, 80), symbol: "bw", brand: "pet"),
    BeadColor(id: "X50", name: "墨绿", rgb: RGBColor(20, 65, 25), symbol: "bx", brand: "pet"),
    BeadColor(id: "X51", name: "极浅紫", rgb: RGBColor(232, 218, 248), symbol: "by", brand: "pet"),
    BeadColor(id: "X52", name: "灰紫", rgb: RGBColor(168, 152, 192), symbol: "bz", brand: "pet"),
    BeadColor(id: "X53", name: "暗紫", rgb: RGBColor(72, 38, 108), symbol: "ca", brand: "pet"),
    BeadColor(id: "X54", name: "浅橘奶", rgb: RGBColor(252, 225, 195), symbol: "cb", brand: "pet"),
    BeadColor(id: "X55", name: "暗橘奶", rgb: RGBColor(235, 200, 165), symbol: "cc", brand: "pet"),
    BeadColor(id: "X56", name: "浅黄棕", rgb: RGBColor(220, 198, 155), symbol: "cd", brand: "pet"),
    BeadColor(id: "X57", name: "暖棕灰", rgb: RGBColor(148, 132, 118), symbol: "ce", brand: "pet"),
    BeadColor(id: "X58", name: "冷棕灰", rgb: RGBColor(132, 135, 142), symbol: "cf", brand: "pet"),
    BeadColor(id: "X59", name: "浅铁锈", rgb: RGBColor(198, 115, 85), symbol: "cg", brand: "pet"),
    BeadColor(id: "X60", name: "深铁锈", rgb: RGBColor(155, 75, 50), symbol: "ch", brand: "pet"),
    BeadColor(id: "X61", name: "浅栗", rgb: RGBColor(185, 135, 95), symbol: "ci", brand: "pet"),
    BeadColor(id: "X62", name: "深栗", rgb: RGBColor(125, 78, 48), symbol: "cj", brand: "pet"),
    BeadColor(id: "X63", name: "暖米棕", rgb: RGBColor(208, 188, 158), symbol: "ck", brand: "pet"),
    BeadColor(id: "X64", name: "冷米棕", rgb: RGBColor(188, 185, 178), symbol: "cl", brand: "pet"),
])

// MARK: - 查询函数

/// 根据色板 ID 获取色板定义。对应源端 `getBeadPalette`。
/// 未知 ID 返回 nil。
public func getBeadPalette(_ paletteId: String) -> BeadPaletteDef? {
    switch paletteId {
    case "generic_24": return paletteGeneric24
    case "generic_48": return paletteGeneric48
    case "pet_basic_96": return palettePetBasic96
    case "pet_full_160": return palettePetFull160
    default:
        if paletteId.hasPrefix("MARD_") {
            let colors: [BeadColor]
            if paletteId == "MARD_PET_96" || paletteId == "MARD_PET_160" {
                colors = getMardPetColors(paletteId)
            } else {
                colors = getMardColorsBySet(paletteId)
            }
            let label = mardSetLabels[paletteId] ?? String(paletteId.dropFirst("MARD_".count))
            return BeadPaletteDef(id: paletteId, name: "MARD " + label, colors: colors)
        }
        return nil
    }
}

/// 列出所有可用色板。对应源端 `getAvailablePalettes`。
public func getAvailablePalettes() -> [PaletteInfo] {
    return [
        PaletteInfo(id: "MARD_120", name: "MARD 120 色（推荐）"),
        PaletteInfo(id: "MARD_PET_96", name: "MARD 宠物精选 96 色"),
        PaletteInfo(id: "MARD_PET_160", name: "MARD 宠物精选 160 色"),
        PaletteInfo(id: "MARD_72", name: "MARD 72 色（入门）"),
        PaletteInfo(id: "MARD_96", name: "MARD 96 色（基础）"),
        PaletteInfo(id: "MARD_144", name: "MARD 144 色"),
        PaletteInfo(id: "MARD_221", name: "MARD 221 色（专业）"),
        PaletteInfo(id: "MARD_291", name: "MARD 291 色（全部）"),
        PaletteInfo(id: "pet_basic_96", name: "通用宠物 96 色（旧版）"),
        PaletteInfo(id: "pet_full_160", name: "通用宠物 160 色（旧版）"),
    ]
}
