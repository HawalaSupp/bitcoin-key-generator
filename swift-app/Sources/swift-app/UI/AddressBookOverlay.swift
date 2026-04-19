import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Address Book Overlay
// Unified address intelligence hub.
// Six sections: Contacts · Labels · Recent · Tags · Whitelist · Intelligence.
// All wired to ContactsManager, AddressLabelManager,
// AddressIntelligenceManager, and Rust whitelist FFI — zero mock data.
// Monumental. Monochrome. Address-grade.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AddressBookOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil
    var initialTab: ABTab? = nil

    // ── Tab ──
    enum ABTab: String, CaseIterable {
        case contacts     = "CONTACTS"
        case labels       = "LABELS"
        case recent       = "RECENT"
        case tags         = "TAGS"
        case whitelist    = "WHITELIST"
        case intelligence = "INTEL"
        case addresses    = "ADDRESSES"
        case generate     = "GENERATE"
        case stealth      = "STEALTH"
        case validate     = "VALIDATE"
        case privacy      = "PRIVACY"
        case derivation   = "DERIVATION"
    }

    @State private var selectedTab: ABTab = .contacts

    // ── Real managers ──
    @ObservedObject private var contactsMgr  = ContactsManager.shared
    @ObservedObject private var labelMgr     = AddressLabelManager.shared
    @ObservedObject private var addressMgr   = HDAddressManager.shared
    @ObservedObject private var stealthMgr   = StealthAddressManager.shared
    @ObservedObject private var validator     = ChainAddressValidator.shared

    // ── Contacts tab state ──
    @State private var contactSearch: String = ""
    @State private var expandedContactId: UUID? = nil
    @State private var showAddContact = false
    @State private var editingContact: Contact? = nil
    @State private var deleteContactTarget: Contact? = nil
    @State private var showDeleteConfirm = false
    @State private var newContactName = ""
    @State private var newContactAddress = ""
    @State private var newContactChain = "bitcoin"
    @State private var newContactNotes = ""
    @State private var importCount = 0
    @State private var showImportResult = false

    // ── Labels tab state ──
    @State private var labelSearch: String = ""
    @State private var showAddLabel = false
    @State private var editingLabel: AddressLabel? = nil
    @State private var newLabelAddress = ""
    @State private var newLabelName = ""
    @State private var newLabelNotes = ""
    @State private var newLabelTagIds: Set<UUID> = []
    @State private var newLabelFavorite = false

    // ── Tags tab state ──
    @State private var showAddTag = false
    @State private var editingTag: AddressTag? = nil
    @State private var newTagName = ""
    @State private var newTagColor = "blue"
    @State private var newTagIcon = "tag.fill"
    @State private var tagFilterId: UUID? = nil

    // ── Whitelist tab state ──
    @State private var whitelistEntries: [HawalaBridge.WhitelistEntry] = []
    @State private var whitelistLoading = false
    @State private var whitelistError: String? = nil
    @State private var showAddWhitelist = false
    @State private var wlAddress = ""
    @State private var wlLabel = ""
    @State private var wlNotes = ""
    @State private var wlSkipTimeLock = false

    // ── Intelligence tab state ──
    @State private var intelAddress = ""
    @State private var intelResult: AddressAnalysis? = nil
    @State private var intelAnalyzing = false

    // ── Addresses tab state ──
    @State private var addrSelectedChain: CryptoChain = .bitcoin
    @State private var addrSelectedFilter: Int = 0 // 0=All 1=Unused 2=Used 3=Receive 4=Change 5=Labeled
    @State private var addrSearch = ""
    @State private var addrExpandedId: UUID? = nil
    @State private var addrEditLabel = ""
    @State private var addrEditNote = ""
    @State private var addrShowReuseAlert = false
    @State private var addrPendingReuse: ManagedAddress? = nil

    // ── Generate tab state ──
    @State private var genChain: CryptoChain = .bitcoin
    @State private var genIsChange = false
    @State private var genLabel = ""
    @State private var genResult: ManagedAddress? = nil

    // ── Stealth tab state ──
    @State private var stealthChain: StealthChain = .bitcoin
    @State private var stealthExpandedKeyId: UUID? = nil
    @State private var stealthShowGenerate = false
    @State private var stealthGenLabel = ""
    @State private var stealthDeleteTarget: StealthKeyPair? = nil
    @State private var stealthShowDeleteConfirm = false
    @State private var stealthEditLabelTarget: StealthKeyPair? = nil
    @State private var stealthEditLabelText = ""
    @State private var stealthPaymentFilter: Int = 0 // 0=all 1=received 2=sent

    // ── Validate tab state ──
    @State private var valAddress = ""
    @State private var valChain = "ethereum"
    @State private var valResult: ChainAddressValidationResult? = nil
    @State private var valLoading = false

    // ── Privacy tab state ──
    @State private var privGapLimitText = ""
    @State private var privInfoExpanded = false

    // ── Derivation tab state ──
    @State private var derivChain: CryptoChain = .bitcoin
    @State private var derivAccount: Int = 0
    @State private var derivExpandedPath: String? = nil

    // ── Clipboard ──
    @State private var copiedAddress: String? = nil
    @State private var copyTask: Task<Void, Never>? = nil

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered = false
    @State private var backHovered = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardContainer
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            if let tab = initialTab { selectedTab = tab }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                silkPhase = 1
            }
        }
        .alert("Remove Contact", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { deleteContactTarget = nil }
            Button("Remove", role: .destructive) {
                if let c = deleteContactTarget {
                    contactsMgr.deleteContact(c)
                    deleteContactTarget = nil
                }
            }
        } message: {
            Text("This contact will be permanently removed.")
        }
        .alert("Imported \(importCount) address\(importCount == 1 ? "" : "es")", isPresented: $showImportResult) {
            Button("OK") { }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardContainer: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            tabContent
        }
        .frame(width: 700, height: 650)
        .background(cardBg)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var cardBg: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07)
            // silk shimmer
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.015), .clear],
                startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
            )
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1
            )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        HStack {
            if onBackToSettings != nil {
                Button {
                    dismissOverlay()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onBackToSettings?()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Settings")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(backHovered ? 0.7 : 0.3))
                }
                .buttonStyle(.plain)
                .onHover { backHovered = $0 }
            }

            Spacer()

            Text("Address Book")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Button { dismissOverlay() } label: {
                Circle()
                    .fill(Color.white.opacity(closeHovered ? 0.12 : 0.06))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(ABTab.allCases, id: \.self) { tab in
                    if tab == .addresses {
                        // Visual divider between address book and management tabs
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1, height: 16)
                            .padding(.horizontal, 6)
                    }
                    tabButton(tab)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: ABTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.25))
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    selectedTab == tab
                        ? Color.white.opacity(0.08)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                switch selectedTab {
                case .contacts:     contactsTab
                case .labels:       labelsTab
                case .recent:       recentTab
                case .tags:         tagsTab
                case .whitelist:    whitelistTab
                case .intelligence: intelligenceTab
                case .addresses:    addressesTab
                case .generate:     generateTab
                case .stealth:      stealthTab
                case .validate:     validateTab
                case .privacy:      privacyTab
                case .derivation:   derivationTab
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – CONTACTS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var contactsTab: some View {
        VStack(spacing: 12) {
            // Search + actions bar
            HStack(spacing: 8) {
                searchField(text: $contactSearch, placeholder: "Search contacts...")
                actionButton(icon: "plus", tooltip: "Add Contact") {
                    resetContactForm()
                    showAddContact = true
                }
                actionButton(icon: "square.and.arrow.down", tooltip: "Import from History") {
                    importCount = contactsMgr.importAllFromHistory()
                    showImportResult = true
                }
            }

            if showAddContact || editingContact != nil {
                contactFormCard
            }

            let filtered = contactSearch.isEmpty
                ? contactsMgr.contacts
                : contactsMgr.search(contactSearch)

            if filtered.isEmpty {
                emptyState(icon: "person.crop.rectangle.stack", title: "No contacts", subtitle: "Add a contact or import from transaction history.")
            } else {
                ForEach(filtered) { contact in
                    contactRow(contact)
                }
            }
        }
    }

    private func contactRow(_ contact: Contact) -> some View {
        let expanded = expandedContactId == contact.id
        let risk = AddressIntelligenceManager.shared.quickRiskCheck(contact.address)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Monogram
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(contact.name.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    HStack(spacing: 4) {
                        Text(contact.shortAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        chainBadge(contact.chainDisplayName)
                    }
                }

                Spacer()

                riskBadge(risk)

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedContactId = expanded ? nil : contact.id
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    // All addresses
                    ForEach(contact.addresses) { addr in
                        HStack(spacing: 6) {
                            chainBadge(addr.chainDisplayName)
                            Text(addr.shortAddress)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            if let label = addr.label {
                                Text(label)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.25))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(3)
                            }
                            Spacer()
                            copyButton(addr.address)
                        }
                    }

                    if let notes = contact.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        smallButton("Edit") {
                            populateContactForm(from: contact)
                            editingContact = contact
                            showAddContact = true
                        }
                        smallButton("Delete") {
                            deleteContactTarget = contact
                            showDeleteConfirm = true
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 10)
                .padding(.leading, 42)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.white.opacity(expanded ? 0.04 : 0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ── Contact Form ──

    private var contactFormCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(editingContact != nil ? "Edit Contact" : "New Contact")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    showAddContact = false
                    editingContact = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            formField("Name", text: $newContactName, placeholder: "Alice")
            formField("Address", text: $newContactAddress, placeholder: "bc1q...", monospaced: true)
            chainPicker(selection: $newContactChain)
            formField("Notes", text: $newContactNotes, placeholder: "Optional notes...")

            HStack {
                Spacer()
                Button {
                    saveContact()
                } label: {
                    Text(editingContact != nil ? "Update" : "Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newContactName.isEmpty || newContactAddress.isEmpty)
                .opacity(newContactName.isEmpty || newContactAddress.isEmpty ? 0.3 : 1)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – LABELS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var labelsTab: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                searchField(text: $labelSearch, placeholder: "Search labels...")
                actionButton(icon: "plus", tooltip: "Add Label") {
                    resetLabelForm()
                    showAddLabel = true
                }
            }

            if showAddLabel || editingLabel != nil {
                labelFormCard
            }

            let filtered = labelSearch.isEmpty
                ? labelMgr.labels
                : labelMgr.search(labelSearch)

            if filtered.isEmpty {
                emptyState(icon: "tag", title: "No labels", subtitle: "Label addresses to identify them quickly.")
            } else {
                ForEach(filtered) { label in
                    labelRow(label)
                }
            }
        }
    }

    private func labelRow(_ label: AddressLabel) -> some View {
        let risk = AddressIntelligenceManager.shared.quickRiskCheck(label.address)
        let tags = labelMgr.tags(for: label.address)

        return HStack(spacing: 10) {
            // Favorite star
            Button {
                labelMgr.toggleFavorite(for: label.address)
            } label: {
                Image(systemName: label.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(label.isFavorite ? .yellow : .white.opacity(0.15))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    riskBadge(risk)
                }
                HStack(spacing: 4) {
                    Text(truncateAddress(label.address))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    ForEach(tags) { tag in
                        tagPill(tag)
                    }
                }
            }

            Spacer()

            copyButton(label.address)

            Button {
                populateLabelForm(from: label)
                editingLabel = label
                showAddLabel = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)

            Button {
                labelMgr.removeLabel(for: label.address)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ── Label Form ──

    private var labelFormCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(editingLabel != nil ? "Edit Label" : "New Label")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    showAddLabel = false
                    editingLabel = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            formField("Address", text: $newLabelAddress, placeholder: "0x...", monospaced: true)
            formField("Name", text: $newLabelName, placeholder: "My Exchange")
            formField("Notes", text: $newLabelNotes, placeholder: "Optional notes...")

            // Tag selection
            if !labelMgr.tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                    FlowLayout(spacing: 6) {
                        ForEach(labelMgr.tags) { tag in
                            Button {
                                if newLabelTagIds.contains(tag.id) {
                                    newLabelTagIds.remove(tag.id)
                                } else {
                                    newLabelTagIds.insert(tag.id)
                                }
                            } label: {
                                tagPill(tag, selected: newLabelTagIds.contains(tag.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Toggle(isOn: $newLabelFavorite) {
                    Text("Favorite")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                Button {
                    saveLabel()
                } label: {
                    Text(editingLabel != nil ? "Update" : "Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newLabelAddress.isEmpty || newLabelName.isEmpty)
                .opacity(newLabelAddress.isEmpty || newLabelName.isEmpty ? 0.3 : 1)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – RECENT TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var recentTab: some View {
        let recents = AddressIntelligenceManager.shared.getRecentRecipients(limit: 30)

        return VStack(spacing: 12) {
            if recents.isEmpty {
                emptyState(icon: "clock.arrow.circlepath", title: "No recent recipients", subtitle: "Addresses you send to will appear here.")
            } else {
                ForEach(Array(recents.enumerated()), id: \.offset) { _, entry in
                    recentRow(address: entry.address, chainId: entry.chainId, count: entry.count, lastDate: entry.lastDate)
                }
            }
        }
    }

    private func recentRow(address: String, chainId: String, count: Int, lastDate: Date) -> some View {
        let risk = AddressIntelligenceManager.shared.quickRiskCheck(address, chainId: chainId)
        let isFirst = AddressIntelligenceManager.shared.isFirstTimeSend(to: address, chainId: chainId)
        let hasSaved = contactsMgr.hasContact(forAddress: address, chainId: chainId)
        let existingLabel = labelMgr.label(for: address)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let lbl = existingLabel {
                        Text(lbl.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Text(truncateAddress(address))
                        .font(.system(size: existingLabel != nil ? 11 : 13, design: .monospaced))
                        .foregroundColor(.white.opacity(existingLabel != nil ? 0.35 : 0.6))
                    riskBadge(risk)
                }
                HStack(spacing: 8) {
                    chainBadge(chainDisplayName(chainId))
                    Text("\(count) send\(count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                    Text(relativeDate(lastDate))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                    if isFirst {
                        Text("FIRST")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            if !hasSaved {
                Button {
                    contactsMgr.importFromHistory(address: address, chainId: chainId)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Save as contact")
            } else {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.15))
            }

            copyButton(address)
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – TAGS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tagsTab: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                actionButton(icon: "plus", tooltip: "New Tag") {
                    resetTagForm()
                    showAddTag = true
                }
            }

            if showAddTag || editingTag != nil {
                tagFormCard
            }

            if tagFilterId != nil {
                tagFilterView
            }

            let tags = labelMgr.tags
            if tags.isEmpty {
                emptyState(icon: "tag", title: "No tags", subtitle: "Create tags to categorize addresses.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(tags) { tag in
                        tagCard(tag)
                    }
                }
            }
        }
    }

    private func tagCard(_ tag: AddressTag) -> some View {
        let count = labelMgr.addresses(with: tag.id).count

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                if let icon = tag.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundColor(tag.swiftUIColor)
                }
                Text(tag.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            HStack {
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text("\(count) address\(count == 1 ? "" : "es")")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            tagFilterId = tagFilterId == tag.id ? nil : tag.id
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    Button {
                        populateTagForm(from: tag)
                        editingTag = tag
                        showAddTag = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    Button {
                        labelMgr.deleteTag(tag.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(tag.swiftUIColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tag.swiftUIColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var tagFilterView: some View {
        let tagId = tagFilterId!
        let addresses = labelMgr.addresses(with: tagId)
        let tagName = labelMgr.tags.first(where: { $0.id == tagId })?.name ?? "Tag"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Addresses tagged \"\(tagName)\"")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Button {
                    withAnimation { tagFilterId = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            if addresses.isEmpty {
                Text("No addresses with this tag.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            } else {
                ForEach(addresses) { label in
                    HStack(spacing: 6) {
                        Text(label.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Text(truncateAddress(label.address))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        copyButton(label.address)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // ── Tag Form ──

    private var tagFormCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(editingTag != nil ? "Edit Tag" : "New Tag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button { showAddTag = false; editingTag = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            formField("Name", text: $newTagName, placeholder: "Tag name")

            // Color picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                HStack(spacing: 6) {
                    ForEach(tagColors, id: \.self) { color in
                        Button {
                            newTagColor = color
                        } label: {
                            Circle()
                                .fill(colorFromName(color))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(newTagColor == color ? 0.6 : 0), lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                HStack(spacing: 8) {
                    ForEach(tagIcons, id: \.self) { icon in
                        Button {
                            newTagIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .foregroundColor(newTagIcon == icon ? .white.opacity(0.8) : .white.opacity(0.2))
                                .frame(width: 28, height: 28)
                                .background(newTagIcon == icon ? Color.white.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button { saveTag() } label: {
                    Text(editingTag != nil ? "Update" : "Create")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newTagName.isEmpty)
                .opacity(newTagName.isEmpty ? 0.3 : 1)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – WHITELIST TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var whitelistTab: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Trusted Whitelist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                actionButton(icon: "arrow.clockwise", tooltip: "Refresh") { loadWhitelist() }
                actionButton(icon: "plus", tooltip: "Add to Whitelist") { showAddWhitelist = true }
            }

            if showAddWhitelist {
                whitelistFormCard
            }

            if whitelistLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.3)))
                    .padding(20)
            } else if let err = whitelistError {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 20))
                        .foregroundColor(.orange.opacity(0.5))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            } else if whitelistEntries.isEmpty {
                emptyState(icon: "checkmark.shield", title: "No whitelisted addresses", subtitle: "Whitelisted addresses bypass spending confirmations after the time-lock period.")
            } else {
                ForEach(Array(whitelistEntries.enumerated()), id: \.offset) { _, entry in
                    whitelistRow(entry)
                }
            }
        }
        .onAppear { loadWhitelist() }
    }

    private func whitelistRow(_ entry: HawalaBridge.WhitelistEntry) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(entry.isActive ? Color.green.opacity(0.25) : Color.orange.opacity(0.25))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let label = entry.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(truncateAddress(entry.address))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                HStack(spacing: 6) {
                    Text(entry.isActive ? "Active" : "Pending")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(entry.isActive ? .green.opacity(0.6) : .orange.opacity(0.6))
                    if !entry.chains.isEmpty {
                        Text(entry.chains.joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    if !entry.isActive {
                        let remaining = Int(entry.activeAt) - Int(Date().timeIntervalSince1970)
                        if remaining > 0 {
                            Text(formatDuration(remaining))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.5))
                        }
                    }
                }
            }

            Spacer()

            Button {
                removeWhitelistEntry(entry.address)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var whitelistFormCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Add to Whitelist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button { showAddWhitelist = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            formField("Address", text: $wlAddress, placeholder: "0x... or bc1...", monospaced: true)
            formField("Label", text: $wlLabel, placeholder: "Optional label")
            formField("Notes", text: $wlNotes, placeholder: "Optional notes")

            HStack {
                Toggle(isOn: $wlSkipTimeLock) {
                    Text("Skip time-lock (24h)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                Button { addToWhitelist() } label: {
                    Text("Whitelist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(wlAddress.isEmpty)
                .opacity(wlAddress.isEmpty ? 0.3 : 1)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – INTELLIGENCE TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var intelligenceTab: some View {
        VStack(spacing: 14) {
            // Address input
            HStack(spacing: 8) {
                searchField(text: $intelAddress, placeholder: "Enter address to analyze...")
                Button {
                    analyzeIntelAddress()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(intelAddress.isEmpty || intelAnalyzing)
            }

            if intelAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.3)))
                        .scaleEffect(0.7)
                    Text("Analyzing...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(20)
            } else if let result = intelResult {
                analysisResultView(result)
            } else {
                intelPlaceholder
            }
        }
    }

    private var intelPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.08))
            Text("Address Intelligence")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
            Text("Analyze any address for risk assessment, validation, known services, and transaction history.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 6) {
                intelFeatureRow(icon: "shield.checkered", text: "5-level risk assessment")
                intelFeatureRow(icon: "building.columns", text: "Known exchange & DeFi detection")
                intelFeatureRow(icon: "checkmark.circle", text: "Format & checksum validation")
                intelFeatureRow(icon: "exclamationmark.shield", text: "Scam & sanctions screening")
                intelFeatureRow(icon: "clock", text: "Transaction history lookup")
            }
            .padding(.top, 8)
        }
        .padding(20)
    }

    private func intelFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private func analysisResultView(_ analysis: AddressAnalysis) -> some View {
        VStack(spacing: 12) {
            // Risk header
            HStack(spacing: 10) {
                Image(systemName: analysis.riskLevel.icon)
                    .font(.system(size: 22))
                    .foregroundColor(riskColor(analysis.riskLevel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.riskLevel.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(riskColor(analysis.riskLevel))
                    Text(analysis.blockchain.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(analysis.isValid ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(analysis.isValid ? "Valid" : "Invalid")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    if let chk = analysis.checksumValid {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(chk ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(chk ? "Checksum OK" : "Checksum fail")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }
            .padding(14)
            .background(riskColor(analysis.riskLevel).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(riskColor(analysis.riskLevel).opacity(0.15), lineWidth: 1)
            )

            // Known service
            if let service = analysis.knownService {
                HStack(spacing: 8) {
                    Image(systemName: service.type.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        Text(service.type.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                    if service.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green.opacity(0.5))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Risk factors
            if !analysis.riskFactors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Risk Factors")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    ForEach(analysis.riskFactors) { factor in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: factor.level.icon)
                                .font(.system(size: 11))
                                .foregroundColor(riskColor(factor.level))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(factor.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(factor.description)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Send history
            if analysis.previouslySentTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Sent \(analysis.previouslySentCount) time\(analysis.previouslySentCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    if let lastDate = analysis.lastSentDate {
                        Text("· Last: \(relativeDate(lastDate))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.25))
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Flags
            if analysis.isScamReported || analysis.isSanctioned {
                HStack(spacing: 12) {
                    if analysis.isScamReported {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.red)
                            Text("SCAM REPORTED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                    }
                    if analysis.isSanctioned {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.red)
                            Text("SANCTIONED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – ADDRESSES TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private let addrFilterNames = ["All", "Unused", "Used", "Receive", "Change", "Labeled"]

    private var addressesTab: some View {
        VStack(spacing: 12) {
            // Chain selector pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CryptoChain.allCases, id: \.self) { chain in
                        Button {
                            addrSelectedChain = chain
                            addrExpandedId = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chain.icon)
                                    .font(.system(size: 10))
                                Text(chain.rawValue)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(addrSelectedChain == chain ? .white.opacity(0.9) : .white.opacity(0.3))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(addrSelectedChain == chain ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Filter pills
            HStack(spacing: 4) {
                ForEach(Array(addrFilterNames.enumerated()), id: \.offset) { idx, name in
                    Button {
                        addrSelectedFilter = idx
                    } label: {
                        Text(name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(addrSelectedFilter == idx ? .white.opacity(0.8) : .white.opacity(0.25))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(addrSelectedFilter == idx ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Statistics bar
            let stats = addressMgr.getStatistics(for: addrSelectedChain)
            HStack(spacing: 16) {
                addrStatBadge("Total", "\(stats.totalAddresses)", .white.opacity(0.4))
                addrStatBadge("Used", "\(stats.usedAddresses)", .orange)
                addrStatBadge("Unused", "\(stats.unusedAddresses)", .green)
                if stats.multiUseAddresses > 0 {
                    addrStatBadge("Multi-use", "\(stats.multiUseAddresses)", .red)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Search
            searchField(text: $addrSearch, placeholder: "Search addresses or labels...")

            // Address list
            let addrs = filteredManagedAddresses
            if addrs.isEmpty {
                emptyState(icon: "tray", title: "No addresses", subtitle: addrSelectedChain.supportsMultipleAddresses ? "Generate a new address from the GENERATE tab." : "\(addrSelectedChain.name) uses a single address.")
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(addrs) { addr in
                        managedAddressRow(addr)
                    }
                }
            }
        }
        .alert("Address Reuse Warning", isPresented: $addrShowReuseAlert) {
            Button("Generate New") {
                _ = addressMgr.getNextReceiveAddress(chain: addrSelectedChain, forceNew: true)
            }
            Button("View Anyway", role: .destructive) {
                if let a = addrPendingReuse { addrExpandedId = a.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This address has been used before. Reusing reduces privacy and allows transaction linking.")
        }
    }

    private func addrStatBadge(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    private var filteredManagedAddresses: [ManagedAddress] {
        var addrs = addressMgr.getAddresses(for: addrSelectedChain)
        switch addrSelectedFilter {
        case 1: addrs = addrs.filter { !$0.isUsed }
        case 2: addrs = addrs.filter { $0.isUsed }
        case 3: addrs = addrs.filter { !$0.isChange }
        case 4: addrs = addrs.filter { $0.isChange }
        case 5: addrs = addrs.filter { !$0.label.isEmpty }
        default: break
        }
        if !addrSearch.isEmpty {
            addrs = addrs.filter {
                $0.address.localizedCaseInsensitiveContains(addrSearch) ||
                $0.label.localizedCaseInsensitiveContains(addrSearch)
            }
        }
        return addrs.sorted { $0.index > $1.index }
    }

    private func managedAddressRow(_ addr: ManagedAddress) -> some View {
        let expanded = addrExpandedId == addr.id
        let hasWarning = addr.isUsed && addr.useCount > 1 && addressMgr.showReuseWarnings

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(addr.isUsed ? (addr.useCount > 1 ? Color.orange : Color.green) : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(addr.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        if addr.isChange {
                            Text("CHANGE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(3)
                        }
                        if hasWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(addr.address.isEmpty ? "Pending..." : PrivacyManager.shared.redactAddress(addr.shortAddress))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                        Text("m/\(addr.index)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.15))
                    }
                }

                Spacer()

                if addr.useCount > 0 {
                    Text("\(addr.useCount) tx")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                }

                copyButton(addr.address)

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.15))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if addr.isUsed && addressMgr.showReuseWarnings && !expanded {
                    addrPendingReuse = addr
                    addrShowReuseAlert = true
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        addrExpandedId = expanded ? nil : addr.id
                        if !expanded {
                            addrEditLabel = addr.label
                            addrEditNote = addr.note
                        }
                    }
                }
            }

            // Inline detail panel
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Full address
                    HStack {
                        Text(addr.address.isEmpty ? "Pending derivation..." : addr.address)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .textSelection(.enabled)
                        Spacer()
                        copyButton(addr.address)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Derivation path
                    HStack {
                        Text("Derivation")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        Text(addr.derivationPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Text(addr.isChange ? "Change" : "Receive")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(addr.isChange ? .orange.opacity(0.6) : .green.opacity(0.6))
                    }

                    // Label editor
                    HStack(spacing: 8) {
                        Text("Label")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 40, alignment: .leading)
                        TextField("Add label...", text: $addrEditLabel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .onChange(of: addrEditLabel) { val in
                                addressMgr.setLabel(val, for: addr.address)
                            }
                    }

                    // Notes editor
                    HStack(spacing: 8) {
                        Text("Notes")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 40, alignment: .leading)
                        TextField("Add notes...", text: $addrEditNote)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .onChange(of: addrEditNote) { val in
                                addressMgr.setNote(val, for: addr.address)
                            }
                    }

                    // Usage
                    if addr.isUsed {
                        HStack {
                            Text("Transactions: \(addr.useCount)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            if let lastUsed = addr.lastUsedAt {
                                Text("Last: \(relativeDate(lastUsed))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            Text("Created: \(relativeDate(addr.createdAt))")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.2))
                        }
                    }

                    // Privacy warning for multi-use
                    if addr.useCount > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("Used \(addr.useCount) times — consider generating a new address for better privacy.")
                                .font(.system(size: 10))
                                .foregroundColor(.orange.opacity(0.7))
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 15)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.white.opacity(expanded ? 0.04 : 0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – GENERATE TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var generateTab: some View {
        VStack(spacing: 16) {
            // Chain selector pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CryptoChain.allCases, id: \.self) { chain in
                        Button {
                            genChain = chain
                            genResult = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chain.icon)
                                    .font(.system(size: 10))
                                Text(chain.name)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(genChain == chain ? .white.opacity(0.9) : .white.opacity(0.3))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(genChain == chain ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !genChain.supportsMultipleAddresses {
                emptyState(icon: "info.circle", title: "Single address chain", subtitle: "\(genChain.name) uses a single address and doesn't support HD derivation.")
            } else {
                // Type picker
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { isChange in
                        Button {
                            genIsChange = isChange
                        } label: {
                            Text(isChange ? "Change" : "Receive")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(genIsChange == isChange ? .white.opacity(0.85) : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(genIsChange == isChange ? Color.white.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )

                // Label field
                formField("Label", text: $genLabel, placeholder: "Optional label (e.g., Savings)")

                // Generate button
                Button {
                    generateNewAddress()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Generate \(genIsChange ? "Change" : "Receive") Address")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Result
                if let result = genResult {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green.opacity(0.6))
                            Text("Address Generated")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.green.opacity(0.7))
                            Spacer()
                        }

                        HStack {
                            Text(result.address.isEmpty ? "Generating..." : result.shortAddress)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            copyButton(result.address)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        HStack {
                            Text("Path: \(result.derivationPath)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            Text("Index: \(result.index)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.green.opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – STEALTH TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var stealthTab: some View {
        VStack(spacing: 12) {
            stealthChainBar
            stealthStatsBar
            stealthScanProgress
            stealthGenerateForm
            stealthKeysList
            stealthPaymentsSection
        }
        .alert("Delete Key Pair", isPresented: $stealthShowDeleteConfirm) {
            Button("Cancel", role: .cancel) { stealthDeleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let kp = stealthDeleteTarget {
                    try? stealthMgr.deleteKeyPair(kp)
                    stealthDeleteTarget = nil
                }
            }
        } message: {
            Text("This will permanently remove this stealth key pair. Any unspent funds may become inaccessible.")
        }
    }

    @ViewBuilder
    private var stealthChainBar: some View {
        HStack(spacing: 6) {
            ForEach(StealthChain.allCases, id: \.self) { chain in
                Button {
                    stealthChain = chain
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: chain.icon)
                            .font(.system(size: 10))
                        Text(chain.displayName)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(stealthChain == chain ? .white.opacity(0.9) : .white.opacity(0.3))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(stealthChain == chain ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            actionButton(icon: "plus", tooltip: "Generate Key Pair") {
                stealthShowGenerate = true
                stealthGenLabel = ""
            }
        }
    }

    @ViewBuilder
    private var stealthStatsBar: some View {
        let stats = stealthMgr.getStatistics(for: stealthChain)
        HStack(spacing: 16) {
            addrStatBadge("Keys", "\(stats.keyPairCount)", .white.opacity(0.4))
            addrStatBadge("Received", "\(stats.receivedPayments)", .green)
            addrStatBadge("Unspent", "\(stats.unspentPayments)", .cyan)
            addrStatBadge("Sent", "\(stats.outgoingPayments)", .orange)
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var stealthScanProgress: some View {
        if let progress = stealthMgr.scanProgress[stealthChain], progress.isScanning {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.3)))
                    .scaleEffect(0.6)
                Text("Scanning... \(progress.progressPercentage)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                Text("\(progress.paymentsFound) found")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.5))
                Spacer()
            }
            .padding(8)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private var stealthGenerateForm: some View {
        if stealthShowGenerate {
            VStack(spacing: 10) {
                HStack {
                    Text("Generate Key Pair")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Button { stealthShowGenerate = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                formField("Label", text: $stealthGenLabel, placeholder: "Optional label")
                HStack {
                    Spacer()
                    Button {
                        generateStealthKeyPair()
                    } label: {
                        HStack(spacing: 4) {
                            if stealthMgr.isGeneratingKeys {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5))).scaleEffect(0.6)
                            }
                            Text("Generate")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(stealthMgr.isGeneratingKeys)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var stealthKeysList: some View {
        let chainKeys = stealthMgr.keyPairs.filter { $0.chain == stealthChain }
        if chainKeys.isEmpty && !stealthShowGenerate {
            emptyState(icon: "key.horizontal", title: "No stealth keys", subtitle: "Generate a key pair to receive stealth payments on \(stealthChain.displayName).")
        } else {
            ForEach(chainKeys) { kp in
                stealthKeyRow(kp)
            }
        }
    }

    @ViewBuilder
    private var stealthPaymentsSection: some View {
        if !stealthMgr.receivedPayments.isEmpty || !stealthMgr.outgoingPayments.isEmpty {
            stealthPaymentFilterBar
            stealthReceivedPayments
            stealthOutgoingPayments
        }
    }

    @ViewBuilder
    private var stealthPaymentFilterBar: some View {
        HStack(spacing: 4) {
            ForEach(["All", "Received", "Sent"], id: \.self) { label in
                let idx = label == "All" ? 0 : (label == "Received" ? 1 : 2)
                Button {
                    stealthPaymentFilter = idx
                } label: {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(stealthPaymentFilter == idx ? .white.opacity(0.8) : .white.opacity(0.25))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stealthPaymentFilter == idx ? Color.white.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var stealthReceivedPayments: some View {
        if stealthPaymentFilter != 2 {
            let received = stealthMgr.receivedPayments.filter { $0.chain == stealthChain }
            ForEach(received) { payment in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.left")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(truncateAddress(payment.oneTimeAddress))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        HStack(spacing: 6) {
                            Text(payment.isSpent ? "Spent" : "Unspent")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(payment.isSpent ? .white.opacity(0.25) : .green.opacity(0.6))
                            Text(relativeDate(payment.detectedAt))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.2))
                        }
                    }
                    Spacer()
                    Text("\(payment.amount) sat")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(10)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var stealthOutgoingPayments: some View {
        if stealthPaymentFilter != 1 {
            let outgoing = stealthMgr.outgoingPayments.filter { $0.chain == stealthChain }
            ForEach(outgoing) { payment in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(.orange.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(truncateAddress(payment.oneTimeAddress))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        HStack(spacing: 6) {
                            Text(payment.status.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(payment.status == .confirmed ? .green.opacity(0.6) : .orange.opacity(0.6))
                            Text(relativeDate(payment.createdAt))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.2))
                        }
                    }
                    Spacer()
                    Text("\(payment.amount) sat")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(10)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func stealthKeyRow(_ kp: StealthKeyPair) -> some View {
        let expanded = stealthExpandedKeyId == kp.id

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(kp.isDefault ? .cyan.opacity(0.6) : .white.opacity(0.2))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let label = kp.label, !label.isEmpty {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        if kp.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                    Text(truncateAddress(kp.metaAddress))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                Text(relativeDate(kp.createdAt))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.15))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    stealthExpandedKeyId = expanded ? nil : kp.id
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Meta address
                    HStack {
                        Text(kp.metaAddress)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .textSelection(.enabled)
                        Spacer()
                        copyButton(kp.metaAddress)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    HStack(spacing: 8) {
                        if !kp.isDefault {
                            smallButton("Set Default") {
                                stealthMgr.setDefaultKeyPair(kp)
                            }
                        }
                        smallButton("Edit Label") {
                            stealthEditLabelTarget = kp
                            stealthEditLabelText = kp.label ?? ""
                        }
                        smallButton("Delete") {
                            stealthDeleteTarget = kp
                            stealthShowDeleteConfirm = true
                        }
                    }

                    // Inline label editor
                    if stealthEditLabelTarget?.id == kp.id {
                        HStack(spacing: 6) {
                            TextField("Label", text: $stealthEditLabelText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(6)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Button {
                                stealthMgr.updateKeyPairLabel(kp, label: stealthEditLabelText.isEmpty ? nil : stealthEditLabelText)
                                stealthEditLabelTarget = nil
                            } label: {
                                Text("Save")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 19)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.white.opacity(expanded ? 0.04 : 0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – VALIDATE TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var validateTab: some View {
        VStack(spacing: 14) {
            // Chain picker
            HStack(spacing: 6) {
                let chains = ["bitcoin", "ethereum", "solana", "xrp", "litecoin"]
                ForEach(chains, id: \.self) { chain in
                    Button {
                        valChain = chain
                        valResult = nil
                    } label: {
                        Text(chain.capitalized)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(valChain == chain ? .white.opacity(0.9) : .white.opacity(0.3))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(valChain == chain ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Address input
            VStack(alignment: .leading, spacing: 6) {
                Text("Address or Domain")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                TextField("Enter address, .eth, .sol, or .crypto domain...", text: $valAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            }

            // Validate button
            HStack {
                Button {
                    validateAddress()
                } label: {
                    HStack(spacing: 6) {
                        if validator.isResolving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                                .scaleEffect(0.6)
                        }
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 11))
                        Text("Validate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(valAddress.trimmingCharacters(in: .whitespaces).isEmpty || validator.isResolving)

                if valResult != nil {
                    Button {
                        valAddress = ""
                        valResult = nil
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Result panel
            if let result = valResult {
                VStack(alignment: .leading, spacing: 10) {
                    switch result {
                    case .valid(let normalized, let displayName, let checksum):
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Valid Address")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.green.opacity(0.8))
                                if let name = displayName {
                                    Text("Resolved: \(name)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            Spacer()
                        }

                        // Normalized address
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Normalized")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.25))
                            HStack {
                                Text(normalized)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .textSelection(.enabled)
                                Spacer()
                                copyButton(normalized)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        // Checksum address (if different)
                        if let cs = checksum, cs != normalized {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Checksum")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.25))
                                HStack {
                                    Text(cs)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                        .textSelection(.enabled)
                                    Spacer()
                                    copyButton(cs)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                    case .invalid(let error):
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invalid Address")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.red.opacity(0.8))
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // Quick info
            if valResult == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Supported Formats")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                    Group {
                        infoRow("Bitcoin", "P2PKH, P2SH, Bech32 (bc1), Taproot (bc1p)")
                        infoRow("Ethereum", "0x addresses with EIP-55 checksum")
                        infoRow("Solana", "Base58 (32-44 chars)")
                        infoRow("XRP", "r-addresses with Base58Check")
                        infoRow("Domains", ".eth, .sol, .crypto, .x, .wallet")
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func infoRow(_ chain: String, _ formats: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(chain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 60, alignment: .leading)
            Text(formats)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – PRIVACY TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var privacyTab: some View {
        VStack(spacing: 16) {
            // Gap limit
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "number.square")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Gap Limit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("Current: \(addressMgr.gapLimit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                Text("Number of consecutive unused addresses before the wallet stops scanning. Higher values improve recovery but slow scanning.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))

                HStack(spacing: 8) {
                    ForEach([5, 10, 20, 50, 100], id: \.self) { value in
                        Button {
                            addressMgr.setGapLimit(value)
                            privGapLimitText = "\(value)"
                        } label: {
                            Text("\(value)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(addressMgr.gapLimit == value ? .white.opacity(0.9) : .white.opacity(0.3))
                                .frame(width: 36, height: 28)
                                .background(addressMgr.gapLimit == value ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()

                    // Custom entry
                    HStack(spacing: 4) {
                        TextField("Custom", text: $privGapLimitText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 48)
                            .padding(4)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Button {
                            if let val = Int(privGapLimitText), val >= 1, val <= 200 {
                                addressMgr.setGapLimit(val)
                            }
                        } label: {
                            Text("Set")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )

            // Auto-generate toggle
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $addressMgr.autoGenerateNewAddress) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Generate Addresses")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Automatically create a new receive address after each transaction to improve privacy.")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.white.opacity(0.3))
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )

            // Reuse warnings toggle
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $addressMgr.showReuseWarnings) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Address Reuse Warnings")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Show a warning when sharing an address that has already been used in a transaction.")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.white.opacity(0.3))
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )

            // Education
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.2))
                    Text("HD Wallet Privacy")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                }
                Text("Your wallet uses Hierarchical Deterministic (HD) key derivation (BIP-32/44/84) to generate a unique address for each transaction. This prevents blockchain observers from linking your transactions together. For maximum privacy, always use a fresh address and enable auto-generation.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                    .lineSpacing(3)
            }
            .padding(14)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – DERIVATION TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var derivationTab: some View {
        VStack(spacing: 14) {
            derivChainSelector
            derivAccountSelector
            derivPathsTable
            derivPathLegend
        }
    }

    @ViewBuilder
    private var derivChainSelector: some View {
        HStack(spacing: 6) {
            ForEach(CryptoChain.allCases.filter { [.bitcoin, .ethereum, .litecoin, .solana, .xrp].contains($0) }, id: \.self) { chain in
                Button {
                    derivChain = chain
                } label: {
                    Text(chain.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(derivChain == chain ? .white.opacity(0.9) : .white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(derivChain == chain ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var derivAccountSelector: some View {
        HStack(spacing: 8) {
            Text("Account")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
            ForEach(0..<5, id: \.self) { acct in
                Button {
                    derivAccount = acct
                } label: {
                    Text("\(acct)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(derivAccount == acct ? .white.opacity(0.9) : .white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .background(derivAccount == acct ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var derivPathsTable: some View {
        let bipInfo = derivationInfo(for: derivChain)
        VStack(alignment: .leading, spacing: 0) {
            derivPathsHeader
            ForEach(bipInfo, id: \.path) { info in
                derivPathRow(info)
                Divider().background(Color.white.opacity(0.04))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var derivPathsHeader: some View {
        HStack {
            Text("BIP Standard")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 80, alignment: .leading)
            Text("Purpose")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 120, alignment: .leading)
            Text("Path (Account \(derivAccount))")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
    }

    private func derivPathRow(_ info: DerivationPathInfo) -> some View {
        let expanded = derivExpandedPath == info.path
        return VStack(spacing: 0) {
            HStack {
                Text(info.standard)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 80, alignment: .leading)
                Text(info.purpose)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 120, alignment: .leading)
                Text(info.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(info.isActive ? .cyan.opacity(0.6) : .white.opacity(0.4))
                    .textSelection(.enabled)
                Spacer()
                if info.isActive {
                    Text("ACTIVE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.1))
                        .cornerRadius(3)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    derivExpandedPath = expanded ? nil : info.path
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                        .lineSpacing(3)

                    HStack(spacing: 4) {
                        Text("Full path:")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.2))
                        Text(info.path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .textSelection(.enabled)
                        copyButton(info.path)
                    }

                    let addrs = addressMgr.addresses.filter {
                        $0.chain == derivChain && $0.derivationPath.hasPrefix(info.pathPrefix)
                    }
                    if !addrs.isEmpty {
                        Text("\(addrs.count) derived address\(addrs.count == 1 ? "" : "es")")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.2))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(expanded ? Color.white.opacity(0.02) : Color.clear)
    }

    @ViewBuilder
    private var derivPathLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Path Components")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
            Group {
                pathLegendRow("m", "Master key (seed)")
                pathLegendRow("purpose'", "BIP standard (44/49/84/86)")
                pathLegendRow("coin_type'", "Cryptocurrency (0=BTC, 60=ETH, 2=LTC)")
                pathLegendRow("account'", "Account index (hardened)")
                pathLegendRow("change", "0 = receive, 1 = change")
                pathLegendRow("index", "Address index")
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct DerivationPathInfo {
        let standard: String
        let purpose: String
        let path: String
        let pathPrefix: String
        let isActive: Bool
        let description: String
    }

    private func derivationInfo(for chain: CryptoChain) -> [DerivationPathInfo] {
        switch chain {
        case .bitcoin:
            return [
                DerivationPathInfo(standard: "BIP-84", purpose: "Native SegWit", path: "m/84'/0'/\(derivAccount)'/0/0", pathPrefix: "m/84'/0'/\(derivAccount)'", isActive: true, description: "Native SegWit addresses (bc1q...). Current standard for Bitcoin — lower transaction fees and better efficiency."),
                DerivationPathInfo(standard: "BIP-86", purpose: "Taproot", path: "m/86'/0'/\(derivAccount)'/0/0", pathPrefix: "m/86'/0'/\(derivAccount)'", isActive: false, description: "Taproot addresses (bc1p...). Newest standard supporting advanced scripting and improved privacy."),
                DerivationPathInfo(standard: "BIP-49", purpose: "Nested SegWit", path: "m/49'/0'/\(derivAccount)'/0/0", pathPrefix: "m/49'/0'/\(derivAccount)'", isActive: false, description: "Nested SegWit addresses (3...). Transitional format — compatible with older wallets."),
                DerivationPathInfo(standard: "BIP-44", purpose: "Legacy", path: "m/44'/0'/\(derivAccount)'/0/0", pathPrefix: "m/44'/0'/\(derivAccount)'", isActive: false, description: "Legacy addresses (1...). Original Bitcoin address format — highest fees but universal compatibility."),
            ]
        case .bitcoinTestnet:
            return [
                DerivationPathInfo(standard: "BIP-84", purpose: "Testnet SegWit", path: "m/84'/1'/\(derivAccount)'/0/0", pathPrefix: "m/84'/1'/\(derivAccount)'", isActive: true, description: "Testnet native SegWit addresses (tb1q...)."),
            ]
        case .ethereum, .polygon, .arbitrum, .optimism, .base:
            return [
                DerivationPathInfo(standard: "BIP-44", purpose: "Standard", path: "m/44'/60'/\(derivAccount)'/0/0", pathPrefix: "m/44'/60'/\(derivAccount)'", isActive: true, description: "Standard Ethereum derivation path. All EVM chains (Polygon, Arbitrum, Optimism, Base) use the same key."),
            ]
        case .litecoin:
            return [
                DerivationPathInfo(standard: "BIP-84", purpose: "Native SegWit", path: "m/84'/2'/\(derivAccount)'/0/0", pathPrefix: "m/84'/2'/\(derivAccount)'", isActive: true, description: "Native SegWit Litecoin addresses (ltc1q...). Standard derivation for Litecoin."),
                DerivationPathInfo(standard: "BIP-44", purpose: "Legacy", path: "m/44'/2'/\(derivAccount)'/0/0", pathPrefix: "m/44'/2'/\(derivAccount)'", isActive: false, description: "Legacy Litecoin addresses (L...). Older format, higher fees."),
            ]
        case .solana:
            return [
                DerivationPathInfo(standard: "BIP-44", purpose: "Standard", path: "m/44'/501'/\(derivAccount)'/0'", pathPrefix: "m/44'/501'/\(derivAccount)'", isActive: true, description: "Solana uses hardened derivation for each key. Each account gets a unique keypair."),
            ]
        case .xrp:
            return [
                DerivationPathInfo(standard: "BIP-44", purpose: "Standard", path: "m/44'/144'/\(derivAccount)'/0/0", pathPrefix: "m/44'/144'/\(derivAccount)'", isActive: true, description: "Standard XRP derivation path using coin type 144."),
            ]
        }
    }

    private func pathLegendRow(_ component: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(component)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 70, alignment: .leading)
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }

    // ── Contacts ──

    private func saveContact() {
        if let existing = editingContact {
            var updated = existing
            updated.name = newContactName
            updated.address = newContactAddress
            updated.chainId = newContactChain
            updated.notes = newContactNotes.isEmpty ? nil : newContactNotes
            contactsMgr.updateContact(updated)
        } else {
            let c = Contact(
                name: newContactName,
                address: newContactAddress,
                chainId: newContactChain,
                notes: newContactNotes.isEmpty ? nil : newContactNotes
            )
            contactsMgr.addContact(c)
        }
        showAddContact = false
        editingContact = nil
    }

    private func resetContactForm() {
        newContactName = ""
        newContactAddress = ""
        newContactChain = "bitcoin"
        newContactNotes = ""
        editingContact = nil
    }

    private func populateContactForm(from c: Contact) {
        newContactName = c.name
        newContactAddress = c.address
        newContactChain = c.chainId
        newContactNotes = c.notes ?? ""
    }

    // ── Labels ──

    private func saveLabel() {
        let addr = editingLabel?.address ?? newLabelAddress
        labelMgr.setLabel(
            for: addr,
            name: newLabelName,
            notes: newLabelNotes.isEmpty ? nil : newLabelNotes,
            tagIds: Array(newLabelTagIds),
            isFavorite: newLabelFavorite
        )
        showAddLabel = false
        editingLabel = nil
    }

    private func resetLabelForm() {
        newLabelAddress = ""
        newLabelName = ""
        newLabelNotes = ""
        newLabelTagIds = []
        newLabelFavorite = false
        editingLabel = nil
    }

    private func populateLabelForm(from l: AddressLabel) {
        newLabelAddress = l.address
        newLabelName = l.name
        newLabelNotes = l.notes ?? ""
        newLabelTagIds = Set(l.tagIds)
        newLabelFavorite = l.isFavorite
    }

    // ── Tags ──

    private func saveTag() {
        if let existing = editingTag {
            labelMgr.updateTag(existing.id, name: newTagName, color: newTagColor, icon: newTagIcon)
        } else {
            _ = labelMgr.createTag(name: newTagName, color: newTagColor, icon: newTagIcon)
        }
        showAddTag = false
        editingTag = nil
    }

    private func resetTagForm() {
        newTagName = ""
        newTagColor = "blue"
        newTagIcon = "tag.fill"
        editingTag = nil
    }

    private func populateTagForm(from t: AddressTag) {
        newTagName = t.name
        newTagColor = t.color
        newTagIcon = t.icon ?? "tag.fill"
    }

    // ── Whitelist ──

    private func loadWhitelist() {
        whitelistLoading = true
        whitelistError = nil
        do {
            whitelistEntries = try HawalaBridge.shared.whitelistGetAll(walletId: "default")
            whitelistLoading = false
        } catch {
            whitelistError = error.localizedDescription
            whitelistLoading = false
        }
    }

    private func addToWhitelist() {
        do {
            _ = try HawalaBridge.shared.whitelistAdd(
                walletId: "default",
                address: wlAddress,
                label: wlLabel.isEmpty ? nil : wlLabel,
                notes: wlNotes.isEmpty ? nil : wlNotes,
                skipTimeLock: wlSkipTimeLock
            )
            wlAddress = ""
            wlLabel = ""
            wlNotes = ""
            wlSkipTimeLock = false
            showAddWhitelist = false
            loadWhitelist()
        } catch {
            whitelistError = error.localizedDescription
        }
    }

    private func removeWhitelistEntry(_ address: String) {
        do {
            try HawalaBridge.shared.whitelistRemove(walletId: "default", address: address)
            loadWhitelist()
        } catch {
            whitelistError = error.localizedDescription
        }
    }

    // ── Intelligence ──

    private func analyzeIntelAddress() {
        guard !intelAddress.isEmpty else { return }
        intelAnalyzing = true
        Task {
            let result = await AddressIntelligenceManager.shared.analyzeAddress(intelAddress)
            await MainActor.run {
                intelResult = result
                intelAnalyzing = false
            }
        }
    }

    // ── Address Management ──

    private func generateNewAddress() {
        let chain = genChain
        let managed: ManagedAddress?
        if genIsChange {
            managed = addressMgr.getNextChangeAddress(chain: chain, account: 0)
        } else {
            managed = addressMgr.getNextReceiveAddress(chain: chain, account: 0, forceNew: true)
        }
        if let managed = managed, !genLabel.isEmpty {
            addressMgr.setLabel(genLabel, for: managed.address)
        }
        genResult = managed
    }

    private func generateStealthKeyPair() {
        Task {
            _ = try? await stealthMgr.generateKeyPair(
                for: stealthChain,
                label: stealthGenLabel.isEmpty ? nil : stealthGenLabel
            )
            await MainActor.run {
                stealthShowGenerate = false
                stealthGenLabel = ""
            }
        }
    }

    private func validateAddress() {
        let addr = valAddress.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty else { return }
        Task {
            let result = await validator.validate(address: addr, chainId: valChain)
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    valResult = result
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared UI Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func searchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func actionButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 60, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundColor(.white.opacity(0.7))
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private func chainPicker(selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text("Chain")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 60, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(supportedChains, id: \.self) { chain in
                    Text(chainDisplayName(chain))
                        .tag(chain)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func copyButton(_ address: String) -> some View {
        Button {
            copyToClipboard(address)
        } label: {
            Image(systemName: copiedAddress == address ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(copiedAddress == address ? .green.opacity(0.6) : .white.opacity(0.2))
        }
        .buttonStyle(.plain)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.08))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.15))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private func riskBadge(_ level: AddressRiskLevel) -> some View {
        let color = riskColor(level)
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(level == .safe ? "" : level.rawValue)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, level == .safe ? 4 : 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
        .opacity(level == .safe ? 0.6 : 1)
    }

    private func chainBadge(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white.opacity(0.3))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.04))
            .cornerRadius(3)
    }

    private func tagPill(_ tag: AddressTag, selected: Bool = false) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 5, height: 5)
            Text(tag.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(selected ? 0.8 : 0.35))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tag.swiftUIColor.opacity(selected ? 0.15 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(tag.swiftUIColor.opacity(selected ? 0.3 : 0), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 14 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copiedAddress = text
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { copiedAddress = nil }
            }
        }
    }

    private func riskColor(_ level: AddressRiskLevel) -> Color {
        switch level {
        case .safe:     return .green
        case .low:      return .blue
        case .medium:   return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "red": return .red
        case "gray": return .gray
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .blue
        }
    }

    private func chainDisplayName(_ chainId: String) -> String {
        switch chainId {
        case "bitcoin", "bitcoin-mainnet": return "Bitcoin"
        case "bitcoin-testnet": return "BTC Test"
        case "litecoin": return "Litecoin"
        case "ethereum", "ethereum-mainnet": return "Ethereum"
        case "ethereum-sepolia": return "ETH Test"
        case "bnb", "bsc-mainnet": return "BNB"
        case "polygon-mainnet": return "Polygon"
        case "arbitrum-mainnet": return "Arbitrum"
        case "optimism-mainnet": return "Optimism"
        case "base-mainnet": return "Base"
        case "avalanche-mainnet": return "Avalanche"
        case "fantom-mainnet": return "Fantom"
        case "gnosis-mainnet": return "Gnosis"
        case "scroll-mainnet": return "Scroll"
        case "solana", "solana-mainnet": return "Solana"
        case "solana-devnet": return "SOL Dev"
        case "xrp", "xrp-mainnet": return "XRP"
        case "xrp-testnet": return "XRP Test"
        default: return chainId.capitalized
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    // ── Constants ──

    private let tagColors = ["blue", "green", "orange", "purple", "pink", "cyan", "yellow", "red", "gray", "indigo", "mint"]

    private let tagIcons = ["tag.fill", "person.fill", "building.columns", "square.stack.3d.up", "doc.text", "snowflake", "flame.fill", "briefcase.fill", "wallet.pass.fill", "lock.fill", "globe"]

    private let supportedChains = [
        "bitcoin", "bitcoin-testnet", "litecoin",
        "ethereum", "ethereum-sepolia",
        "bnb", "polygon-mainnet", "arbitrum-mainnet", "optimism-mainnet",
        "base-mainnet", "avalanche-mainnet", "fantom-mainnet", "gnosis-mainnet", "scroll-mainnet",
        "solana", "solana-devnet",
        "xrp", "xrp-testnet"
    ]
}

// MARK: – FlowLayout (Simple Wrapping Layout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), offsets)
    }
}
