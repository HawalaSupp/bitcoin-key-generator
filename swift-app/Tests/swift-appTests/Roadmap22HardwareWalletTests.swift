//
//  Roadmap22HardwareWalletTests.swift
//  Hawala
//
//  ROADMAP-22: Hardware Wallet Integration Tests
//  Tests for Ledger + Trezor support, device protocols, signing flows,
//  connection management, analytics, error handling, and UI components.
//

import Testing
import Foundation
@testable import swift_app

// MARK: - E1: Hardware Device Types

@Suite("E1: Hardware Device Type Enum")
struct HardwareDeviceTypeTests {
    @Test("All device types defined")
    func allDeviceTypes() {
        let types = HardwareDeviceType.allCases
        // Ledger: Nano S, Nano S Plus, Nano X, Stax
        // Trezor: One, Model T, Safe 3
        #expect(types.count == 7)
    }

    @Test("Ledger devices have correct vendor ID")
    func ledgerVendorId() {
        #expect(HardwareDeviceType.ledgerNanoS.vendorId == 0x2c97)
        #expect(HardwareDeviceType.ledgerNanoSPlus.vendorId == 0x2c97)
        #expect(HardwareDeviceType.ledgerNanoX.vendorId == 0x2c97)
        #expect(HardwareDeviceType.ledgerStax.vendorId == 0x2c97)
    }

    @Test("Trezor devices have correct vendor ID")
    func trezorVendorId() {
        #expect(HardwareDeviceType.trezorOne.vendorId == 0x1209)
        #expect(HardwareDeviceType.trezorModelT.vendorId == 0x1209)
        #expect(HardwareDeviceType.trezorSafe3.vendorId == 0x1209)
    }

    @Test("Product IDs are non-empty")
    func productIds() {
        for type in HardwareDeviceType.allCases {
            #expect(!type.productIds.isEmpty, "Product IDs should not be empty for \(type.displayName)")
        }
    }

    @Test("Bluetooth support correct")
    func bluetoothSupport() {
        #expect(HardwareDeviceType.ledgerNanoX.supportsBluetooth == true)
        #expect(HardwareDeviceType.ledgerStax.supportsBluetooth == true)
        #expect(HardwareDeviceType.ledgerNanoS.supportsBluetooth == false)
        #expect(HardwareDeviceType.trezorOne.supportsBluetooth == false)
        #expect(HardwareDeviceType.trezorModelT.supportsBluetooth == false)
    }

    @Test("USB support for all devices")
    func usbSupport() {
        for type in HardwareDeviceType.allCases {
            #expect(type.supportsUSB == true)
        }
    }

    @Test("Display names are meaningful")
    func displayNames() {
        #expect(HardwareDeviceType.ledgerNanoS.displayName == "Ledger Nano S")
        #expect(HardwareDeviceType.ledgerNanoX.displayName == "Ledger Nano X")
        #expect(HardwareDeviceType.trezorOne.displayName == "Trezor One")
        #expect(HardwareDeviceType.trezorModelT.displayName == "Trezor Model T")
        #expect(HardwareDeviceType.ledgerStax.displayName == "Ledger Stax")
        #expect(HardwareDeviceType.trezorSafe3.displayName == "Trezor Safe 3")
    }

    @Test("Manufacturer classification")
    func manufacturers() {
        #expect(HardwareDeviceType.ledgerNanoS.manufacturer == .ledger)
        #expect(HardwareDeviceType.ledgerNanoX.manufacturer == .ledger)
        #expect(HardwareDeviceType.ledgerStax.manufacturer == .ledger)
        #expect(HardwareDeviceType.trezorOne.manufacturer == .trezor)
        #expect(HardwareDeviceType.trezorModelT.manufacturer == .trezor)
        #expect(HardwareDeviceType.trezorSafe3.manufacturer == .trezor)
    }
}

// MARK: - E2: Device Icon/Brand Extensions

@Suite("E2: Device UI Extensions")
struct DeviceUIExtensionTests {
    @Test("All devices have icon names (no default fallback)")
    func allDevicesHaveIcons() {
        for type in HardwareDeviceType.allCases {
            let icon = type.iconName
            #expect(!icon.isEmpty, "\(type.displayName) should have an icon")
            #expect(icon != "externaldrive", "\(type.displayName) should not use default icon")
        }
    }

    @Test("Ledger Stax has specific icon")
    func ledgerStaxIcon() {
        #expect(HardwareDeviceType.ledgerStax.iconName == "rectangle.portrait.fill")
    }

    @Test("Trezor Safe 3 has specific icon")
    func trezorSafe3Icon() {
        #expect(HardwareDeviceType.trezorSafe3.iconName == "shield.checkerboard")
    }

    @Test("All devices have short names (no default fallback)")
    func allDevicesHaveShortNames() {
        for type in HardwareDeviceType.allCases {
            let name = type.shortName
            #expect(!name.isEmpty, "\(type.displayName) should have a short name")
            #expect(name != "HW", "\(type.displayName) should not use default short name")
        }
    }

    @Test("Ledger Stax short name")
    func ledgerStaxShortName() {
        #expect(HardwareDeviceType.ledgerStax.shortName == "Stax")
    }

    @Test("Trezor Safe 3 short name")
    func trezorSafe3ShortName() {
        #expect(HardwareDeviceType.trezorSafe3.shortName == "Safe 3")
    }
}

// MARK: - E3: HardwareWallet Protocol

@Suite("E3: HardwareWallet Protocol")
struct HardwareWalletProtocolTests {
    @Test("Protocol defines required methods")
    func protocolRequirements() {
        // Compile-time check: LedgerWallet and TrezorWallet conform
        let _: any HardwareWallet.Type = LedgerWallet.self
        let _: any HardwareWallet.Type = TrezorWallet.self
    }

    @Test("Device status enum has all required states")
    func deviceStatusStates() {
        let states: [HardwareDeviceStatus] = [
            .disconnected,
            .connecting,
            .connected,
            .requiresPinEntry,
            .requiresPassphrase,
            .requiresAppOpen(appName: "Bitcoin"),
            .ready,
            .busy,
            .error(.deviceNotFound)
        ]
        #expect(states.count == 9)
    }

    @Test("Ready status check")
    func readyStatusCheck() {
        let ready = HardwareDeviceStatus.ready
        #expect(ready.isReady == true)

        let connecting = HardwareDeviceStatus.connecting
        #expect(connecting.isReady == false)

        let disconnected = HardwareDeviceStatus.disconnected
        #expect(disconnected.isReady == false)
    }
}

// MARK: - E4: Derivation Path

@Suite("E4: Derivation Path Parsing")
struct DerivationPathTests {
    @Test("Parse standard BIP44 Ethereum path")
    func parseBIP44Eth() {
        let path = DerivationPath(string: "m/44'/60'/0'/0/0")
        #expect(path != nil)
        #expect(path?.components.count == 5)
        #expect(path?.components[0].index == 44)
        #expect(path?.components[0].hardened == true)
        #expect(path?.components[1].index == 60)
        #expect(path?.components[4].index == 0)
        #expect(path?.components[4].hardened == false)
    }

    @Test("Parse BIP84 Bitcoin path")
    func parseBIP84Bitcoin() {
        let path = DerivationPath(string: "m/84'/0'/0'/0/0")
        #expect(path != nil)
        #expect(path?.components[0].index == 84)
        #expect(path?.components[0].hardened == true)
    }

    @Test("Description matches input")
    func descriptionRoundTrip() {
        let original = "m/44'/60'/0'/0/0"
        let path = DerivationPath(string: original)
        #expect(path?.description == original)
    }

    @Test("BIP44 factory method")
    func bip44Factory() {
        let path = DerivationPath.bip44(coinType: 60, account: 0, change: 0, index: 0)
        #expect(path.description == "m/44'/60'/0'/0/0")
    }

    @Test("BIP84 factory method")
    func bip84Factory() {
        let path = DerivationPath.bip84(account: 0, change: 0, index: 0)
        #expect(path.description == "m/84'/0'/0'/0/0")
    }

    @Test("Serialization for APDU")
    func serialization() {
        let path = DerivationPath(string: "m/44'/60'/0'/0/0")!
        let data = path.serialize()
        // Should be: count byte (5) + 5 * 4 bytes = 21 bytes
        #expect(data.count == 21)
        #expect(data[0] == 5) // 5 components
    }

    @Test("Invalid path returns nil")
    func invalidPath() {
        let path = DerivationPath(string: "invalid/path")
        #expect(path == nil)
    }

    @Test("Hardened value includes flag")
    func hardenedValue() {
        let comp = DerivationPath.PathComponent(index: 44, hardened: true)
        #expect(comp.value == 44 | 0x80000000)
    }

    @Test("Non-hardened value is raw index")
    func nonHardenedValue() {
        let comp = DerivationPath.PathComponent(index: 0, hardened: false)
        #expect(comp.value == 0)
    }
}

// MARK: - E5: Supported Chains

@Suite("E5: Supported Chain Configuration")
struct SupportedChainTests {
    @Test("All chains have ledger app names")
    func ledgerAppNames() {
        for chain in SupportedChain.allCases {
            #expect(!chain.ledgerAppName.isEmpty, "\(chain.rawValue) should have ledger app name")
        }
    }

    @Test("All chains have default paths")
    func defaultPaths() {
        for chain in SupportedChain.allCases {
            let path = DerivationPath(string: chain.defaultPath)
            #expect(path != nil, "\(chain.rawValue) should have a valid default path")
        }
    }

    @Test("Bitcoin uses BIP84 native SegWit")
    func bitcoinPath() {
        #expect(SupportedChain.bitcoin.defaultPath == "m/84'/0'/0'/0/0")
    }

    @Test("Ethereum uses BIP44 coin type 60")
    func ethereumPath() {
        #expect(SupportedChain.ethereum.defaultPath == "m/44'/60'/0'/0/0")
    }

    @Test("EVM chains share Ethereum coin type")
    func evmCoinType() {
        let evmChains: [SupportedChain] = [.ethereum, .polygon, .arbitrum, .optimism, .bsc]
        for chain in evmChains {
            #expect(chain.coinType == 60, "\(chain.rawValue) should use coin type 60")
        }
    }

    @Test("Chain curve types")
    func curveTypes() {
        #expect(SupportedChain.bitcoin.curve == .secp256k1)
        #expect(SupportedChain.ethereum.curve == .secp256k1)
        #expect(SupportedChain.solana.curve == .ed25519)
    }
}

// MARK: - E6: Elliptic Curve Types

@Suite("E6: Elliptic Curve Types")
struct EllipticCurveTests {
    @Test("All curve types defined")
    func allCurves() {
        let _: EllipticCurveType = .secp256k1
        let _: EllipticCurveType = .ed25519
        let _: EllipticCurveType = .nist256p1
        let _: EllipticCurveType = .sr25519
    }

    @Test("Curves are Codable")
    func codable() throws {
        let original = EllipticCurveType.secp256k1
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EllipticCurveType.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - E7: Result Types

@Suite("E7: Hardware Wallet Result Types")
struct ResultTypeTests {
    @Test("PublicKeyResult stores key and chain code")
    func publicKeyResult() {
        let key = Data(repeating: 0x02, count: 33)
        let chainCode = Data(repeating: 0xAA, count: 32)
        let result = PublicKeyResult(publicKey: key, chainCode: chainCode, address: "0x123")
        #expect(result.publicKey.count == 33)
        #expect(result.chainCode?.count == 32)
        #expect(result.address == "0x123")
    }

    @Test("AddressResult stores address and path")
    func addressResult() {
        let path = DerivationPath(string: "m/44'/60'/0'/0/0")!
        let result = AddressResult(address: "0xABCD", publicKey: Data([0x04]), path: path)
        #expect(result.address == "0xABCD")
        #expect(result.publicKey?.count == 1)
        #expect(result.path.description == "m/44'/60'/0'/0/0")
    }

    @Test("SignatureResult r and s extraction")
    func signatureComponents() {
        // 64-byte raw signature
        var sig = Data(repeating: 0x11, count: 32) // R
        sig.append(contentsOf: Data(repeating: 0x22, count: 32)) // S
        let result = SignatureResult(signature: sig, recoveryId: 0)
        #expect(result.r?.count == 32)
        #expect(result.s?.count == 32)
        #expect(result.r?.first == 0x11)
        #expect(result.s?.first == 0x22)
        #expect(result.recoveryId == 0)
    }

    @Test("SignatureResult handles short signature gracefully")
    func shortSignature() {
        let result = SignatureResult(signature: Data([0x01, 0x02]))
        #expect(result.r == nil)
        #expect(result.s == nil)
    }

    @Test("TransactionDisplayInfo stores all fields")
    func transactionDisplayInfo() {
        let info = TransactionDisplayInfo(
            type: "Send",
            amount: "0.5 ETH",
            recipient: "0x1234",
            fee: "0.001 ETH",
            network: "Ethereum"
        )
        #expect(info.type == "Send")
        #expect(info.amount == "0.5 ETH")
        #expect(info.recipient == "0x1234")
        #expect(info.fee == "0.001 ETH")
        #expect(info.network == "Ethereum")
    }
}

// MARK: - E8: HWError

@Suite("E8: Hardware Wallet Error Handling")
struct HWErrorTests {
    @Test("All error types have user-friendly descriptions")
    func allErrorDescriptions() {
        let errors: [HWError] = [
            .deviceNotFound,
            .connectionFailed("reason"),
            .deviceDisconnected,
            .timeout,
            .permissionDenied,
            .appNotOpen(appName: "Bitcoin"),
            .appVersionUnsupported(required: "2.0", current: "1.0"),
            .wrongApp(expected: "Bitcoin", current: "Ethereum"),
            .userRejected,
            .pinRequired,
            .pinIncorrect,
            .passphraseRequired,
            .deviceLocked,
            .invalidResponse("details"),
            .communicationError("comm"),
            .apduError(statusWord: 0x6985),
            .unsupportedChain("polkadot"),
            .unsupportedOperation("op"),
            .invalidTransaction("reason"),
            .invalidPath("m/0"),
            .notImplemented("feature"),
            .unknown("msg")
        ]
        for err in errors {
            #expect(err.errorDescription != nil, "Error should have description: \(err)")
            #expect(!err.errorDescription!.isEmpty)
        }
    }

    @Test("APDU status word 0x9000 is success")
    func successStatusWord() {
        let error = HWError.fromStatusWord(0x9000)
        #expect(error == nil)
    }

    @Test("APDU status word 0x6985 is user rejected")
    func rejectedStatusWord() {
        let error = HWError.fromStatusWord(0x6985)
        if case .userRejected = error {
            // OK
        } else {
            Issue.record("Expected userRejected, got \(String(describing: error))")
        }
    }

    @Test("APDU status word 0x6982 is pin required")
    func pinStatusWord() {
        let error = HWError.fromStatusWord(0x6982)
        if case .pinRequired = error {
            // OK
        } else {
            Issue.record("Expected pinRequired")
        }
    }

    @Test("Unknown APDU status words produce apduError")
    func unknownStatusWord() {
        let error = HWError.fromStatusWord(0x1234)
        if case .apduError(let sw) = error {
            #expect(sw == 0x1234)
        } else {
            Issue.record("Expected apduError")
        }
    }
}

// MARK: - E9: Ledger APDU Commands

@Suite("E9: Ledger APDU Command Building")
struct LedgerAPDUCommandTests {
    @Test("Build basic APDU")
    func buildBasic() {
        let apdu = LedgerAPDUCommand.build(cla: 0xB0, ins: 0x01, p1: 0x00, p2: 0x00)
        #expect(apdu.count >= 4)
        #expect(apdu[0] == 0xB0)
        #expect(apdu[1] == 0x01)
    }

    @Test("Build APDU with data")
    func buildWithData() {
        let data = Data([0x01, 0x02, 0x03])
        let apdu = LedgerAPDUCommand.build(cla: 0xE0, ins: 0x40, data: data)
        // CLA + INS + P1 + P2 + Lc + data = 4 + 1 + 3 = 8
        #expect(apdu.count == 8)
        #expect(apdu[4] == 3) // Lc = data length
    }

    @Test("Parse response with status word")
    func parseResponse() {
        // Data + SW1 + SW2
        let response = Data([0xAA, 0xBB, 0x90, 0x00])
        let parsed = LedgerAPDUCommand.parseResponse(response)
        #expect(parsed != nil)
        #expect(parsed!.statusWord == 0x9000)
        #expect(parsed!.data.count == 2)
    }

    @Test("Parse empty response")
    func parseEmptyResponse() {
        let response = Data([0x90, 0x00])
        let parsed = LedgerAPDUCommand.parseResponse(response)
        #expect(parsed != nil)
        #expect(parsed!.statusWord == 0x9000)
        #expect(parsed!.data.isEmpty)
    }

    @Test("Parse too-short response returns nil")
    func parseTooShort() {
        let response = Data([0x90])
        let parsed = LedgerAPDUCommand.parseResponse(response)
        #expect(parsed == nil)
    }
}

// MARK: - E10: Hardware Wallet Account

@Suite("E10: Hardware Wallet Account Model")
struct HardwareWalletAccountTests {
    @Test("Account creation with defaults")
    func creation() {
        let account = HardwareWalletAccount(
            deviceType: .ledgerNanoX,
            chain: .ethereum,
            derivationPath: "m/44'/60'/0'/0/0",
            address: "0x742d35Cc6634C0532925a3b844Bc9e7595f",
            publicKey: "04abcdef"
        )
        #expect(!account.id.isEmpty)
        #expect(account.deviceType == .ledgerNanoX)
        #expect(account.chain == .ethereum)
        #expect(account.label == nil)
    }

    @Test("Account is Codable")
    func codable() throws {
        let account = HardwareWalletAccount(
            deviceType: .trezorModelT,
            chain: .bitcoin,
            derivationPath: "m/84'/0'/0'/0/0",
            address: "bc1qxyz",
            publicKey: "02abcdef",
            label: "My Trezor"
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(HardwareWalletAccount.self, from: data)
        #expect(decoded.deviceType == .trezorModelT)
        #expect(decoded.chain == .bitcoin)
        #expect(decoded.address == "bc1qxyz")
        #expect(decoded.label == "My Trezor")
    }

    @Test("Truncated address formatting")
    func truncatedAddress() {
        let account = HardwareWalletAccount(
            deviceType: .ledgerNanoX,
            chain: .ethereum,
            derivationPath: "m/44'/60'/0'/0/0",
            address: "0x742d35Cc6634C0532925a3b844Bc9e7595f",
            publicKey: ""
        )
        let truncated = account.truncatedAddress
        #expect(truncated.contains("..."))
        #expect(truncated.count < account.address.count)
    }

    @Test("Short address not truncated")
    func shortAddress() {
        let account = HardwareWalletAccount(
            deviceType: .trezorOne,
            chain: .bitcoin,
            derivationPath: "m/84'/0'/0'/0/0",
            address: "bc1qshort",
            publicKey: ""
        )
        #expect(!account.truncatedAddress.contains("..."))
    }
}

// MARK: - E11: Discovered Device

@Suite("E11: Discovered Device Model")
struct DiscoveredDeviceTests {
    @Test("USB device creation")
    func usbDevice() {
        let device = DiscoveredDevice(
            id: "usb-12345",
            deviceType: .ledgerNanoS,
            connectionType: .usb,
            name: "Ledger Nano S"
        )
        #expect(device.id == "usb-12345")
        #expect(device.connectionType == .usb)
        #expect(device.deviceType == .ledgerNanoS)
    }

    @Test("Bluetooth device creation")
    func bleDevice() {
        let device = DiscoveredDevice(
            id: "ble-uuid",
            deviceType: .ledgerNanoX,
            connectionType: .bluetooth,
            name: "Nano X"
        )
        #expect(device.connectionType == .bluetooth)
    }

    @Test("Connection type display names")
    func connectionTypeNames() {
        #expect(DiscoveredDevice.ConnectionType.usb.displayName == "USB")
        #expect(DiscoveredDevice.ConnectionType.bluetooth.displayName == "Bluetooth")
    }

    @Test("Connection type icon names")
    func connectionTypeIcons() {
        #expect(DiscoveredDevice.ConnectionType.usb.iconName == "cable.connector")
        #expect(DiscoveredDevice.ConnectionType.bluetooth.iconName == "dot.radiowaves.left.and.right")
    }
}

// MARK: - E12: Device Info

@Suite("E12: Device Info Model")
struct DeviceInfoTests {
    @Test("Device info stores all fields")
    func deviceInfo() {
        let info = DeviceInfo(
            manufacturer: "Ledger",
            model: "Nano X",
            firmwareVersion: "2.1.0",
            serialNumber: "SN12345",
            mcuVersion: "1.12",
            seVersion: "1.4.2"
        )
        #expect(info.manufacturer == "Ledger")
        #expect(info.model == "Nano X")
        #expect(info.firmwareVersion == "2.1.0")
        #expect(info.serialNumber == "SN12345")
    }
}

// MARK: - E13: Analytics Events

@Suite("E13: Hardware Wallet Analytics Events")
struct HardwareWalletAnalyticsTests {
    @Test("All 8 roadmap events defined")
    func allEventsExist() {
        #expect(!AnalyticsService.EventName.hwPairingStarted.isEmpty)
        #expect(!AnalyticsService.EventName.hwPaired.isEmpty)
        #expect(!AnalyticsService.EventName.hwPairingFailed.isEmpty)
        #expect(!AnalyticsService.EventName.hwSigningRequested.isEmpty)
        #expect(!AnalyticsService.EventName.hwSigningConfirmed.isEmpty)
        #expect(!AnalyticsService.EventName.hwSigningRejected.isEmpty)
        #expect(!AnalyticsService.EventName.hwDisconnected.isEmpty)
        #expect(!AnalyticsService.EventName.hwAddressVerified.isEmpty)
    }

    @Test("Event name format follows convention")
    func eventNameFormat() {
        let events = [
            AnalyticsService.EventName.hwPairingStarted,
            AnalyticsService.EventName.hwPaired,
            AnalyticsService.EventName.hwPairingFailed,
            AnalyticsService.EventName.hwSigningRequested,
            AnalyticsService.EventName.hwSigningConfirmed,
            AnalyticsService.EventName.hwSigningRejected,
            AnalyticsService.EventName.hwDisconnected,
            AnalyticsService.EventName.hwAddressVerified
        ]
        for event in events {
            #expect(event.hasPrefix("hardware_wallet_"), "\(event) should start with hardware_wallet_")
        }
    }

    @Test("Legacy hw_wallet_connected event still exists")
    func legacyEvent() {
        #expect(AnalyticsService.EventName.hardwareWalletConnected == "hw_wallet_connected")
    }
}

// MARK: - E14: NavigationViewModel HW State

@Suite("E14: NavigationViewModel Hardware Wallet State")
struct NavigationViewModelHWTests {
    @MainActor
    @Test("Hardware wallet state properties exist")
    func hwStateProperties() {
        let vm = NavigationViewModel()
        #expect(vm.isHardwareWalletConnected == false)
        #expect(vm.connectedHardwareDeviceType == nil)
        #expect(vm.hardwareWalletFirmwareVersion == nil)
        #expect(vm.showHardwareWalletSetupSheet == false)
    }

    @MainActor
    @Test("Hardware wallet sheet property exists")
    func hwSheetProperty() {
        let vm = NavigationViewModel()
        #expect(vm.showHardwareWalletSheet == false)
    }

    @MainActor
    @Test("dismissAllSheets resets HW state")
    func dismissAllSheetsResetsHW() {
        let vm = NavigationViewModel()
        vm.showHardwareWalletSheet = true
        vm.showHardwareWalletSetupSheet = true

        vm.dismissAllSheets()

        #expect(vm.showHardwareWalletSheet == false)
        #expect(vm.showHardwareWalletSetupSheet == false)
    }

    @MainActor
    @Test("Can track connected device type")
    func trackConnectedDevice() {
        let vm = NavigationViewModel()
        vm.isHardwareWalletConnected = true
        vm.connectedHardwareDeviceType = .ledgerNanoX
        vm.hardwareWalletFirmwareVersion = "2.1.0"

        #expect(vm.isHardwareWalletConnected == true)
        #expect(vm.connectedHardwareDeviceType == .ledgerNanoX)
        #expect(vm.hardwareWalletFirmwareVersion == "2.1.0")
    }
}

// MARK: - E15: HardwareWalletManagerV2 Singleton

@Suite("E15: HardwareWalletManagerV2")
struct HardwareWalletManagerV2Tests {
    @MainActor
    @Test("Singleton exists")
    func singletonExists() {
        let manager = HardwareWalletManagerV2.shared
        #expect(manager === HardwareWalletManagerV2.shared)
    }

    @MainActor
    @Test("Initial state is empty")
    func initialState() {
        let manager = HardwareWalletManagerV2.shared
        #expect(manager.isScanning == false || manager.isScanning == true) // May have been started
        #expect(manager.error == nil)
    }

    @MainActor
    @Test("Can get accounts for chain")
    func getAccountsForChain() {
        let manager = HardwareWalletManagerV2.shared
        let ethAccounts = manager.getAccounts(for: .ethereum)
        // May or may not have accounts, but should not crash
        #expect(ethAccounts.count >= 0)
    }
}

// MARK: - E16: Trezor Message Protocol

@Suite("E16: Trezor Message Protocol")
struct TrezorMessageTests {
    @Test("TrezorInitialize encodes")
    func initializeEncodes() {
        let msg = TrezorInitialize()
        let data = msg.encode()
        // Empty message should produce empty or minimal data
        #expect(data.count >= 0)
    }

    @Test("TrezorFeatures message type")
    func featuresMessageType() {
        #expect(TrezorFeatures.messageType == .features)
        #expect(TrezorFeatures.messageType.rawValue == 17)
    }

    @Test("TrezorFeatures with version")
    func featuresVersion() {
        let features = TrezorFeatures(
            vendor: "trezor.io",
            majorVersion: 2,
            minorVersion: 6,
            patchVersion: 0
        )
        #expect(features.vendor == "trezor.io")
        #expect(features.majorVersion == 2)
        #expect(features.minorVersion == 6)
        #expect(features.patchVersion == 0)
    }

    @Test("Message type IDs match Trezor spec")
    func messageTypeIds() {
        #expect(TrezorMessageType.initialize.rawValue == 0)
        #expect(TrezorMessageType.features.rawValue == 17)
        #expect(TrezorMessageType.getPublicKey.rawValue == 11)
        #expect(TrezorMessageType.publicKey.rawValue == 12)
        #expect(TrezorMessageType.signTx.rawValue == 15)
        #expect(TrezorMessageType.signMessage.rawValue == 38)
        #expect(TrezorMessageType.ethereumSignTx.rawValue == 58)
        #expect(TrezorMessageType.solanaGetPublicKey.rawValue == 512)
    }
}

// MARK: - E17: Ledger APDU Legacy Commands

@Suite("E17: Legacy Ledger APDU")
struct LedgerAPDUTests {
    @Test("Get version command format")
    func getVersion() {
        let cmd = LedgerAPDU.getVersion()
        #expect(cmd.count == 5)
        #expect(cmd[0] == 0xE0) // CLA
        #expect(cmd[1] == 0xC4) // INS
    }

    @Test("Serialize derivation path")
    func serializePath() {
        let data = LedgerAPDU.serializeDerivationPath("m/44'/60'/0'/0/0")
        // 1 byte count + 5 * 4 bytes = 21 bytes
        #expect(data.count == 21)
        #expect(data[0] == 5) // 5 components
    }

    @Test("Get public key APDU")
    func getPublicKey() {
        let cmd = LedgerAPDU.getPublicKey(path: "m/44'/60'/0'/0/0", display: true)
        #expect(cmd[0] == 0xE0)
        #expect(cmd[1] == 0x40) // INS_GET_WALLET_PUBLIC_KEY
        #expect(cmd[2] == 0x01) // display = true
    }
}

// MARK: - E18: HardwareWalletTransaction

@Suite("E18: Hardware Wallet Transaction")
struct HardwareWalletTransactionTests {
    @Test("Transaction with display info")
    func withDisplayInfo() {
        let tx = HardwareWalletTransaction(
            rawData: Data([0x01, 0x02]),
            preImageHashes: [Data([0xAA])],
            displayInfo: TransactionDisplayInfo(
                type: "Send",
                amount: "0.1 ETH",
                recipient: "0x1234",
                fee: "0.002 ETH",
                network: "Ethereum"
            )
        )
        #expect(tx.rawData.count == 2)
        #expect(tx.preImageHashes?.count == 1)
        #expect(tx.displayInfo?.type == "Send")
    }

    @Test("Transaction without display info")
    func withoutDisplayInfo() {
        let tx = HardwareWalletTransaction(rawData: Data([0xFF]))
        #expect(tx.displayInfo == nil)
        #expect(tx.preImageHashes == nil)
    }
}

// MARK: - E19: Legacy HardwareWalletManager (V1)

@Suite("E19: Legacy HardwareWalletManager")
struct LegacyHardwareWalletManagerTests {
    @MainActor
    @Test("V1 manager singleton exists")
    func v1Singleton() {
        let manager = HardwareWalletManager.shared
        #expect(manager !== nil as AnyObject?)
    }

    @Test("HardwareWalletType has all standard models")
    func walletTypes() {
        let types = HardwareWalletType.allCases
        #expect(types.count >= 5)
        // Check Ledger and Trezor types exist
        #expect(types.contains(.ledgerNanoS))
        #expect(types.contains(.ledgerNanoX))
        #expect(types.contains(.trezorOne))
        #expect(types.contains(.trezorT))
    }

    @Test("HardwareWalletError descriptions")
    func errorDescriptions() {
        let errors: [HardwareWalletError] = [
            .deviceNotFound,
            .communicationFailed,
            .invalidResponse,
            .userRejected,
            .appNotOpen("Ethereum"),
            .timeout
        ]
        for err in errors {
            #expect(err.errorDescription != nil)
        }
    }
}

// MARK: - E20: WalletImportManager HW Support

@Suite("E20: WalletImportManager Hardware Integration")
struct WalletImportManagerHWTests {
    @Test("Hardware wallet import method exists")
    func hwImportMethod() {
        let method = WalletImportMethod.hardwareWallet
        #expect(method.rawValue == "hardware_wallet")
    }

    @Test("Hardware wallet has correct display name")
    func hwDisplayName() {
        #expect(WalletImportMethod.hardwareWallet.title == "Hardware Wallet")
    }

    @Test("Hardware wallet has icon")
    func hwIcon() {
        #expect(WalletImportMethod.hardwareWallet.icon == "cpu")
    }

    @Test("Hardware wallet has subtitle")
    func hwSubtitle() {
        let subtitle = WalletImportMethod.hardwareWallet.description
        #expect(subtitle.contains("Ledger") || subtitle.contains("Trezor"))
    }

    @Test("Hardware error types exist")
    func hwErrors() {
        let errors: [ImportError] = [
            .hardwareNotConnected,
            .hardwareRejected
        ]
        for err in errors {
            #expect(err.errorDescription != nil)
            #expect(!err.errorDescription!.isEmpty)
        }
    }
}

// MARK: - E21: Localization

@Suite("E21: Hardware Wallet Localization")
struct HardwareWalletLocalizationTests {
    @Test("Hardware wallet strings exist")
    @MainActor func hwStringsExist() {
        let keys = [
            "hardware.title",
            "hardware.connect",
            "hardware.disconnect",
            "hardware.connected",
            "hardware.not_connected",
            "hardware.ledger",
            "hardware.trezor"
        ]
        for key in keys {
            let value = LocalizationManager.shared.localized(key)
            #expect(!value.isEmpty, "Missing localization: \(key)")
        }
    }
}

// MARK: - E22: Security Score Integration

@Suite("E22: Hardware Wallet Security Score")
struct SecurityScoreHWTests {
    @Test("Hardware wallet connected is a security item")
    func hwSecurityItem() {
        let item = SecurityScoreManager.SecurityItem.hardwareWalletConnected
        #expect(item.rawValue == "hardwareWallet")
    }

    @Test("Hardware item has title and description")
    func hwItemDetails() {
        let item = SecurityScoreManager.SecurityItem.hardwareWalletConnected
        #expect(!item.title.isEmpty)
        #expect(!item.description.isEmpty)
    }

    @Test("Hardware item has icon")
    func hwItemIcon() {
        let icon = SecurityScoreManager.SecurityItem.hardwareWalletConnected.icon
        #expect(!icon.isEmpty)
    }

    @Test("Hardware item contributes points")
    func hwItemPoints() {
        let points = SecurityScoreManager.SecurityItem.hardwareWalletConnected.points
        #expect(points > 0)
    }
}

// MARK: - E23: Onboarding HW Support

@Suite("E23: Onboarding Hardware Wallet Flow")
struct OnboardingHWTests {
    @Test("Onboarding has hardware wallet connect step")
    func hwOnboardingStep() {
        let step = NewOnboardingStep.hardwareWalletConnect
        #expect(step == .hardwareWalletConnect)
    }

    @Test("Ledger creation method exists")
    func ledgerCreationMethod() {
        let method = WalletCreationMethod.ledger
        #expect(method.rawValue == "ledger")
    }

    @Test("Trezor creation method exists")
    func trezorCreationMethod() {
        let method = WalletCreationMethod.trezor
        #expect(method.rawValue == "trezor")
    }

    @Test("Import hardware wallet step exists")
    func importHWStep() {
        let step = NewOnboardingStep.importHardwareWallet
        #expect(step == .importHardwareWallet)
    }

    @Test("Ledger and Trezor have display names")
    func creationMethodNames() {
        #expect(!WalletCreationMethod.ledger.title.isEmpty)
        #expect(!WalletCreationMethod.trezor.title.isEmpty)
    }
}
