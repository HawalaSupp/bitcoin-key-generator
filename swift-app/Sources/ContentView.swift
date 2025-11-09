import SwiftUI

struct ContentView: View {
    @State private var output: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bitcoin Key Generator")
                .font(.largeTitle)
                .bold()

            Text("Press the button to invoke the Rust key generator. The output will appear below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await runGenerator() }
                } label: {
                    Label("Generate Keys", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                Button {
                    output.removeAll()
                    errorMessage = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating && output.isEmpty && errorMessage == nil)
            }

            if isGenerating {
                ProgressView("Running Rust generator...")
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            ScrollView {
                Text(output.isEmpty ? "Output will appear here" : output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .frame(minHeight: 200)

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 400)
    }

    private func runGenerator() async {
        isGenerating = true
        errorMessage = nil

        do {
            let result = try await runRustKeyGenerator()
            await MainActor.run {
                output = result
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func runRustKeyGenerator() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "cargo",
                "run",
                "--manifest-path",
                manifestPath,
                "--quiet"
            ]
            process.currentDirectoryURL = workspaceRoot

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outputString.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let message = errorString.isEmpty ? "Rust generator failed with exit code \(proc.terminationStatus)" : errorString
                    continuation.resume(throwing: KeyGeneratorError.executionFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private var workspaceRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // ContentView.swift
        url.deleteLastPathComponent() // Sources
        url.deleteLastPathComponent() // swift-app
        return url // workspace root
    }

    private var manifestPath: String {
        workspaceRoot
            .appendingPathComponent("rust-app")
            .appendingPathComponent("Cargo.toml")
            .path
    }
}

enum KeyGeneratorError: LocalizedError {
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        }
    }
}

#Preview {
    ContentView()
}
