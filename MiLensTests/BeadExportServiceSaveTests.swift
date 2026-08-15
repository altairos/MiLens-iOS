//  BeadExportServiceSaveTests —— 保存到相册协议收敛测试（audit-6 P2-1 / R3+R7）。
//  BeadExportService.saveToPhotoLibrary 必须经 PhotoLibraryAccess 协议透传：
//  成功记录、底层失败、权限拒绝三分支（MockPhotoLibraryAccess 失败注入）。
//  真实 IOSPhotoLibraryAccess.save 依赖系统授权弹窗与照片库，属真机验证项（P2-3）。

import XCTest
@testable import MiLens

final class BeadExportServiceSaveTests: XCTestCase {

    private func makeService(_ mock: MockPhotoLibraryAccess) -> BeadExportService {
        BeadExportService(photoLibrary: mock)
    }

    /// 成功分支：数据与类型透传到协议实现（photo 资源）。
    func testSaveToPhotoLibraryPersistsDataThroughProtocol() async throws {
        let mock = MockPhotoLibraryAccess()
        let png = Data([0x89, 0x50, 0x4E, 0x47])  // PNG 魔数前缀

        try await makeService(mock).saveToPhotoLibrary(pngData: png)

        XCTAssertEqual(mock.saveCalls.count, 1)
        XCTAssertEqual(mock.saveCalls.first?.data, png)
        XCTAssertEqual(mock.saveCalls.first?.kind, .photo)
    }

    /// 失败分支：协议实现抛 saveFailed 时原样上抛，且不记录成功调用。
    func testSaveToPhotoLibraryPropagatesSaveFailure() async {
        let mock = MockPhotoLibraryAccess()
        mock.saveError = PhotoLibraryError.saveFailed

        do {
            try await makeService(mock).saveToPhotoLibrary(pngData: Data([0x00]))
            XCTFail("saveFailed 应上抛")
        } catch let error as PhotoLibraryError {
            XCTAssertEqual(error, .saveFailed)
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
        XCTAssertTrue(mock.saveCalls.isEmpty, "失败路径不应记录成功调用")
    }

    /// 权限拒绝分支：savePermissionDenied 上抛（业务层据此提示去系统设置开启）。
    func testSaveToPhotoLibraryPropagatesPermissionDenied() async {
        let mock = MockPhotoLibraryAccess()
        mock.saveError = PhotoLibraryError.savePermissionDenied

        do {
            try await makeService(mock).saveToPhotoLibrary(pngData: Data([0x00]))
            XCTFail("savePermissionDenied 应上抛")
        } catch let error as PhotoLibraryError {
            XCTAssertEqual(error, .savePermissionDenied)
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    /// 连续保存多次均被记录（红包封面批量导出场景的透传正确性）。
    func testSaveToPhotoLibraryRecordsRepeatedSaves() async throws {
        let mock = MockPhotoLibraryAccess()
        let service = makeService(mock)

        try await service.saveToPhotoLibrary(pngData: Data([0x01]))
        try await service.saveToPhotoLibrary(pngData: Data([0x02]))

        XCTAssertEqual(mock.saveCalls.map { $0.data }, [Data([0x01]), Data([0x02])])
        XCTAssertEqual(mock.saveCalls.map { $0.kind }, [.photo, .photo])
    }
}
