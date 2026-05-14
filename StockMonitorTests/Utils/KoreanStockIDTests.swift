import XCTest
@testable import Stockbar

final class KoreanStockIDTests: XCTestCase {

    // MARK: - isKoreanID

    func test_isKoreanID_kospi() {
        XCTAssertTrue(KoreanStockID.isKorean("kr_005930.ks"))
    }

    func test_isKoreanID_kosdaq() {
        XCTAssertTrue(KoreanStockID.isKorean("kr_293490.kq"))
    }

    func test_isKoreanID_rejects_other_markets() {
        XCTAssertFalse(KoreanStockID.isKorean("sh600000"))
        XCTAssertFalse(KoreanStockID.isKorean("hk00700"))
        XCTAssertFalse(KoreanStockID.isKorean("usr_aapl"))
    }

    func test_isKoreanID_rejects_empty_and_garbage() {
        XCTAssertFalse(KoreanStockID.isKorean(""))
        XCTAssertFalse(KoreanStockID.isKorean("kr"))
        XCTAssertFalse(KoreanStockID.isKorean("kr_"))
    }

    // MARK: - krIDToYahooSymbol

    func test_krIDToYahooSymbol_kospi() {
        XCTAssertEqual(KoreanStockID.toYahooSymbol("kr_005930.ks"), "005930.KS")
    }

    func test_krIDToYahooSymbol_kosdaq() {
        XCTAssertEqual(KoreanStockID.toYahooSymbol("kr_293490.kq"), "293490.KQ")
    }

    func test_krIDToYahooSymbol_handles_mixed_case_input() {
        XCTAssertEqual(KoreanStockID.toYahooSymbol("kr_005930.KS"), "005930.KS")
        XCTAssertEqual(KoreanStockID.toYahooSymbol("KR_005930.ks"), "005930.KS")
    }

    func test_krIDToYahooSymbol_rejects_non_korean() {
        XCTAssertNil(KoreanStockID.toYahooSymbol("sh600000"))
        XCTAssertNil(KoreanStockID.toYahooSymbol(""))
    }

    // MARK: - yahooSymbolToKrID

    func test_yahooSymbolToKrID_kospi() {
        XCTAssertEqual(KoreanStockID.fromYahooSymbol("005930.KS"), "kr_005930.ks")
    }

    func test_yahooSymbolToKrID_kosdaq() {
        XCTAssertEqual(KoreanStockID.fromYahooSymbol("293490.KQ"), "kr_293490.kq")
    }

    func test_yahooSymbolToKrID_handles_lowercase_input() {
        XCTAssertEqual(KoreanStockID.fromYahooSymbol("005930.ks"), "kr_005930.ks")
    }
}
