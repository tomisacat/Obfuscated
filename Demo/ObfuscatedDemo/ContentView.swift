import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each example shows the macro you write, what it decodes to at runtime, and whether the compile-time byte payload differs from the raw UTF-8 literal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                demoSection("Single Methods", examples: DemoCatalog.methodExamples)

                Section {
                    Text("ObfuscatedKey, ObfuscatedNonce, ObfuscatedSalt, ObfuscatedInfo, and explicit ECIES recipient keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    demoRows(DemoCatalog.explicitMaterialExamples)
                } header: {
                    Text("Explicit Material")
                }

                demoSection("Edge Cases", examples: DemoCatalog.edgeCaseExamples)

                demoSection("Typed Values", examples: DemoCatalog.typedValueExamples)

                demoSection("Custom Steps", examples: DemoCatalog.customStepExamples)

                demoSection("Pipelines", examples: DemoCatalog.pipelineExamples)
            }
            .demoListStyle()
            .navigationTitle("Obfuscated Demo")
            .inlineNavigationTitle()
        }
    }

    @ViewBuilder
    private func demoSection(_ title: String, examples: [DemoExample]) -> some View {
        Section(title) {
            demoRows(examples)
        }
    }

    @ViewBuilder
    private func demoRows(_ examples: [DemoExample]) -> some View {
        ForEach(examples) { example in
            DemoRow(example: example)
                .fixedSize(horizontal: false, vertical: true)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
}

private struct DemoRow: View {
    let example: DemoExample

    private var decodedLabel: String {
        example.plaintext.isEmpty ? "(empty)" : example.value
    }

    private var obfuscationSummary: String {
        if example.matchesPlaintextUTF8 {
            return "Compile-time bytes match UTF-8 literal (\(example.encodedByteCount) bytes)."
        }
        return "Compile-time bytes differ from UTF-8 literal (\(example.encodedByteCount) bytes stored)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(example.title)
                .font(.headline)

            FieldBlock(title: "Macro", value: example.macroSource, style: .code)

            FieldBlock(title: "Decodes to", value: decodedLabel, style: .value)

            StatusLine(
                text: obfuscationSummary,
                systemImage: example.matchesPlaintextUTF8 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                color: example.matchesPlaintextUTF8 ? .orange : .green
            )

            StatusLine(
                text: example.value == example.plaintext ? "Runtime check passed" : "Runtime check failed",
                systemImage: example.value == example.plaintext ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: example.value == example.plaintext ? .secondary : .red
            )

            if let note = example.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FieldBlock: View {
    enum Style {
        case code
        case value
    }

    let title: String
    let value: String
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value.isEmpty ? " " : value)
                .font(style == .code ? .caption.monospaced() : .body.monospaced())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(10)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var fieldBackground: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

private struct StatusLine: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(.caption)
                .padding(.top, 2)

            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    @ViewBuilder
    func demoListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#Preview {
    ContentView()
}
