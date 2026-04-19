import Testing
import Foundation
@testable import swift_app

@Suite
struct BalanceResponseParserTests {
    @Test func testParseAlchemyETHBalance() throws {
        let payload = #"{"jsonrpc":"2.0","id":1,"result":"0x38d7ea4c68000"}"#.data(using: .utf8)!
        let decimal = try BalanceResponseParser.parseAlchemyETHBalance(from: payload)
    #expect(decimal == Decimal(string: "0.001")!, "Expected 0.001 ETH")
    }
    
    @Test func testParseAlchemyERC20Balance() throws {
    let payload = #"{"jsonrpc":"2.0","id":1,"result":"0x1bc16d674ec80000"}"#.data(using: .utf8)!
        let decimal = try BalanceResponseParser.parseAlchemyERC20Balance(from: payload, decimals: 18)
    #expect(decimal == Decimal(string: "2")!)
    }
    
    @Test func testParseBlockchairETHBalance() throws {
        let payload = #"{"data":{"0xabc":{"address":{"balance":"100000000000000000"}}}}"#.data(using: .utf8)!
        let decimal = try BalanceResponseParser.parseBlockchairETHBalance(from: payload, address: "0xABC")
    #expect(decimal == Decimal(string: "0.1")!)
    }
    
    @Test func testParseBlockchairERC20Balance() throws {
        let payload = #"{"data":{"0xabc":{"layer_2":{"erc_20":[{"token_address":"0xToken","balance":"2500000"}]}}}}"#.data(using: .utf8)!
        let decimal = try BalanceResponseParser.parseBlockchairERC20Balance(from: payload, address: "0xABC", contractAddress: "0xTOKEN", decimals: 6)
    #expect(decimal == Decimal(string: "2.5")!)
    }
    
    @Test func testParseXRPLBalance() throws {
        let payload = #"{"result":{"account_data":{"Balance":"1234567"}}}"#.data(using: .utf8)!
        let decimal = try BalanceResponseParser.parseXRPLBalance(from: payload)
    #expect(decimal == Decimal(string: "1.234567")!)
    }
}
