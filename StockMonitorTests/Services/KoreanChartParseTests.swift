import XCTest
@testable import Stockbar

final class KoreanChartParseTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture \(name).json missing — re-run capture step")
        }
        return try Data(contentsOf: url)
    }

    func test_parseKoreanChartPoints_returns_points_and_preclose() throws {
        let data = try loadFixture("chart_005930_ks")
        let result = try XCTUnwrap(ChartService.parseKoreanChartPoints(data))
        XCTAssertGreaterThan(result.preClose, 0)
        XCTAssertFalse(result.points.isEmpty)
        // x 轴基准：KST 09:00 = index 0；最大 index 389（15:29）
        for p in result.points {
            XCTAssertGreaterThanOrEqual(p.id, 0)
            XCTAssertLessThanOrEqual(p.id, 389)
            XCTAssertGreaterThan(p.price, 0)
        }
    }

    func test_parseKoreanChartPoints_invalid_data() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(ChartService.parseKoreanChartPoints(data))
    }

    func test_parseKoreanChartPoints_empty_meta() throws {
        let data = try loadFixture("quote_empty")
        XCTAssertNil(ChartService.parseKoreanChartPoints(data))
    }
}
