import XCTest
@testable import MiLensKit

// 编辑器 ViewModel 纯逻辑测试。
// 逐条翻译源端 7 个黄金规格测试文件：
// - EditorToolViewModel.test.ets (323 行 / ~60 用例)
// - EditorCropViewModel.test.ets (190 行 / ~20 用例)
// - EditorCanvasViewModel.test.ets (59 行 / ~8 用例)
// - EditorAdjustViewModel.test.ets (235 行 / ~30 用例)
// - EditorCutoutViewModel.test.ets (156 行 / ~20 用例)
// - EditorSaveViewModel.test.ets (133 行 / ~15 用例)
// - EditorTextToolViewModel.test.ets (104 行 / ~15 用例)

// MARK: - EditorToolLogic

final class EditorToolLogicConstantsTests: XCTestCase {

    func testAspectRatioBounds() {
        XCTAssertEqual(MIN_CANVAS_ASPECT_RATIO, 0.6)
        XCTAssertEqual(MAX_CANVAS_ASPECT_RATIO, 1.8)
    }

    func testTextDefaults() {
        XCTAssertEqual(DEFAULT_TEXT_FONT_SIZE, 32)
        XCTAssertEqual(DEFAULT_TEXT_COLOR, "#FFFFFF")
        XCTAssertTrue(DEFAULT_TEXT_STROKE_ENABLED)
        XCTAssertEqual(DEFAULT_TEXT_STROKE_WIDTH, 2)
        XCTAssertEqual(TEXT_STROKE_DISABLED_WIDTH, 0)
    }

    func testCropInitMargin() {
        XCTAssertEqual(CROP_INIT_MARGIN, 0.1)
    }

    func testCropRatiosHas5EntriesStartingWithFree() {
        XCTAssertEqual(CROP_RATIOS.count, 5)
        XCTAssertEqual(CROP_RATIOS[0].label, "自由")
        XCTAssertNil(CROP_RATIOS[0].value)
    }

    func testPresetColorsHas5Entries() {
        XCTAssertEqual(PRESET_COLORS.count, 5)
        XCTAssertEqual(PRESET_COLORS[0], "#FFFFFF")
    }
}

final class EditorToolLogicClampAspectRatioTests: XCTestCase {

    func testReturnsMinForNaN() {
        XCTAssertEqual(clampAspectRatio(.nan), MIN_CANVAS_ASPECT_RATIO)
    }

    func testReturnsMinForInfinity() {
        XCTAssertEqual(clampAspectRatio(.infinity), MIN_CANVAS_ASPECT_RATIO)
    }

    func testClampsUnderMinToMin() {
        XCTAssertEqual(clampAspectRatio(0.1), MIN_CANVAS_ASPECT_RATIO)
    }

    func testClampsOverMaxToMax() {
        XCTAssertEqual(clampAspectRatio(3.5), MAX_CANVAS_ASPECT_RATIO)
    }

    func testPassesThroughInRangeValues() {
        XCTAssertEqual(clampAspectRatio(1), 1)
        XCTAssertEqual(clampAspectRatio(1.5), 1.5)
    }
}

final class EditorToolLogicTextDefaultsTests: XCTestCase {

    func testDefaultTextLayerState() {
        let d = defaultTextLayerState()
        XCTAssertEqual(d.fontSize, DEFAULT_TEXT_FONT_SIZE)
        XCTAssertEqual(d.color, DEFAULT_TEXT_COLOR)
        XCTAssertTrue(d.strokeEnabled)
        XCTAssertEqual(d.strokeWidth, DEFAULT_TEXT_STROKE_WIDTH)
    }

    func testResolveStrokeWidthEnabled() {
        XCTAssertEqual(resolveStrokeWidth(true), DEFAULT_TEXT_STROKE_WIDTH)
    }

    func testResolveStrokeWidthDisabled() {
        XCTAssertEqual(resolveStrokeWidth(false), TEXT_STROKE_DISABLED_WIDTH)
    }
}

final class EditorToolLogicCropRatioTests: XCTestCase {

    func testCropRatioOptionsReturnsCopy() {
        let a = cropRatioOptions()
        XCTAssertEqual(a.count, CROP_RATIOS.count)
        // Swift 值语义天然满足"每次返回新数组"
        let b = cropRatioOptions()
        XCTAssertEqual(a, b)
    }

    func testCropRatioLabels() {
        let labels = cropRatioLabels()
        XCTAssertEqual(labels.count, 5)
        XCTAssertEqual(labels[0], "自由")
        XCTAssertEqual(labels[4], "16:9")
    }

    func testResolveCropRatioByIndexValid() {
        XCTAssertNil(resolveCropRatioByIndex(0))
        XCTAssertEqual(resolveCropRatioByIndex(1)!, 1)
        XCTAssertEqual(resolveCropRatioByIndex(2)!, 4.0 / 3.0, accuracy: 0.001)
    }

    func testResolveCropRatioByIndexOutOfRange() {
        XCTAssertNil(resolveCropRatioByIndex(-1))
        XCTAssertNil(resolveCropRatioByIndex(99))
    }
}

final class EditorToolLogicToggleTests: XCTestCase {

    func testToggleOffWhenClickingActiveTool() {
        let d = resolveToolToggle(currentTool: .crop, targetTool: .crop)
        XCTAssertEqual(d.newTool, .none)
        XCTAssertFalse(d.shouldInitCrop)
    }

    func testToggleOnWhenClickingInactiveTool() {
        let d = resolveToolToggle(currentTool: .none, targetTool: .crop)
        XCTAssertEqual(d.newTool, .crop)
        XCTAssertTrue(d.shouldInitCrop)
    }

    func testSwitchingToNonCropToolNoInit() {
        let d = resolveToolToggle(currentTool: .crop, targetTool: .rotate)
        XCTAssertEqual(d.newTool, .rotate)
        XCTAssertFalse(d.shouldInitCrop)
    }

    func testSwitchingToBeadFromNone() {
        let d = resolveToolToggle(currentTool: .none, targetTool: .bead)
        XCTAssertEqual(d.newTool, .bead)
        XCTAssertFalse(d.shouldInitCrop)
    }

    func testResolveToolTabActiveMatches() {
        XCTAssertTrue(resolveToolTabActive(currentTool: .crop, mode: .crop))
    }

    func testResolveToolTabActiveRejects() {
        XCTAssertFalse(resolveToolTabActive(currentTool: .crop, mode: .rotate))
    }
}

final class EditorToolLogicComputeCropInitRegionTests: XCTestCase {

    func testZeroRegionForNonPositiveCanvas() {
        let r = computeCropInitRegion(canvasW: 0, canvasH: 100, ratio: nil)
        XCTAssertEqual(r.w, 0)
        XCTAssertEqual(r.h, 0)
        let r2 = computeCropInitRegion(canvasW: 100, canvasH: 0, ratio: 1)
        XCTAssertEqual(r2.w, 0)
    }

    func testFreeRatioUses80PercentAndCenters() {
        let r = computeCropInitRegion(canvasW: 1000, canvasH: 1000, ratio: nil)
        XCTAssertEqual(r.w, 800)
        XCTAssertEqual(r.h, 800)
        XCTAssertEqual(r.x, 100)
        XCTAssertEqual(r.y, 100)
    }

    func testOneToOneOnSquareMatchesFree() {
        let r = computeCropInitRegion(canvasW: 1000, canvasH: 1000, ratio: 1)
        XCTAssertEqual(r.w, 800)
        XCTAssertEqual(r.h, 800)
    }

    func testFourThreeOnWideCanvasFitsByHeight() {
        // canvas 1000×500 → maxW=800, maxH=400
        // maxW/maxH = 2 > 4/3 → cropH=400, cropW=400*4/3 ≈ 533.33
        let r = computeCropInitRegion(canvasW: 1000, canvasH: 500, ratio: 4.0 / 3.0)
        XCTAssertEqual(r.h, 400)
        XCTAssertEqual(r.w, 400 * 4.0 / 3.0, accuracy: 0.01)
    }

    func testSixteenNineOnTallCanvasFitsByWidth() {
        let r = computeCropInitRegion(canvasW: 500, canvasH: 1000, ratio: 16.0 / 9.0)
        XCTAssertEqual(r.w, 400)
        XCTAssertEqual(r.h, 400 / (16.0 / 9.0), accuracy: 0.01)
    }
}

final class EditorToolLogicGroupTests: XCTestCase {

    // resolveToolGroup
    func testResolveToolGroupAdjust() {
        XCTAssertEqual(resolveToolGroup(.crop), .adjust)
        XCTAssertEqual(resolveToolGroup(.rotate), .adjust)
        XCTAssertEqual(resolveToolGroup(.adjust), .adjust)
    }

    func testResolveToolGroupDecorate() {
        XCTAssertEqual(resolveToolGroup(.text), .decorate)
        XCTAssertEqual(resolveToolGroup(.sticker), .decorate)
        XCTAssertEqual(resolveToolGroup(.frame), .decorate)
    }

    func testResolveToolGroupCreate() {
        XCTAssertEqual(resolveToolGroup(.bead), .create)
    }

    func testResolveToolGroupSmart() {
        XCTAssertEqual(resolveToolGroup(.cutout), .smart)
    }

    func testResolveToolGroupNone() {
        XCTAssertEqual(resolveToolGroup(.none), .none)
    }

    // toolsInGroup
    func testAdjustGroupHas3Tools() {
        let tools = toolsInGroup(.adjust)
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0].label, "裁剪")
        XCTAssertEqual(tools[0].mode, .crop)
        XCTAssertEqual(tools[2].label, "调色")
    }

    func testDecorateGroupHas3Tools() {
        let tools = toolsInGroup(.decorate)
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0].mode, .text)
        XCTAssertEqual(tools[2].mode, .frame)
    }

    func testCreateGroupHasBeadOnly() {
        let tools = toolsInGroup(.create)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].label, "拼豆")
        XCTAssertEqual(tools[0].mode, .bead)
    }

    func testSmartGroupHasCutout() {
        let tools = toolsInGroup(.smart)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].label, "抠图")
        XCTAssertEqual(tools[0].mode, .cutout)
    }

    func testNoneGroupIsEmpty() {
        XCTAssertEqual(toolsInGroup(.none).count, 0)
    }

    // resolveGroupToggle
    func testGroupToggleOffWhenClickingActive() {
        let d = resolveGroupToggle(currentGroup: .adjust, targetGroup: .adjust)
        XCTAssertEqual(d.newGroup, .none)
        XCTAssertEqual(d.newTool, .none)
    }

    func testGroupSwitchWithToolReset() {
        let d = resolveGroupToggle(currentGroup: .none, targetGroup: .decorate)
        XCTAssertEqual(d.newGroup, .decorate)
        XCTAssertEqual(d.newTool, .none)
    }

    func testGroupSwitchBetweenGroupsResetsTool() {
        let d = resolveGroupToggle(currentGroup: .adjust, targetGroup: .create)
        XCTAssertEqual(d.newGroup, .create)
        XCTAssertEqual(d.newTool, .none)
    }

    // isGroupTabActive
    func testGroupTabActiveTrueWhenToolBelongsToGroup() {
        XCTAssertTrue(isGroupTabActive(currentTool: .crop, group: .adjust))
        XCTAssertTrue(isGroupTabActive(currentTool: .rotate, group: .adjust))
        XCTAssertTrue(isGroupTabActive(currentTool: .text, group: .decorate))
        XCTAssertTrue(isGroupTabActive(currentTool: .bead, group: .create))
    }

    func testGroupTabActiveFalseWhenToolDoesNotBelong() {
        XCTAssertFalse(isGroupTabActive(currentTool: .crop, group: .decorate))
        XCTAssertFalse(isGroupTabActive(currentTool: .text, group: .adjust))
        XCTAssertFalse(isGroupTabActive(currentTool: .none, group: .adjust))
    }
}

// MARK: - EditorCropOverlay

final class EditorCropOverlayConstantsTests: XCTestCase {

    func testHandleDimensions() {
        XCTAssertEqual(CROP_HANDLE_LENGTH, 20)
        XCTAssertEqual(CROP_HANDLE_WIDTH, 4)
    }

    func testBorderGridWidths() {
        XCTAssertEqual(CROP_BORDER_WIDTH, 2)
        XCTAssertEqual(CROP_GRID_WIDTH, 1)
    }

    func testThirdsIndices() {
        XCTAssertEqual(CROP_THIRDS_INDICES.count, 2)
        XCTAssertEqual(CROP_THIRDS_INDICES[0], 1)
        XCTAssertEqual(CROP_THIRDS_INDICES[1], 2)
    }

    func testColors() {
        XCTAssertEqual(CROP_OVERLAY_COLOR, "rgba(0,0,0,0.5)")
        XCTAssertEqual(CROP_GRID_COLOR, "rgba(255,255,255,0.3)")
        XCTAssertEqual(CROP_BORDER_COLOR, "#FFFFFF")
    }
}

final class EditorCropOverlayMaskTests: XCTestCase {

    func testComputes4MaskRectsForCenteredCrop() {
        let rect = EditorCropRect(x: 200, y: 200, w: 600, h: 600)
        let mask = computeCropOverlayMask(canvasW: 1000, canvasH: 1000, rect: rect)
        XCTAssertEqual(mask.top.x, 0)
        XCTAssertEqual(mask.top.y, 0)
        XCTAssertEqual(mask.top.w, 1000)
        XCTAssertEqual(mask.top.h, 200)
        XCTAssertEqual(mask.bottom.y, 800)
        XCTAssertEqual(mask.bottom.h, 200)
        XCTAssertEqual(mask.left.w, 200)
        XCTAssertEqual(mask.left.h, 600)
        XCTAssertEqual(mask.right.x, 800)
        XCTAssertEqual(mask.right.w, 200)
    }

    func testTopLeftMasksZeroWhenCropTouchesOrigin() {
        let rect = EditorCropRect(x: 0, y: 0, w: 500, h: 500)
        let mask = computeCropOverlayMask(canvasW: 1000, canvasH: 1000, rect: rect)
        XCTAssertEqual(mask.top.h, 0)
        XCTAssertEqual(mask.left.w, 0)
    }

    func testAllMasksZeroWhenCropFillsCanvas() {
        let rect = EditorCropRect(x: 0, y: 0, w: 1000, h: 1000)
        let mask = computeCropOverlayMask(canvasW: 1000, canvasH: 1000, rect: rect)
        XCTAssertEqual(mask.top.h, 0)
        XCTAssertEqual(mask.bottom.h, 0)
        XCTAssertEqual(mask.left.w, 0)
        XCTAssertEqual(mask.right.w, 0)
    }
}

final class EditorCropOverlayThirdsTests: XCTestCase {

    func testReturns2x2LinesAtThirds() {
        let rect = EditorCropRect(x: 0, y: 0, w: 300, h: 600)
        let t = computeCropThirdsLines(rect: rect)
        XCTAssertEqual(t.xLines.count, 2)
        XCTAssertEqual(t.yLines.count, 2)
        XCTAssertEqual(t.xLines[0], 100)
        XCTAssertEqual(t.xLines[1], 200)
        XCTAssertEqual(t.yLines[0], 200)
        XCTAssertEqual(t.yLines[1], 400)
    }

    func testLinesOffsetByXY() {
        let rect = EditorCropRect(x: 50, y: 100, w: 300, h: 300)
        let t = computeCropThirdsLines(rect: rect)
        XCTAssertEqual(t.xLines[0], 50 + 100)
        XCTAssertEqual(t.yLines[0], 100 + 100)
    }
}

final class EditorCropOverlayHandlesTests: XCTestCase {

    func testReturns4HandlesWithCorrectDirections() {
        let rect = EditorCropRect(x: 10, y: 20, w: 100, h: 200)
        let handles = computeCropCornerHandles(rect: rect)
        XCTAssertEqual(handles.count, 4)
        // 左上 (1,1)
        XCTAssertEqual(handles[0].x, 10)
        XCTAssertEqual(handles[0].y, 20)
        XCTAssertEqual(handles[0].dx, 1)
        XCTAssertEqual(handles[0].dy, 1)
        // 右上 (-1,1)
        XCTAssertEqual(handles[1].x, 110)
        XCTAssertEqual(handles[1].y, 20)
        XCTAssertEqual(handles[1].dx, -1)
        XCTAssertEqual(handles[1].dy, 1)
        // 右下 (-1,-1)
        XCTAssertEqual(handles[2].x, 110)
        XCTAssertEqual(handles[2].y, 220)
        XCTAssertEqual(handles[2].dx, -1)
        XCTAssertEqual(handles[2].dy, -1)
        // 左下 (1,-1)
        XCTAssertEqual(handles[3].x, 10)
        XCTAssertEqual(handles[3].y, 220)
        XCTAssertEqual(handles[3].dx, 1)
        XCTAssertEqual(handles[3].dy, -1)
    }
}

final class EditorCropOverlayClampTests: XCTestCase {

    func testZeroForNonPositiveCanvas() {
        let r = clampCropRect(canvasW: 0, canvasH: 100, rect: .init(x: 0, y: 0, w: 50, h: 50))
        XCTAssertEqual(r.w, 0)
        XCTAssertEqual(r.h, 0)
    }

    func testZeroForNaNInputs() {
        let r = clampCropRect(canvasW: 100, canvasH: 100, rect: .init(x: .nan, y: 0, w: 50, h: 50))
        XCTAssertEqual(r.w, 0)
    }

    func testClampsXYToNonNegative() {
        let r = clampCropRect(canvasW: 1000, canvasH: 1000, rect: .init(x: -50, y: -30, w: 100, h: 100))
        XCTAssertEqual(r.x, 0)
        XCTAssertEqual(r.y, 0)
    }

    func testClampsXPlusWToCanvasW() {
        let r = clampCropRect(canvasW: 1000, canvasH: 1000, rect: .init(x: 950, y: 0, w: 100, h: 100))
        XCTAssertEqual(r.x, 900)
        XCTAssertEqual(r.w, 100)
    }

    func testClampsWHToCanvasSize() {
        let r = clampCropRect(canvasW: 500, canvasH: 300, rect: .init(x: 0, y: 0, w: 1000, h: 1000))
        XCTAssertEqual(r.w, 500)
        XCTAssertEqual(r.h, 300)
    }

    func testNegativeWHBecomeZero() {
        let r = clampCropRect(canvasW: 1000, canvasH: 1000, rect: .init(x: 100, y: 100, w: -50, h: -30))
        XCTAssertEqual(r.w, 0)
        XCTAssertEqual(r.h, 0)
    }

    func testPassesThroughInRangeRect() {
        let r = clampCropRect(canvasW: 1000, canvasH: 1000, rect: .init(x: 100, y: 200, w: 300, h: 400))
        XCTAssertEqual(r.x, 100)
        XCTAssertEqual(r.y, 200)
        XCTAssertEqual(r.w, 300)
        XCTAssertEqual(r.h, 400)
    }
}

// MARK: - EditorCanvasLogic

final class EditorCanvasLogicTests: XCTestCase {

    func testDefaultState() {
        let s = defaultEditorCanvasState()
        XCTAssertEqual(s.tool, .none)
        XCTAssertFalse(s.isSaving)
        XCTAssertTrue(s.isPhotoLoading)
    }

    func testIsToolActiveTrue() {
        let s = EditorCanvasState(tool: .crop)
        XCTAssertTrue(isToolActive(s, tool: .crop))
    }

    func testIsToolActiveFalse() {
        let s = EditorCanvasState(tool: .crop)
        XCTAssertFalse(isToolActive(s, tool: .text))
    }

    func testCanSaveTrueWhenIdleAndLoaded() {
        let s = EditorCanvasState(tool: .none, isSaving: false, isPhotoLoading: false)
        XCTAssertTrue(canSave(s))
    }

    func testCanSaveFalseWhenSaving() {
        let s = EditorCanvasState(tool: .none, isSaving: true, isPhotoLoading: false)
        XCTAssertFalse(canSave(s))
    }

    func testCanSaveFalseWhenLoading() {
        let s = EditorCanvasState(tool: .none, isSaving: false, isPhotoLoading: true)
        XCTAssertFalse(canSave(s))
    }

    func testIsInteractingTrueWhenToolNotNone() {
        XCTAssertTrue(isInteracting(EditorCanvasState(tool: .crop)))
    }

    func testIsInteractingFalseWhenToolNone() {
        XCTAssertFalse(isInteracting(EditorCanvasState(tool: .none)))
    }

    func testIsReadyTrueWhenNotLoading() {
        XCTAssertTrue(isReady(EditorCanvasState(tool: .none, isPhotoLoading: false)))
    }

    func testIsReadyFalseWhenLoading() {
        XCTAssertFalse(isReady(defaultEditorCanvasState()))
    }
}

// MARK: - EditorAdjustLogic

final class EditorAdjustLogicDefaultStateTests: XCTestCase {

    func testDefaultAllZeroIncludingSharpness() {
        let s = defaultAdjustPanelState()
        XCTAssertEqual(s.brightness, 0)
        XCTAssertEqual(s.contrast, 0)
        XCTAssertEqual(s.saturation, 0)
        XCTAssertEqual(s.temperature, 0)
        XCTAssertEqual(s.sharpness, 0)
    }
}

final class EditorAdjustLogicBuildAdjustmentsTests: XCTestCase {

    func testAssemblesAll5Fields() {
        let state = EditorAdjustPanelState(brightness: 10, contrast: -5, saturation: 30, temperature: -20, sharpness: 40)
        let adj = buildAdjustments(state)
        XCTAssertEqual(adj.brightness, 10)
        XCTAssertEqual(adj.contrast, -5)
        XCTAssertEqual(adj.saturation, 30)
        XCTAssertEqual(adj.temperature, -20)
        XCTAssertEqual(adj.sharpness, 40)
    }

    func testClampsSharpnessTo100() {
        let adj = buildAdjustments(EditorAdjustPanelState(sharpness: 150))
        XCTAssertEqual(adj.sharpness, 100)
    }

    func testClampsNegativeSharpnessTo0() {
        let adj = buildAdjustments(EditorAdjustPanelState(sharpness: -20))
        XCTAssertEqual(adj.sharpness, 0)
    }

    func testNeutralStateYieldsNeutral() {
        let adj = buildAdjustments(defaultAdjustPanelState())
        XCTAssertEqual(adj.brightness, NEUTRAL_EDITOR_ADJUSTMENTS.brightness)
        XCTAssertEqual(adj.sharpness, NEUTRAL_EDITOR_ADJUSTMENTS.sharpness)
    }
}

final class EditorAdjustLogicIsNeutralTests: XCTestCase {

    func testTrueWhenAll5Zero() {
        XCTAssertTrue(isAdjustNeutral(EditorAdjustPanelState()))
    }

    func testFalseWhenBrightnessNonZero() {
        XCTAssertFalse(isAdjustNeutral(EditorAdjustPanelState(brightness: 1)))
    }

    func testFalseWhenSharpnessNonZero() {
        XCTAssertFalse(isAdjustNeutral(EditorAdjustPanelState(sharpness: 50)))
    }

    func testFalseWhenMultipleNonZero() {
        XCTAssertFalse(isAdjustNeutral(EditorAdjustPanelState(contrast: -1, saturation: 50)))
    }
}

final class EditorAdjustLogicSyncTests: XCTestCase {

    func testReadsAll5Fields() {
        let adj = EditorColorAdjustments(brightness: 15, contrast: -10, saturation: 25, temperature: -5, sharpness: 60)
        let s = syncAdjustPanelState(adj)
        XCTAssertEqual(s.brightness, 15)
        XCTAssertEqual(s.contrast, -10)
        XCTAssertEqual(s.saturation, 25)
        XCTAssertEqual(s.temperature, -5)
        XCTAssertEqual(s.sharpness, 60)
    }
}

final class EditorAdjustLogicSliderGestureTests: XCTestCase {

    func testBeginPhase() {
        let d = resolveSliderGesture(.begin)
        XCTAssertTrue(d.shouldBeginGesture)
        XCTAssertFalse(d.shouldEndGesture)
    }

    func testMovingPhase() {
        let d = resolveSliderGesture(.moving)
        XCTAssertFalse(d.shouldBeginGesture)
        XCTAssertFalse(d.shouldEndGesture)
    }

    func testEndPhase() {
        let d = resolveSliderGesture(.end)
        XCTAssertFalse(d.shouldBeginGesture)
        XCTAssertTrue(d.shouldEndGesture)
    }

    func testClickPhase() {
        let d = resolveSliderGesture(.click)
        XCTAssertFalse(d.shouldBeginGesture)
        XCTAssertTrue(d.shouldEndGesture)
    }
}

final class EditorAdjustLogicMapSliderModeTests: XCTestCase {

    func testMapsKnownValues() {
        XCTAssertEqual(mapSliderModeToPhase(0), .begin)
        XCTAssertEqual(mapSliderModeToPhase(1), .moving)
        XCTAssertEqual(mapSliderModeToPhase(2), .end)
        XCTAssertEqual(mapSliderModeToPhase(3), .click)
    }

    func testFallsBackToMovingForUnknown() {
        XCTAssertEqual(mapSliderModeToPhase(99), .moving)
        XCTAssertEqual(mapSliderModeToPhase(-1), .moving)
    }
}

final class EditorAdjustLogicSharpnessApplyTests: XCTestCase {

    func testReturnsFalseForBeginPhase() {
        XCTAssertFalse(resolveSharpnessApply(prevStrength: 0, nextStrength: 50, phase: .begin).shouldApply)
    }

    func testReturnsFalseForMovingPhase() {
        XCTAssertFalse(resolveSharpnessApply(prevStrength: 0, nextStrength: 50, phase: .moving).shouldApply)
    }

    func testReturnsTrueForEndWhenChanged() {
        let d = resolveSharpnessApply(prevStrength: 0, nextStrength: 50, phase: .end)
        XCTAssertTrue(d.shouldApply)
        XCTAssertEqual(d.strength, 50)
    }

    func testReturnsTrueForClickWhenChanged() {
        let d = resolveSharpnessApply(prevStrength: 0, nextStrength: 30, phase: .click)
        XCTAssertTrue(d.shouldApply)
        XCTAssertEqual(d.strength, 30)
    }

    func testReturnsFalseForEndWhenUnchanged() {
        XCTAssertFalse(resolveSharpnessApply(prevStrength: 50, nextStrength: 50, phase: .end).shouldApply)
    }

    func testReturnsTrueWhenStrengthGoesToZero() {
        let d = resolveSharpnessApply(prevStrength: 50, nextStrength: 0, phase: .end)
        XCTAssertTrue(d.shouldApply)
        XCTAssertEqual(d.strength, 0)
    }

    func testClampsNextStrengthTo100() {
        let d = resolveSharpnessApply(prevStrength: 0, nextStrength: 150, phase: .end)
        XCTAssertTrue(d.shouldApply)
        XCTAssertEqual(d.strength, 100)
    }

    func testClampsNegativeNextTo0() {
        let d = resolveSharpnessApply(prevStrength: 50, nextStrength: -10, phase: .end)
        XCTAssertTrue(d.shouldApply)
        XCTAssertEqual(d.strength, 0)
    }

    func testComparesClampedPrevAndNext() {
        // prev=150→clamp=100, next=100→clamp=100 → 相同 → shouldApply=false
        XCTAssertFalse(resolveSharpnessApply(prevStrength: 150, nextStrength: 100, phase: .end).shouldApply)
    }
}

// MARK: - EditorCutoutLogic

final class EditorCutoutLogicCanStartTests: XCTestCase {

    func testAllowsFromIdle() {
        let d = canStartCutout(.idle)
        XCTAssertTrue(d.canStart)
        XCTAssertEqual(d.rejectReason, "")
    }

    func testAllowsFromApplied() {
        XCTAssertTrue(canStartCutout(.applied).canStart)
    }

    func testAllowsFromError() {
        XCTAssertTrue(canStartCutout(.error).canStart)
    }

    func testBlocksDuringProcessing() {
        let d = canStartCutout(.processing)
        XCTAssertFalse(d.canStart)
        XCTAssertEqual(d.rejectReason, "正在识别主体，请稍候")
    }
}

final class EditorCutoutLogicGuardTests: XCTestCase {

    private let validGuard = EditorCutoutGuard(pageActive: true, photoGeneration: 1, cutoutGeneration: 3,
                                               targetLayerId: "photo_001", layerExists: true)

    func testPassesWhenAllMatch() {
        XCTAssertTrue(isCutoutResultValid(validGuard, expectedPhotoGeneration: 1, expectedCutoutGeneration: 3))
    }

    func testFailsWhenPageInactive() {
        let g = EditorCutoutGuard(pageActive: false, photoGeneration: 1, cutoutGeneration: 3,
                                  targetLayerId: "photo_001", layerExists: true)
        XCTAssertFalse(isCutoutResultValid(g, expectedPhotoGeneration: 1, expectedCutoutGeneration: 3))
    }

    func testFailsWhenPhotoGenerationChanged() {
        XCTAssertFalse(isCutoutResultValid(validGuard, expectedPhotoGeneration: 2, expectedCutoutGeneration: 3))
    }

    func testFailsWhenCutoutGenerationChanged() {
        XCTAssertFalse(isCutoutResultValid(validGuard, expectedPhotoGeneration: 1, expectedCutoutGeneration: 4))
    }

    func testFailsWhenLayerGone() {
        let g = EditorCutoutGuard(pageActive: true, photoGeneration: 1, cutoutGeneration: 3,
                                  targetLayerId: "photo_001", layerExists: false)
        XCTAssertFalse(isCutoutResultValid(g, expectedPhotoGeneration: 1, expectedCutoutGeneration: 3))
    }
}

final class EditorCutoutLogicResolveResultTests: XCTestCase {

    func testAppliedForAISuccess() {
        let d = resolveCutoutResult(isValid: true, resultNull: false, isFallback: false)
        XCTAssertTrue(d.isValid)
        XCTAssertFalse(d.isFallback)
        XCTAssertEqual(d.nextPhase, .applied)
        XCTAssertEqual(d.statusText, "已移除背景，可撤销")
    }

    func testAppliedWithFallbackForDegraded() {
        let d = resolveCutoutResult(isValid: true, resultNull: false, isFallback: true)
        XCTAssertTrue(d.isValid)
        XCTAssertTrue(d.isFallback)
        XCTAssertEqual(d.nextPhase, .applied)
    }

    func testErrorWhenResultNull() {
        let d = resolveCutoutResult(isValid: true, resultNull: true, isFallback: false)
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.nextPhase, .error)
        XCTAssertEqual(d.statusText, "未能识别主体，请重试或更换照片")
    }

    func testStaleWhenGuardFails() {
        let d = resolveCutoutResult(isValid: false, resultNull: false, isFallback: false)
        XCTAssertFalse(d.isValid)
        XCTAssertEqual(d.statusText, "")
    }
}

final class EditorCutoutLogicStatusTextTests: XCTestCase {

    func testIdleText() {
        XCTAssertEqual(cutoutStatusText(.idle), "自动识别主体并移除背景")
    }

    func testProcessingText() {
        XCTAssertEqual(cutoutStatusText(.processing), "正在识别主体…")
    }

    func testAppliedText() {
        XCTAssertEqual(cutoutStatusText(.applied), "已移除背景，可撤销")
    }

    func testErrorText() {
        XCTAssertEqual(cutoutStatusText(.error), "识别失败，可重试")
    }
}

final class EditorCutoutLogicRetryTests: XCTestCase {

    func testAllowsRetryFromIdle() {
        XCTAssertTrue(canRetryCutout(.idle))
    }

    func testAllowsRetryFromApplied() {
        XCTAssertTrue(canRetryCutout(.applied))
    }

    func testAllowsRetryFromError() {
        XCTAssertTrue(canRetryCutout(.error))
    }

    func testBlocksRetryDuringProcessing() {
        XCTAssertFalse(canRetryCutout(.processing))
    }
}

// MARK: - EditorSaveLogic

final class EditorSaveLogicCanStartTests: XCTestCase {

    private func snap(_ isSaving: Bool = false, _ isLoading: Bool = false, _ loaded: Bool = true, _ unsaved: Bool = false) -> EditorSaveSnapshot {
        EditorSaveSnapshot(isSaving: isSaving, isPhotoLoading: isLoading, photoLoaded: loaded, hasUnsavedChanges: unsaved)
    }

    func testAllowsWhenLoadedAndIdle() {
        XCTAssertTrue(canStartSave(snap()))
    }

    func testBlocksWhenSaving() {
        XCTAssertFalse(canStartSave(snap(true)))
    }

    func testBlocksWhenLoading() {
        XCTAssertFalse(canStartSave(snap(false, true, false)))
    }

    func testBlocksWhenNotLoaded() {
        XCTAssertFalse(canStartSave(snap(false, false, false)))
    }

    func testBlocksWhenBothSavingAndLoading() {
        XCTAssertFalse(canStartSave(snap(true, true, true)))
    }
}

final class EditorSaveLogicBackActionTests: XCTestCase {

    private func snap(_ isSaving: Bool, _ unsaved: Bool) -> EditorSaveSnapshot {
        EditorSaveSnapshot(isSaving: isSaving, isPhotoLoading: false, photoLoaded: true, hasUnsavedChanges: unsaved)
    }

    func testImmediateBackWhenNoUnsaved() {
        XCTAssertEqual(resolveBackAction(snap(false, false)), .immediateBack)
    }

    func testConfirmWhenUnsaved() {
        XCTAssertEqual(resolveBackAction(snap(false, true)), .confirmSaveFirst)
    }

    func testBlockWhenSavingRegardlessOfChanges() {
        XCTAssertEqual(resolveBackAction(snap(true, true)), .blockWhileSaving)
    }

    func testBlockTakesPriorityOverConfirm() {
        XCTAssertEqual(resolveBackAction(snap(true, false)), .blockWhileSaving)
    }

    func testImmediateBackWhenNoChangesEvenIfNotLoaded() {
        let s = EditorSaveSnapshot(isSaving: false, isPhotoLoading: false, photoLoaded: false, hasUnsavedChanges: false)
        XCTAssertEqual(resolveBackAction(s), .immediateBack)
    }
}

final class EditorSaveLogicFileNameTests: XCTestCase {

    func testDefaultProducesJpg() {
        XCTAssertEqual(resolveSaveFileNameHint(timestamp: 1700000000000), "MiLens_Edit_1700000000000.jpg")
    }

    func testCustomExtension() {
        XCTAssertEqual(resolveSaveFileNameHint(timestamp: 123, ext: "png"), "MiLens_Edit_123.png")
    }

    func testFallsBackToJpgWhenEmpty() {
        XCTAssertEqual(resolveSaveFileNameHint(timestamp: 456, ext: ""), "MiLens_Edit_456.jpg")
    }

    func testExtensionConstantIsJpg() {
        XCTAssertEqual(EDIT_EXPORT_EXTENSION, "jpg")
    }
}

final class EditorSaveLogicFormatTests: XCTestCase {

    func testPngWhenHasAlpha() {
        let d = resolveSaveFormat(hasAlpha: true)
        XCTAssertEqual(d.format, "image/png")
        XCTAssertEqual(d.extension_, "png")
    }

    func testJpegWhenNoAlpha() {
        let d = resolveSaveFormat(hasAlpha: false)
        XCTAssertEqual(d.format, "image/jpeg")
        XCTAssertEqual(d.extension_, "jpg")
    }

    func testPngQuality100() {
        XCTAssertEqual(resolveSaveFormat(hasAlpha: true).quality, 100)
    }

    func testJpegQuality92() {
        XCTAssertEqual(resolveSaveFormat(hasAlpha: false).quality, 92)
    }

    func testFileNameWithDecisionPng() {
        let decision = resolveSaveFormat(hasAlpha: true)
        let name = resolveSaveFileNameHint(timestamp: 1700000000000, decision: decision)
        XCTAssertEqual(name, "MiLens_Edit_1700000000000.png")
    }

    func testFileNameWithDecisionJpg() {
        let decision = resolveSaveFormat(hasAlpha: false)
        let name = resolveSaveFileNameHint(timestamp: 999, decision: decision)
        XCTAssertEqual(name, "MiLens_Edit_999.jpg")
    }
}

// MARK: - EditorTextToolLogic

final class EditorTextToolLogicCanAddTests: XCTestCase {

    func testAllowsNonEmpty() {
        XCTAssertTrue(canAddTextLayer("hello"))
    }

    func testAllowsWithSurroundingSpaces() {
        XCTAssertTrue(canAddTextLayer("  hello  "))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(canAddTextLayer(""))
    }

    func testRejectsWhitespaceOnly() {
        XCTAssertFalse(canAddTextLayer("   "))
    }
}

final class EditorTextToolLogicEditPanelTests: XCTestCase {

    func testShowsWhenTextLayerSelectedNotInAddMode() {
        XCTAssertTrue(shouldShowTextLayerEditPanel(activeLayerType: "text", currentTool: .crop))
        XCTAssertTrue(shouldShowTextLayerEditPanel(activeLayerType: "text", currentTool: .none))
    }

    func testHidesWhenInTextAddMode() {
        XCTAssertFalse(shouldShowTextLayerEditPanel(activeLayerType: "text", currentTool: .text))
    }

    func testHidesWhenNoActiveLayer() {
        XCTAssertFalse(shouldShowTextLayerEditPanel(activeLayerType: "", currentTool: .none))
    }

    func testHidesWhenNotTextLayer() {
        XCTAssertFalse(shouldShowTextLayerEditPanel(activeLayerType: "photo", currentTool: .none))
    }
}

final class EditorTextToolLogicResolveEditTests: XCTestCase {

    func testAssemblesFontSizeAndColor() {
        let edit = resolveTextLayerEdit(fontSize: 24, color: "#FF0000")
        XCTAssertEqual(edit.fontSize, 24)
        XCTAssertEqual(edit.color, "#FF0000")
    }

    func testHandlesZeroFontSize() {
        XCTAssertEqual(resolveTextLayerEdit(fontSize: 0, color: "#000000").fontSize, 0)
    }
}

final class EditorTextToolLogicIsActiveTests: XCTestCase {

    func testTrueForTextMode() {
        XCTAssertTrue(isTextToolActive(.text))
    }

    func testFalseForOtherModes() {
        XCTAssertFalse(isTextToolActive(.crop))
        XCTAssertFalse(isTextToolActive(.none))
        XCTAssertFalse(isTextToolActive(.frame))
    }
}

final class EditorTextToolLogicIsEditableTests: XCTestCase {

    func testTrueForTextLayer() {
        XCTAssertTrue(isTextLayerEditable("text"))
    }

    func testFalseForEmpty() {
        XCTAssertFalse(isTextLayerEditable(""))
    }

    func testFalseForNonText() {
        XCTAssertFalse(isTextLayerEditable("photo"))
        XCTAssertFalse(isTextLayerEditable("sticker"))
    }

    func testTextLayerTypeConstant() {
        XCTAssertEqual(EDITOR_TEXT_LAYER_TYPE, "text")
    }
}
