#!/usr/bin/env python3
"""Generate AddressBookOverlay.swift — unified 6-tab address book overlay."""

import os

OUTPUT = os.path.expanduser(
    "~/Desktop/888/swift-app/Sources/swift-app/UI/AddressBookOverlay.swift"
)

CODE = r'''import SwiftUI

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
    }

    @State private var selectedTab: ABTab = .contacts

    // ── Real managers ──
    @ObservedObject private var contactsMgr  = ContactsManager.shared
    @ObservedObject private var labelMgr     = AddressLabelManager.shared

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
        .frame(width: 700, height: 600)
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
        HStack(spacing: 0) {
            ForEach(ABTab.allCases, id: \.self) { tab in
                tabButton(tab)
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
'''

with open(OUTPUT, 'w') as f:
    f.write(CODE)

print(f"Wrote {len(CODE)} bytes to {OUTPUT}")
