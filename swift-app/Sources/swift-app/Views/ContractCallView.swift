import SwiftUI

/// Contract call builder and executor view
struct ContractCallView: View {
    @StateObject private var abiService = ABIService.shared
    @State private var contractAddress = ""
    @State private var abiJson = ""
    @State private var parsedABI: ABIService.ContractABI?
    @State private var selectedFunction: ABIService.ABIFunction?
    @State private var inputValues: [String] = []
    @State private var result: String?
    @State private var showABIPicker = false
    @State private var showSavedContracts = false
    @State private var contractName = ""
    @State private var selectedChainId = 1
    @State private var showCalldata = false
    @State private var generatedCalldata = ""
    
    private let chains = [
        (1, "Ethereum"),
        (56, "BNB Chain"),
        (137, "Polygon"),
        (42161, "Arbitrum"),
        (10, "Optimism"),
        (8453, "Base"),
        (43114, "Avalanche"),
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                
                contractInputSection
                
                if parsedABI != nil {
                    functionSelectorSection
                }
                
                if let function = selectedFunction {
                    parameterInputSection(function: function)
                    calldataSection(function: function)
                }
                
                if let result = result {
                    resultSection(result: result)
                }
                
                if !abiService.recentContracts.isEmpty {
                    savedContractsSection
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Contract Call")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("ERC-20 Token") { loadKnownABI(.erc20) }
                    Button("ERC-721 NFT") { loadKnownABI(.erc721) }
                    Divider()
                    Button("Saved Contracts...") { showSavedContracts = true }
                } label: {
                    Image(systemName: "doc.text")
                }
            }
        }
        .sheet(isPresented: $showSavedContracts) {
            savedContractsSheet
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Smart Contract Interaction")
                    .font(.headline)
                Spacer()
            }
            
            Text("Build and execute contract calls with ABI encoding")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var contractInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contract Details")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // Chain selector
            HStack {
                Text("Network")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $selectedChainId) {
                    ForEach(chains, id: \.0) { chain in
                        Text(chain.1).tag(chain.0)
                    }
                }
                .frame(width: 150)
            }
            
            // Contract address
            VStack(alignment: .leading, spacing: 4) {
                Text("Contract Address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("0x...", text: $contractAddress)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                    
                    if !contractAddress.isEmpty {
                        Button(action: { contractAddress = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: pasteAddress) {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // ABI input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ABI (JSON)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Load ERC-20") { loadKnownABI(.erc20) }
                        .font(.caption)
                    Button("Load ERC-721") { loadKnownABI(.erc721) }
                        .font(.caption)
                }
                
                TextEditor(text: $abiJson)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: abiJson) { _ in
                        parseABI()
                    }
            }
            
            // Parse status
            if let abi = parsedABI {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(abi.functions.count) functions, \(abi.events.count) events")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    private var functionSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Function")
                .font(.subheadline)
                .fontWeight(.medium)
            
            if let abi = parsedABI {
                // Read functions
                if !abi.readFunctions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("View Functions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(abi.readFunctions) { fn in
                                    FunctionButton(
                                        function: fn,
                                        isSelected: selectedFunction?.name == fn.name,
                                        action: { selectFunction(fn) }
                                    )
                                }
                            }
                        }
                    }
                }
                
                // Write functions
                if !abi.writeFunctions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Write Functions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(abi.writeFunctions) { fn in
                                    FunctionButton(
                                        function: fn,
                                        isSelected: selectedFunction?.name == fn.name,
                                        action: { selectFunction(fn) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    private func parameterInputSection(function: ABIService.ABIFunction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Parameters")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(function.signature)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if function.inputs.isEmpty {
                Text("No parameters required")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(function.inputs.enumerated()), id: \.offset) { index, param in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(param.name.isEmpty ? "param\(index)" : param.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("(\(param.type))")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        
                        TextField(placeholderFor(type: param.type), text: binding(for: index))
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    private func calldataSection(function: ABIService.ABIFunction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calldata")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: generateCalldata) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Generate")
                    }
                    .font(.caption)
                }
                
                if !generatedCalldata.isEmpty {
                    Button(action: copyCalldata) {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            
            // Selector display
            HStack {
                Text("Selector:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(function.selector)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.orange)
            }
            
            // Generated calldata
            if !generatedCalldata.isEmpty {
                Text(generatedCalldata)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if function.isReadOnly {
                    Button(action: executeCall) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Call (Read)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                } else {
                    Button(action: { /* Would build transaction */ }) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Build Transaction")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    private func resultSection(result: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: { self.result = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            Text(result)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    private var savedContractsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Contracts")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ForEach(abiService.recentContracts.prefix(3)) { contract in
                Button(action: { loadContract(contract) }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(contract.name)
                                .font(.subheadline)
                            Text(contract.address.prefix(10) + "..." + contract.address.suffix(6))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(chainName(for: contract.chainId))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    private var savedContractsSheet: some View {
        NavigationView {
            List {
                ForEach(abiService.recentContracts) { contract in
                    Button(action: {
                        loadContract(contract)
                        showSavedContracts = false
                    }) {
                        VStack(alignment: .leading) {
                            Text(contract.name)
                                .fontWeight(.medium)
                            Text(contract.address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Added \(contract.addedAt, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        abiService.removeContract(abiService.recentContracts[index].id)
                    }
                }
            }
            .navigationTitle("Saved Contracts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSavedContracts = false }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func pasteAddress() {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            contractAddress = string
        }
        #endif
    }
    
    private func parseABI() {
        guard !abiJson.isEmpty else {
            parsedABI = nil
            return
        }
        
        do {
            parsedABI = try abiService.parseABI(abiJson)
            selectedFunction = nil
            inputValues = []
        } catch {
            parsedABI = nil
        }
    }
    
    private func selectFunction(_ function: ABIService.ABIFunction) {
        selectedFunction = function
        inputValues = Array(repeating: "", count: function.inputs.count)
        generatedCalldata = ""
        result = nil
    }
    
    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < inputValues.count ? inputValues[index] : "" },
            set: { if index < inputValues.count { inputValues[index] = $0 } }
        )
    }
    
    private func placeholderFor(type: String) -> String {
        switch type {
        case "address": return "0x..."
        case "uint256", "uint": return "0"
        case "bool": return "true/false"
        case "bytes32": return "0x..."
        case "string": return "text"
        default: return type
        }
    }
    
    private func generateCalldata() {
        guard let function = selectedFunction else { return }
        
        var values: [ABIService.ABIValue] = []
        
        for (index, param) in function.inputs.enumerated() {
            let input = index < inputValues.count ? inputValues[index] : ""
            if let type = ABIService.ABIType.from(param.type),
               let value = ABIService.ABIValue.from(input: input, type: type) {
                values.append(value)
            }
        }
        
        generatedCalldata = abiService.encodeFunctionCall(
            signature: function.signature,
            values: values
        )
    }
    
    private func executeCall() {
        generateCalldata()
        // In a real implementation, this would make an eth_call RPC request
        result = "Call executed successfully (simulated)"
    }
    
    private func copyCalldata() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedCalldata, forType: .string)
        #endif
    }
    
    private func loadKnownABI(_ type: KnownABIType) {
        switch type {
        case .erc20:
            abiJson = ABIService.erc20ABI
        case .erc721:
            abiJson = ABIService.erc721ABI
        }
        parseABI()
    }
    
    private func loadContract(_ contract: ABIService.SavedContract) {
        contractAddress = contract.address
        selectedChainId = contract.chainId
        abiJson = contract.abiJson
        contractName = contract.name
        parseABI()
    }
    
    private func chainName(for id: Int) -> String {
        chains.first { $0.0 == id }?.1 ?? "Unknown"
    }
    
    private enum KnownABIType {
        case erc20, erc721
    }
}

// MARK: - Function Button

struct FunctionButton: View {
    let function: ABIService.ABIFunction
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(function.isReadOnly ? Color.blue : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(function.name)
                    .font(.caption)
                
                if function.isPayable {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NavigationView {
        ContractCallView()
    }
}
#endif
#endif
#endif
