import SwiftUI

/// Sheet for generating and displaying seed phrases (mnemonic)
struct SeedPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCount: MnemonicGenerator.WordCount = .twelve
    @State private var words: [String] = MnemonicGenerator.generate(wordCount: .twelve)
    let onCopy: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Length", selection: $selectedCount) {
                    ForEach(MnemonicGenerator.WordCount.allCases) { count in
                        Text(count.title).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCount) { newValue in
                    regenerate(using: newValue)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(String(format: "%02d", index + 1))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(word)
                                    .font(.headline)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button {
                        regenerate(using: selectedCount)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let phrase = words.joined(separator: " ")
                        onCopy(phrase)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Text("Back up this phrase securely. Anyone with access can control your wallets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 20)
            .navigationTitle("Seed Phrase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 550, height: 600)
    }

    private func regenerate(using count: MnemonicGenerator.WordCount) {
        words = MnemonicGenerator.generate(wordCount: count)
    }
}
