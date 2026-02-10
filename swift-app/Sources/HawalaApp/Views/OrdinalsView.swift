import SwiftUI

// MARK: - Ordinals Gallery View

/// Main view for displaying Ordinals inscriptions and BRC-20 tokens
struct OrdinalsView: View {
    @StateObject private var viewModel = OrdinalsViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Inscriptions").tag(0)
                    Text("BRC-20").tag(1)
                    Text("Collections").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Content
                if viewModel.isLoading {
                    loadingView
                } else {
                    switch selectedTab {
                    case 0:
                        inscriptionsGrid
                    case 1:
                        brc20ListView
                    case 2:
                        collectionsGrid
                    default:
                        inscriptionsGrid
                    }
                }
            }
            .navigationTitle("Ordinals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $viewModel.selectedInscription) { inscription in
                InscriptionDetailView(inscription: inscription)
            }
            .sheet(item: $viewModel.selectedToken) { token in
                BRC20DetailView(token: token)
            }
        }
        .onAppear {
            viewModel.loadData()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(LoadingCopy.ordinals)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Inscriptions Grid
    
    private var inscriptionsGrid: some View {
        ScrollView {
            if viewModel.inscriptions.isEmpty {
                emptyState(
                    icon: "photo.stack",
                    title: "No Inscriptions",
                    message: "Your Bitcoin inscriptions will appear here"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                ], spacing: 16) {
                    ForEach(viewModel.inscriptions) { inscription in
                        InscriptionCard(inscription: inscription)
                            .onTapGesture {
                                viewModel.selectedInscription = inscription
                            }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - BRC-20 List
    
    private var brc20ListView: some View {
        ScrollView {
            if viewModel.brc20Balances.isEmpty {
                emptyState(
                    icon: "bitcoinsign.circle",
                    title: "No BRC-20 Tokens",
                    message: "Your BRC-20 token balances will appear here"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.brc20Balances) { balance in
                        BRC20BalanceRow(balance: balance)
                            .onTapGesture {
                                if let token = viewModel.tokenInfo[balance.tick] {
                                    viewModel.selectedToken = token
                                }
                            }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Collections Grid
    
    private var collectionsGrid: some View {
        ScrollView {
            if viewModel.collections.isEmpty {
                emptyState(
                    icon: "square.grid.3x3",
                    title: "No Collections",
                    message: "Ordinals collections you own will appear here"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
                ], spacing: 16) {
                    ForEach(viewModel.collections) { collection in
                        CollectionCard(collection: collection)
                    }
                }
                .padding()
            }
        }
    }
    
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.5))
            
            Text(title)
                .font(.title2.bold())
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inscription Card

struct InscriptionCard: View {
    let inscription: Inscription
    
    var body: some View {
        VStack(spacing: 8) {
            // Content preview
            contentPreview
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(inscription.number)")
                    .font(.caption.bold())
                
                Text(inscription.contentTypeLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let rarity = inscription.satRarity {
                    HStack(spacing: 2) {
                        Text(rarity.emoji)
                        Text(rarity.name)
                            .font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        if inscription.isImage {
            // Would load actual image from inscription content URL
            AsyncImage(url: URL(string: inscription.contentUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    imagePlaceholder
                case .empty:
                    ProgressView()
                @unknown default:
                    imagePlaceholder
                }
            }
        } else if inscription.isText {
            textPreview
        } else if inscription.isHtml {
            htmlPlaceholder
        } else {
            genericPlaceholder
        }
    }
    
    private var imagePlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.title)
                .foregroundColor(.gray)
        }
    }
    
    private var textPreview: some View {
        ZStack {
            Color.black
            Text(inscription.textPreview ?? "Text")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.green)
                .lineLimit(8)
                .padding(8)
        }
    }
    
    private var htmlPlaceholder: some View {
        ZStack {
            Color.blue.opacity(0.2)
            VStack {
                Image(systemName: "globe")
                    .font(.title)
                Text("HTML")
                    .font(.caption2)
            }
            .foregroundColor(.blue)
        }
    }
    
    private var genericPlaceholder: some View {
        ZStack {
            Color.purple.opacity(0.2)
            VStack {
                Image(systemName: "doc.fill")
                    .font(.title)
                Text(inscription.contentType)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundColor(.purple)
        }
    }
}

// MARK: - Inscription Detail View

struct InscriptionDetailView: View {
    let inscription: Inscription
    @Environment(\.dismiss) private var dismiss
    @State private var showingFullImage = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Large content preview
                    contentPreview
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture {
                            if inscription.isImage {
                                showingFullImage = true
                            }
                        }
                    
                    // Inscription info
                    infoSection
                    
                    // Sat info
                    satSection
                    
                    // Actions
                    actionsSection
                }
                .padding()
            }
            .navigationTitle("Inscription #\(inscription.number)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: inscription.explorerUrl)
                }
            }
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        if inscription.isImage {
            AsyncImage(url: URL(string: inscription.contentUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    errorView
                case .empty:
                    ProgressView()
                @unknown default:
                    errorView
                }
            }
        } else {
            ZStack {
                Color(.controlBackgroundColor)
                VStack {
                    Image(systemName: inscription.contentTypeIcon)
                        .font(.system(size: 60))
                    Text(inscription.contentType)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var errorView: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text("Failed to load")
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            infoRow("Inscription ID", inscription.id, copyable: true)
            infoRow("Content Type", inscription.contentType)
            infoRow("Content Size", inscription.formattedSize)
            infoRow("Genesis TX", inscription.genesisTx, copyable: true)
            infoRow("Genesis Block", "\(inscription.genesisHeight)")
            if let address = inscription.address {
                infoRow("Owner", address, copyable: true)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var satSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Satoshi")
                .font(.headline)
            
            infoRow("Ordinal", "\(inscription.sat)")
            
            if let rarity = inscription.satRarity {
                HStack {
                    Text("Rarity")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(rarity.emoji)
                        Text(rarity.name)
                            .foregroundColor(rarity.color)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: {}) {
                HStack {
                    Image(systemName: "arrow.up.right")
                    Text("View on Explorer")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "paperplane")
                    Text("Transfer Inscription")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }
    
    private func infoRow(_ label: String, _ value: String, copyable: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            if copyable {
                Button(action: { copyToClipboard(value) }) {
                    Text(truncate(value))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
    
    private func truncate(_ s: String) -> String {
        if s.count > 20 {
            return "\(s.prefix(8))...\(s.suffix(8))"
        }
        return s
    }
    
    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Auto-clear clipboard after 60 seconds for security
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if NSPasteboard.general.string(forType: .string) == text {
                NSPasteboard.general.clearContents()
            }
        }
        #endif
    }
}

// MARK: - BRC-20 Balance Row

struct BRC20BalanceRow: View {
    let balance: BRC20Balance
    
    var body: some View {
        HStack(spacing: 12) {
            // Token icon
            ZStack {
                Circle()
                    .fill(tokenColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Text(balance.tick.prefix(1).uppercased())
                    .font(.headline.bold())
                    .foregroundColor(tokenColor)
            }
            
            // Token info
            VStack(alignment: .leading, spacing: 4) {
                Text(balance.tick.uppercased())
                    .font(.headline)
                
                Text("Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Balances
            VStack(alignment: .trailing, spacing: 4) {
                Text(balance.formattedTotal)
                    .font(.headline)
                
                if balance.transferable > 0 {
                    Text("\(balance.formattedTransferable) transferable")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var tokenColor: Color {
        // Generate color based on ticker
        let hash = balance.tick.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
}

// MARK: - BRC-20 Detail View

struct BRC20DetailView: View {
    let token: BRC20Token
    @Environment(\.dismiss) private var dismiss
    @State private var transferAmount = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Token header
                    tokenHeader
                    
                    // Supply info
                    supplyCard
                    
                    // Token details
                    detailsCard
                    
                    // Transfer section
                    transferSection
                }
                .padding()
            }
            .navigationTitle(token.tick.uppercased())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private var tokenHeader: some View {
        VStack(spacing: 12) {
            // Token icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Text(token.tick.prefix(2).uppercased())
                    .font(.title.bold())
                    .foregroundColor(.orange)
            }
            
            Text(token.tick.uppercased())
                .font(.title2.bold())
            
            if token.isFullyMinted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Fully Minted")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private var supplyCard: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mint Progress")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f%%", token.mintProgress))
                        .font(.subheadline.bold())
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(token.mintProgress / 100), height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            // Supply info
            HStack {
                supplyItem("Total Supply", token.formattedMaxSupply)
                Divider()
                    .frame(height: 40)
                supplyItem("Minted", token.formattedMinted)
                Divider()
                    .frame(height: 40)
                supplyItem("Remaining", token.formattedRemaining)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func supplyItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token Details")
                .font(.headline)
            
            detailRow("Deploy Inscription", token.deployInscription)
            detailRow("Limit per Mint", token.limitPerMint)
            detailRow("Decimals", "\(token.decimals)")
            detailRow("Holders", "\(token.holders)")
            detailRow("Transactions", "\(token.transactions)")
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    private var transferSection: some View {
        VStack(spacing: 12) {
            Text("Transfer")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("Amount", text: $transferAmount)
                .textFieldStyle(.roundedBorder)
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("Create Transfer Inscription")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(transferAmount.isEmpty)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Collection Card

struct CollectionCard: View {
    let collection: OrdinalsCollection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collection image
            if let iconUrl = collection.iconUrl {
                AsyncImage(url: URL(string: iconUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        collectionPlaceholder
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                collectionPlaceholder
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Collection info
            Text(collection.name)
                .font(.headline)
                .lineLimit(1)
            
            HStack {
                Text("\(collection.supply) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let floor = collection.floorPrice {
                    HStack(spacing: 2) {
                        Image(systemName: "bitcoinsign.circle")
                            .font(.caption2)
                        Text(formatBTC(floor))
                            .font(.caption.bold())
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var collectionPlaceholder: some View {
        ZStack {
            Color.purple.opacity(0.2)
            Image(systemName: "square.grid.3x3")
                .font(.title)
                .foregroundColor(.purple)
        }
    }
    
    private func formatBTC(_ btc: Double) -> String {
        if btc >= 1 {
            return String(format: "%.2f BTC", btc)
        } else {
            return String(format: "%.6f", btc)
        }
    }
}

// MARK: - View Model

@MainActor
class OrdinalsViewModel: ObservableObject {
    @Published var inscriptions: [Inscription] = []
    @Published var brc20Balances: [BRC20Balance] = []
    @Published var collections: [OrdinalsCollection] = []
    @Published var tokenInfo: [String: BRC20Token] = [:]
    @Published var isLoading = false
    @Published var selectedInscription: Inscription?
    @Published var selectedToken: BRC20Token?
    
    func loadData() {
        isLoading = true
        
        Task {
            // Simulate loading
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Load mock data
            inscriptions = Inscription.mockList()
            brc20Balances = BRC20Balance.mockList()
            collections = OrdinalsCollection.mockList()
            
            // Build token info map
            for balance in brc20Balances {
                tokenInfo[balance.tick] = BRC20Token.mock(tick: balance.tick)
            }
            
            isLoading = false
        }
    }
    
    func refresh() {
        loadData()
    }
}

// MARK: - Models

struct Inscription: Identifiable {
    let id: String
    let number: Int
    let contentType: String
    let contentLength: Int
    let genesisTx: String
    let genesisHeight: Int
    let sat: UInt64
    let output: String
    let address: String?
    let timestamp: Date
    
    var isImage: Bool {
        contentType.hasPrefix("image/")
    }
    
    var isText: Bool {
        contentType.hasPrefix("text/") || contentType == "application/json"
    }
    
    var isHtml: Bool {
        contentType == "text/html"
    }
    
    var contentTypeLabel: String {
        if isImage { return "Image" }
        if isText { return "Text" }
        if isHtml { return "HTML" }
        return contentType
    }
    
    var contentTypeIcon: String {
        if isImage { return "photo" }
        if isText { return "doc.text" }
        if isHtml { return "globe" }
        if contentType.hasPrefix("video/") { return "video" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
    
    var contentUrl: String {
        "https://ordinals.com/content/\(id)"
    }
    
    var explorerUrl: URL {
        URL(string: "https://ordinals.com/inscription/\(id)")!
    }
    
    var formattedSize: String {
        if contentLength >= 1_000_000 {
            return String(format: "%.2f MB", Double(contentLength) / 1_000_000)
        } else if contentLength >= 1_000 {
            return String(format: "%.1f KB", Double(contentLength) / 1_000)
        }
        return "\(contentLength) bytes"
    }
    
    var textPreview: String? {
        isText ? "Preview text content..." : nil
    }
    
    var satRarity: SatRarity? {
        SatRarity.from(sat: sat)
    }
    
    static func mockList() -> [Inscription] {
        [
            Inscription(id: "abc123i0", number: 12345, contentType: "image/png", contentLength: 50000, genesisTx: "abc123", genesisHeight: 800000, sat: 1234567890, output: "abc123:0", address: "bc1q...", timestamp: Date()),
            Inscription(id: "def456i0", number: 12346, contentType: "text/plain", contentLength: 100, genesisTx: "def456", genesisHeight: 800001, sat: 0, output: "def456:0", address: "bc1q...", timestamp: Date()),
            Inscription(id: "ghi789i0", number: 12347, contentType: "text/html", contentLength: 5000, genesisTx: "ghi789", genesisHeight: 800002, sat: 5000000000, output: "ghi789:0", address: "bc1q...", timestamp: Date()),
        ]
    }
}

struct BRC20Balance: Identifiable {
    var id: String { tick }
    let tick: String
    let available: Double
    let transferable: Double
    let total: Double
    
    var formattedTotal: String {
        formatNumber(total)
    }
    
    var formattedTransferable: String {
        formatNumber(transferable)
    }
    
    private func formatNumber(_ n: Double) -> String {
        if n >= 1_000_000 {
            return String(format: "%.2fM", n / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.2fK", n / 1_000)
        }
        return String(format: "%.2f", n)
    }
    
    static func mockList() -> [BRC20Balance] {
        [
            BRC20Balance(tick: "ordi", available: 100, transferable: 50, total: 150),
            BRC20Balance(tick: "sats", available: 50_000_000, transferable: 10_000_000, total: 60_000_000),
            BRC20Balance(tick: "rats", available: 1000, transferable: 0, total: 1000),
        ]
    }
}

struct BRC20Token: Identifiable {
    var id: String { tick }
    let tick: String
    let maxSupply: Double
    let minted: Double
    let limitPerMint: String
    let decimals: Int
    let deployInscription: String
    let holders: Int
    let transactions: Int
    
    var mintProgress: Double {
        maxSupply > 0 ? (minted / maxSupply) * 100 : 0
    }
    
    var isFullyMinted: Bool {
        mintProgress >= 100
    }
    
    var formattedMaxSupply: String {
        formatLargeNumber(maxSupply)
    }
    
    var formattedMinted: String {
        formatLargeNumber(minted)
    }
    
    var formattedRemaining: String {
        formatLargeNumber(max(0, maxSupply - minted))
    }
    
    private func formatLargeNumber(_ n: Double) -> String {
        if n >= 1_000_000_000 {
            return String(format: "%.2fB", n / 1_000_000_000)
        } else if n >= 1_000_000 {
            return String(format: "%.2fM", n / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.2fK", n / 1_000)
        }
        return String(format: "%.0f", n)
    }
    
    static func mock(tick: String) -> BRC20Token {
        switch tick {
        case "ordi":
            return BRC20Token(tick: "ordi", maxSupply: 21_000_000, minted: 21_000_000, limitPerMint: "1000", decimals: 18, deployInscription: "abc123i0", holders: 50000, transactions: 1_000_000)
        case "sats":
            return BRC20Token(tick: "sats", maxSupply: 2_100_000_000_000_000, minted: 2_100_000_000_000_000, limitPerMint: "100000000", decimals: 18, deployInscription: "def456i0", holders: 100000, transactions: 5_000_000)
        default:
            return BRC20Token(tick: tick, maxSupply: 1_000_000, minted: 500_000, limitPerMint: "1000", decimals: 18, deployInscription: "xyz789i0", holders: 1000, transactions: 10000)
        }
    }
}

struct OrdinalsCollection: Identifiable {
    let id: String
    let name: String
    let description: String?
    let supply: Int
    let floorPrice: Double?
    let totalVolume: Double?
    let iconUrl: String?
    
    static func mockList() -> [OrdinalsCollection] {
        [
            OrdinalsCollection(id: "bitcoin-puppets", name: "Bitcoin Puppets", description: "Puppets on Bitcoin", supply: 10000, floorPrice: 0.15, totalVolume: 500, iconUrl: nil),
            OrdinalsCollection(id: "nodemonkes", name: "NodeMonkes", description: "Monkes on nodes", supply: 10000, floorPrice: 0.08, totalVolume: 300, iconUrl: nil),
        ]
    }
}

struct SatRarity {
    let name: String
    let emoji: String
    let color: Color
    
    static func from(sat: UInt64) -> SatRarity? {
        if sat == 0 {
            return SatRarity(name: "Mythic", emoji: "🔴", color: .red)
        } else if sat % 2_100_000_000_000_000 == 0 {
            return SatRarity(name: "Legendary", emoji: "🟡", color: .yellow)
        } else if sat % 210_000_000_000_000 == 0 {
            return SatRarity(name: "Epic", emoji: "🟣", color: .purple)
        } else if sat % 52_500_000_000_000 == 0 {
            return SatRarity(name: "Rare", emoji: "🔵", color: .blue)
        } else if sat % 6_250_000_000 == 0 {
            return SatRarity(name: "Uncommon", emoji: "🟢", color: .green)
        }
        return nil // Common sats don't get a badge
    }
}

// MARK: - Previews

struct OrdinalsView_Previews: PreviewProvider {
    static var previews: some View {
        OrdinalsView()
            .frame(width: 600, height: 700)
    }
}
