import Foundation

struct BalanceResponseParser {
    static func parseAlchemyETHBalance(from data: Data) throws -> Decimal {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let result = dictionary["result"] as? String else {
            throw BalanceFetchError.invalidPayload
        }
        let wei = decimalFromHex(result)
        return decimalDividingByPowerOfTen(wei, exponent: 18)
    }
    
    static func parseAlchemyERC20Balance(from data: Data, decimals: Int) throws -> Decimal {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let result = dictionary["result"] as? String else {
            throw BalanceFetchError.invalidPayload
        }
        let balance = decimalFromHex(result)
        return decimalDividingByPowerOfTen(balance, exponent: decimals)
    }
    
    static func parseBlockchairETHBalance(from data: Data, address: String) throws -> Decimal {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let dataDict = dictionary["data"] as? [String: Any],
              let addressData = dataDict[address.lowercased()] as? [String: Any],
              let addressInfo = addressData["address"] as? [String: Any],
              let balanceString = addressInfo["balance"] as? String,
              let balanceDecimal = Decimal(string: balanceString) else {
            throw BalanceFetchError.invalidPayload
        }
        return decimalDividingByPowerOfTen(balanceDecimal, exponent: 18)
    }
    
    static func parseBlockchairERC20Balance(from data: Data, address: String, contractAddress: String, decimals: Int) throws -> Decimal {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let dataDict = dictionary["data"] as? [String: Any],
              let addressData = dataDict[address.lowercased()] as? [String: Any],
              let layer2 = addressData["layer_2"] as? [String: Any],
              let erc20 = layer2["erc_20"] as? [[String: Any]] else {
            return .zero
        }
        
        for token in erc20 {
            if let tokenAddress = token["token_address"] as? String,
               tokenAddress.lowercased() == contractAddress.lowercased(),
               let balanceString = token["balance"] as? String,
               let balanceDecimal = Decimal(string: balanceString) {
                return decimalDividingByPowerOfTen(balanceDecimal, exponent: decimals)
            }
        }
        return .zero
    }
    
    static func parseXRPLBalance(from data: Data) throws -> Decimal {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let result = dictionary["result"] as? [String: Any],
              let accountData = result["account_data"] as? [String: Any],
              let balanceString = accountData["Balance"] as? String,
              let drops = Decimal(string: balanceString) else {
            throw BalanceFetchError.invalidPayload
        }
        return decimalDividingByPowerOfTen(drops, exponent: 6)
    }
    
    // MARK: - Helpers
    private static func decimalFromHex(_ hexString: String) -> Decimal {
        let sanitized = hexString.lowercased().hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard !sanitized.isEmpty else { return Decimal.zero }
        var result = Decimal.zero
        for character in sanitized {
            result *= 16
            if let digit = Int(String(character), radix: 16) {
                result += Decimal(digit)
            } else {
                return Decimal.zero
            }
        }
        return result
    }
    
    private static func decimalDividingByPowerOfTen(_ value: Decimal, exponent: Int) -> Decimal {
        var input = value
        var result = Decimal()
        let clampedExponent = Int16(clamping: exponent)
        NSDecimalMultiplyByPowerOf10(&result, &input, -clampedExponent, .plain)
        return result
    }
}
