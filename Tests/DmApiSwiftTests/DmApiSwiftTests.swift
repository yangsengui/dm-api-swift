import XCTest
@testable import DmApiSwift

final class DmApiSwiftTests: XCTestCase {
    func testModuleSymbolIsAccessible() {
        XCTAssertNotNil(DmApi.self)
    }
}
