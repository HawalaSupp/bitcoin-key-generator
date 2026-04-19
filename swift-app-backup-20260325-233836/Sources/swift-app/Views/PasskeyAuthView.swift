// PasskeyAuthView.swift
// WebAuthn Passkey Authentication
// Created for Hawala - Phase 4

import SwiftUI

struct PasskeyAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var passkeys: [PasskeyInfo] = []
    @State private var isCreating = false
    @State private var showingCreateSheet = false
    @State private var passkeyEnabled = false
    @State private var faceIdEnabled = true
    
    var body: some View {
        NavigationView {
            List {
                heroSection
                
                if passkeyEnabled {
                    passkeysSection
                    settingsSection
                }
                
                benefitsSection
            }
            .navigationTitle("Passkey Auth")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreatePasskeySheet(isCreating: $isCreating, onCreate: createPasskey)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var heroSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "faceid")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding()
                    .background(Circle().fill(Color.blue.opacity(0.1)))
                
                Text("Passwordless Security")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Sign transactions with Face ID or Touch ID. No passwords, no seed phrases to enter.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Toggle("Enable Passkey Authentication", isOn: $passkeyEnabled)
                    .padding(.top)
                
                if !passkeyEnabled {
                    Button(action: { passkeyEnabled = true }) {
                        Text("Get Started")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
    }
    
    private var passkeysSection: some View {
        Section("Your Passkeys") {
            if passkeys.isEmpty {
                Button(action: { showingCreateSheet = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Create New Passkey")
                        Spacer()
                        if isCreating {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCreating)
            } else {
                ForEach(passkeys) { passkey in
                    PasskeyRow(passkey: passkey)
                }
                
                Button(action: { showingCreateSheet = true }) {
                    Label("Add Another Passkey", systemImage: "plus")
                }
            }
        }
    }
    
    private var settingsSection: some View {
        Section("Passkey Settings") {
            Toggle(isOn: $faceIdEnabled) {
                HStack {
                    Image(systemName: "faceid")
                        .foregroundColor(.blue)
                    Text("Use Face ID")
                }
            }
            
            NavigationLink(destination: LinkedAccountsView()) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.green)
                    Text("Linked Smart Accounts")
                }
            }
            
            NavigationLink(destination: PasskeyRecoveryView()) {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .foregroundColor(.orange)
                    Text("Recovery Options")
                }
            }
        }
    }
    
    private var benefitsSection: some View {
        Section("Why Use Passkeys?") {
            BenefitItem(
                icon: "lock.shield.fill",
                iconColor: .blue,
                title: "Phishing-Resistant",
                description: "Passkeys are bound to your device and can't be stolen remotely"
            )
            
            BenefitItem(
                icon: "cloud.fill",
                iconColor: .purple,
                title: "iCloud Sync",
                description: "Access your wallet on all your Apple devices"
            )
            
            BenefitItem(
                icon: "bolt.fill",
                iconColor: .orange,
                title: "Instant Signing",
                description: "Sign transactions with a glance - no passwords needed"
            )
            
            BenefitItem(
                icon: "person.3.fill",
                iconColor: .green,
                title: "Smart Account Compatible",
                description: "Works with ERC-4337 for gasless transactions"
            )
        }
    }
    
    private func createPasskey() {
        isCreating = true
        // In production, this would call AuthenticationServices
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let newPasskey = PasskeyInfo(
                id: UUID().uuidString,
                name: "iPhone Passkey",
                createdAt: Date(),
                lastUsed: Date(),
                deviceName: "iPhone"
            )
            passkeys.append(newPasskey)
            isCreating = false
            showingCreateSheet = false
        }
    }
}

struct PasskeyRow: View {
    let passkey: PasskeyInfo
    
    var body: some View {
        HStack {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(passkey.name)
                    .font(.headline)
                
                Text("Created \(passkey.createdAt, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct BenefitItem: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CreatePasskeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isCreating: Bool
    let onCreate: () -> Void
    
    @State private var passkeyName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 20) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding()
                            .background(Circle().fill(Color.blue.opacity(0.1)))
                        
                        Text("Create Passkey")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Your passkey will be stored securely in your device's Secure Enclave and synced via iCloud Keychain.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                Section("Passkey Name") {
                    TextField("e.g., iPhone Passkey", text: $passkeyName)
                }
                
                Section {
                    Button(action: onCreate) {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Creating...")
                            } else {
                                Image(systemName: "faceid")
                                Text("Create with Face ID")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isCreating || passkeyName.isEmpty)
                }
            }
            .navigationTitle("New Passkey")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct LinkedAccountsView: View {
    var body: some View {
        List {
            Section("Smart Accounts") {
                Text("No linked smart accounts")
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button("Link Smart Account") {
                    // Link smart account
                }
            }
        }
        .navigationTitle("Linked Accounts")
    }
}

struct PasskeyRecoveryView: View {
    var body: some View {
        List {
            Section {
                Text("Your passkeys are synced via iCloud Keychain. If you lose access to all your devices, you can recover using:")
                    .foregroundColor(.secondary)
            }
            
            Section("Recovery Methods") {
                HStack {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                    Text("iCloud Keychain")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.orange)
                    Text("Social Recovery")
                    Spacer()
                    Text("Set Up")
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Recovery Options")
    }
}

// MARK: - Data Types

struct PasskeyInfo: Identifiable {
    let id: String
    let name: String
    let createdAt: Date
    let lastUsed: Date
    let deviceName: String
}

struct PasskeyAuthView_Previews: PreviewProvider {
    static var previews: some View {
        PasskeyAuthView()
    }
}
