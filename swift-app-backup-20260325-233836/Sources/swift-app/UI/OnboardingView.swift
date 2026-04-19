import SwiftUI

// MARK: - Onboarding Flow

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var currentPage = 0
    @State private var hasAgreedToTerms = false
    
    private let pages = OnboardingPage.allPages
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                }
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.automatic)
                .animation(.easeInOut, value: currentPage)
                
                // Page indicators and buttons
                VStack(spacing: 24) {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                    
                    // Terms agreement (on last page)
                    if currentPage == pages.count - 1 {
                        termsAgreement
                    }
                    
                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentPage > 0 {
                            Button {
                                withAnimation {
                                    currentPage -= 1
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
                        Button {
                            if currentPage < pages.count - 1 {
                                withAnimation {
                                    currentPage += 1
                                }
                            } else {
                                completeOnboarding()
                            }
                        } label: {
                            HStack {
                                Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                                Image(systemName: currentPage < pages.count - 1 ? "chevron.right" : "arrow.right")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(nextButtonEnabled ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(!nextButtonEnabled)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var nextButtonEnabled: Bool {
        if currentPage == pages.count - 1 {
            return hasAgreedToTerms
        }
        return true
    }
    
    private var termsAgreement: some View {
        Button {
            hasAgreedToTerms.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: hasAgreedToTerms ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(hasAgreedToTerms ? .blue : .secondary)
                
                Text("I understand that I am responsible for keeping my recovery phrase safe")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func completeOnboarding() {
        withAnimation {
            isOnboardingComplete = true
        }
        UserDefaults.standard.set(true, forKey: "hawala_onboarding_complete")
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let features: [OnboardingFeature]
    
    struct OnboardingFeature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }
    
    static var allPages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "wallet.pass.fill",
                iconColor: .blue,
                title: "Welcome to Hawala",
                subtitle: "Your secure multi-chain cryptocurrency wallet",
                features: [
                    OnboardingFeature(icon: "shield.checkered", title: "Self-Custody", description: "You control your keys. No third parties."),
                    OnboardingFeature(icon: "globe", title: "Multi-Chain", description: "Bitcoin, Ethereum, Solana, and more."),
                    OnboardingFeature(icon: "lock.fill", title: "Secure", description: "Industry-standard encryption & security.")
                ]
            ),
            OnboardingPage(
                icon: "key.fill",
                iconColor: .orange,
                title: "Your Recovery Phrase",
                subtitle: "Understanding your 12/24 word seed phrase",
                features: [
                    OnboardingFeature(icon: "doc.text", title: "Write It Down", description: "Store on paper, never digitally."),
                    OnboardingFeature(icon: "eye.slash", title: "Keep It Secret", description: "Never share with anyone, ever."),
                    OnboardingFeature(icon: "arrow.counterclockwise", title: "Recovery", description: "Your only way to restore your wallet.")
                ]
            ),
            OnboardingPage(
                icon: "bitcoinsign.circle.fill",
                iconColor: .orange,
                title: "Manage Your Crypto",
                subtitle: "Send, receive, and track your assets",
                features: [
                    OnboardingFeature(icon: "arrow.up.arrow.down", title: "Send & Receive", description: "Transfer crypto to any address."),
                    OnboardingFeature(icon: "chart.line.uptrend.xyaxis", title: "Track Portfolio", description: "Real-time prices and analytics."),
                    OnboardingFeature(icon: "clock.arrow.circlepath", title: "History", description: "Complete transaction history.")
                ]
            ),
            OnboardingPage(
                icon: "checkmark.shield.fill",
                iconColor: .green,
                title: "Security Best Practices",
                subtitle: "Keep your crypto safe",
                features: [
                    OnboardingFeature(icon: "faceid", title: "Biometric Lock", description: "Enable Face ID / Touch ID for extra security."),
                    OnboardingFeature(icon: "eye", title: "Verify Addresses", description: "Always double-check recipient addresses."),
                    OnboardingFeature(icon: "exclamationmark.triangle", title: "Beware Scams", description: "Never share your seed phrase or private keys.")
                ]
            )
        ]
    }
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: page.icon)
                    .font(.system(size: 44))
                    .foregroundColor(page.iconColor)
            }
            
            // Title and subtitle
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Features
            VStack(spacing: 16) {
                ForEach(page.features) { feature in
                    featureRow(feature)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(.top, 40)
    }
    
    private func featureRow(_ feature: OnboardingPage.OnboardingFeature) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: feature.icon)
                    .font(.body)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Help & Documentation View

struct HelpView: View {
    @State private var searchQuery = ""
    @State private var selectedCategory: HelpCategory = .gettingStarted
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Help & Documentation")
                    .font(.title2.bold())
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search help topics...", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(cardBackground)
            .cornerRadius(10)
            .padding(.horizontal, 20)
            
            Divider()
                .padding(.top, 16)
            
            // Content
            HStack(spacing: 0) {
                // Categories sidebar
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(HelpCategory.allCases, id: \.self) { category in
                        categoryButton(category)
                    }
                }
                .padding(12)
                .frame(width: 200)
                .background(cardBackground)
                
                // Articles
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selectedCategory.rawValue)
                            .font(.headline)
                        
                        ForEach(filteredArticles) { article in
                            HelpArticleRow(article: article)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 700, height: 500)
    }
    
    private func categoryButton(_ category: HelpCategory) -> some View {
        Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.body)
                    .frame(width: 20)
                
                Text(category.rawValue)
                    .font(.subheadline)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedCategory == category ? Color.blue.opacity(0.2) : Color.clear)
            .foregroundColor(selectedCategory == category ? .blue : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var filteredArticles: [HelpArticle] {
        let categoryArticles = HelpArticle.articles.filter { $0.category == selectedCategory }
        
        if searchQuery.isEmpty {
            return categoryArticles
        }
        
        return categoryArticles.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.summary.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}

// MARK: - Help Category

enum HelpCategory: String, CaseIterable {
    case gettingStarted = "Getting Started"
    case wallet = "Wallet Management"
    case transactions = "Transactions"
    case security = "Security"
    case troubleshooting = "Troubleshooting"
    case faq = "FAQ"
    
    var icon: String {
        switch self {
        case .gettingStarted: return "play.circle"
        case .wallet: return "wallet.pass"
        case .transactions: return "arrow.left.arrow.right"
        case .security: return "lock.shield"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .faq: return "questionmark.circle"
        }
    }
}

// MARK: - Help Article

struct HelpArticle: Identifiable {
    let id = UUID()
    let category: HelpCategory
    let title: String
    let summary: String
    let content: String
    
    static var articles: [HelpArticle] {
        [
            // Getting Started
            HelpArticle(
                category: .gettingStarted,
                title: "Creating Your First Wallet",
                summary: "Learn how to set up a new wallet with a recovery phrase",
                content: "Step-by-step guide to creating your first cryptocurrency wallet..."
            ),
            HelpArticle(
                category: .gettingStarted,
                title: "Importing an Existing Wallet",
                summary: "Restore a wallet using your 12/24 word recovery phrase",
                content: "If you already have a wallet, you can import it using your seed phrase..."
            ),
            HelpArticle(
                category: .gettingStarted,
                title: "Understanding Your Dashboard",
                summary: "Navigate the main wallet interface",
                content: "The dashboard shows your total portfolio value and asset breakdown..."
            ),
            
            // Wallet Management
            HelpArticle(
                category: .wallet,
                title: "Multi-Wallet Support",
                summary: "How to manage multiple wallets",
                content: "Hawala supports multiple wallets. You can create separate wallets for different purposes..."
            ),
            HelpArticle(
                category: .wallet,
                title: "Watch-Only Wallets",
                summary: "Monitor addresses without private keys",
                content: "Watch-only wallets let you track balances without exposing your keys..."
            ),
            HelpArticle(
                category: .wallet,
                title: "Backing Up Your Wallet",
                summary: "Best practices for wallet backup",
                content: "Always keep multiple copies of your recovery phrase in secure locations..."
            ),
            
            // Transactions
            HelpArticle(
                category: .transactions,
                title: "Sending Cryptocurrency",
                summary: "How to send crypto to another address",
                content: "To send crypto, select the asset, enter the recipient address and amount..."
            ),
            HelpArticle(
                category: .transactions,
                title: "Receiving Cryptocurrency",
                summary: "How to receive crypto into your wallet",
                content: "To receive crypto, share your address or QR code with the sender..."
            ),
            HelpArticle(
                category: .transactions,
                title: "Understanding Fees",
                summary: "Network fees explained",
                content: "Every blockchain transaction requires a fee paid to miners/validators..."
            ),
            
            // Security
            HelpArticle(
                category: .security,
                title: "Protecting Your Recovery Phrase",
                summary: "Essential security for your seed phrase",
                content: "Your recovery phrase is the master key to your wallet. Never share it..."
            ),
            HelpArticle(
                category: .security,
                title: "Enabling Biometric Lock",
                summary: "Set up Face ID or Touch ID",
                content: "For extra security, enable biometric authentication in Settings..."
            ),
            HelpArticle(
                category: .security,
                title: "Avoiding Scams",
                summary: "Common cryptocurrency scams to avoid",
                content: "Be aware of phishing sites, fake support, and too-good-to-be-true offers..."
            ),
            
            // Troubleshooting
            HelpArticle(
                category: .troubleshooting,
                title: "Transaction Stuck Pending",
                summary: "What to do if your transaction isn't confirming",
                content: "Sometimes transactions can get stuck due to low fees or network congestion..."
            ),
            HelpArticle(
                category: .troubleshooting,
                title: "Balance Not Updating",
                summary: "Why your balance might show incorrectly",
                content: "Balances are fetched from blockchain APIs. Try refreshing or check network status..."
            ),
            HelpArticle(
                category: .troubleshooting,
                title: "App Crashes or Freezes",
                summary: "Steps to resolve app issues",
                content: "If the app is unresponsive, try force-quitting and restarting..."
            ),
            
            // FAQ
            HelpArticle(
                category: .faq,
                title: "Is Hawala open source?",
                summary: "Information about our code transparency",
                content: "Yes, Hawala is open source. You can review the code on GitHub..."
            ),
            HelpArticle(
                category: .faq,
                title: "Which cryptocurrencies are supported?",
                summary: "List of supported blockchains",
                content: "Hawala supports Bitcoin, Ethereum, Solana, Litecoin, XRP, BNB, and Monero..."
            ),
            HelpArticle(
                category: .faq,
                title: "Can I use Hawala on mobile?",
                summary: "Platform availability",
                content: "Hawala is currently available for macOS. iOS and other platforms coming soon..."
            )
        ]
    }
}

// MARK: - Help Article Row

struct HelpArticleRow: View {
    let article: HelpArticle
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        
                        Text(article.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(article.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Contextual Tooltip

struct TooltipView: View {
    let text: String
    let icon: String?
    
    init(_ text: String, icon: String? = "questionmark.circle") {
        self.text = text
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isOnboardingComplete: .constant(false))
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
            .preferredColorScheme(.dark)
    }
}
#endif
