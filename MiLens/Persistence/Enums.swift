//  宠物种类与性别枚举 —— 翻译自源端 models/Pet.ets（Species / Gender）。
//  SwiftData 以 Int rawValue 持久化，保持与源端数值稳定（0/1/2）。

import Foundation

/// 宠物种类（源端 Species）
enum Species: Int, Codable, CaseIterable {
    case unknown = 0
    case cat = 1
    case dog = 2
}

/// 宠物性别（源端 Gender）
enum Gender: Int, Codable, CaseIterable {
    case unknown = 0
    case male = 1
    case female = 2
}
