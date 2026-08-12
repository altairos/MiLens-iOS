//  MiLensWidgetBundle —— Widget Extension 入口（@main）。
//
//  注册 5 种 Widget（WidgetKit-Design.md §2 组件矩阵）：
//  1. 相片回声 PhotoEcho（Small / Medium / Large）
//  2. 纪念日 UpcomingDay（Small / Medium）
//  3. 档案年轮 LifeArchive（Medium / Large）
//  4. 锁屏·倒计时 LockScreenCircular（AccessoryCircular）
//  5. 锁屏·一段回忆 LockScreenRectangular（AccessoryRectangular）

import WidgetKit
import SwiftUI

@main
struct MiLensWidgetBundle: WidgetBundle {
    var body: some Widget {
        PhotoEchoWidget()
        UpcomingDayWidget()
        LifeArchiveWidget()
        LockScreenCircularWidget()
        LockScreenRectangularWidget()
    }
}
