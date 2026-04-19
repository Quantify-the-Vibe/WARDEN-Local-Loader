import SwiftUI

struct LoaderShellView: View {
    @Bindable var viewModel: LoaderShellViewModel
    @State private var isDiscoveryExpanded = true
    @State private var isLoadStateExpanded = true
    @State private var isHTTPContractExpanded = true
    @State private var isBudgetReportExpanded = true
    @State private var isSupervisorExpanded = true
    @State private var isMemoryBudgetExpanded = true
    @State private var isAdmissionExpanded = true
    @State private var isPostLoadExpanded = true
    @State private var isReclaimExpanded = true
    @State private var isPiMonoExpanded = true
    @State private var isGenerationExpanded = true
    @State private var isResetExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            controlPanel
            statusPanel
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.13),
                    Color(red: 0.11, green: 0.14, blue: 0.18),
                    Color(red: 0.06, green: 0.08, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.shellTitle)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.93, green: 0.96, blue: 0.99))
            Text(viewModel.shellSubtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.62, green: 0.70, blue: 0.78))
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Operator Controls")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 0.58, green: 0.67, blue: 0.78))

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("pi-mono")
                        .font(.headline)
                    Button("pi-mono Button") {
                        viewModel.piMonoButtonPressed()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("pi-mono-button")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selector")
                        .font(.headline)
                    Picker(
                        "Model Selector",
                        selection: Binding(
                            get: { viewModel.selectedModelID ?? "" },
                            set: { viewModel.selectedModelID = $0 }
                        )
                    ) {
                        ForEach(viewModel.availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 280)
                    .accessibilityIdentifier("model-selector")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Load")
                        .font(.headline)
                    Button("Load Button") {
                        viewModel.loadButtonPressed()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("load-button")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reset")
                        .font(.headline)
                    Button("Reset Button") {
                        viewModel.resetButtonPressed()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reset-button")
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.13, green: 0.16, blue: 0.21).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Status")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 0.58, green: 0.67, blue: 0.78))

            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.status == .bootstrapping ? Color.orange : Color(red: 0.49, green: 0.57, blue: 0.65))
                    .frame(width: 10, height: 10)
                Text(viewModel.status.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.91, green: 0.95, blue: 0.98))
            }

            Text(viewModel.statusDetail)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color(red: 0.78, green: 0.83, blue: 0.89))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    collapsibleStatusSection(
                        title: "Discovery",
                        text: viewModel.discoverySummary + selectedModelPathSuffix,
                        isExpanded: $isDiscoveryExpanded
                    )
                    collapsibleStatusSection(
                        title: "Load State",
                        text: viewModel.activeModelSummary,
                        isExpanded: $isLoadStateExpanded
                    )
                    collapsibleStatusSection(
                        title: "HTTP Contract",
                        text: viewModel.serverSummary,
                        isExpanded: $isHTTPContractExpanded
                    )
                    collapsibleStatusSection(
                        title: "Budget Report",
                        text: viewModel.budgetReportSummary,
                        isExpanded: $isBudgetReportExpanded
                    )
                    collapsibleStatusSection(
                        title: "Supervisor",
                        text: viewModel.supervisorSummary,
                        isExpanded: $isSupervisorExpanded
                    )
                    collapsibleStatusSection(
                        title: "Memory Budget",
                        text: "\(viewModel.memoryBudgetStatus)\n\(viewModel.memoryBudgetSummary)",
                        isExpanded: $isMemoryBudgetExpanded
                    )
                    collapsibleStatusSection(
                        title: "Admission",
                        text: viewModel.admissionSummary,
                        isExpanded: $isAdmissionExpanded
                    )
                    collapsibleStatusSection(
                        title: "Post-Load Verification",
                        text: viewModel.postLoadSummary,
                        isExpanded: $isPostLoadExpanded
                    )
                    collapsibleStatusSection(
                        title: "Reclaim Verification",
                        text: viewModel.reclaimSummary,
                        isExpanded: $isReclaimExpanded
                    )
                    collapsibleStatusSection(
                        title: "pi-mono",
                        text: viewModel.piMonoSummary,
                        isExpanded: $isPiMonoExpanded
                    )
                    collapsibleStatusSection(
                        title: "Generation",
                        text: viewModel.generationSummary,
                        isExpanded: $isGenerationExpanded
                    )
                    collapsibleStatusSection(
                        title: "Reset",
                        text: viewModel.resetSummary,
                        isExpanded: $isResetExpanded
                    )
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220, maxHeight: 460)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.11, green: 0.14, blue: 0.18).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("runtime-status-panel")
    }

    private var selectedModelPathSuffix: String {
        guard let selectedModel = viewModel.selectedModel else { return "" }
        return "\nPath: \(selectedModel.localPath)"
    }

    private func collapsibleStatusSection(
        title: String,
        text: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup(isExpanded: isExpanded) {
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(red: 0.74, green: 0.80, blue: 0.87))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            } label: {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.58, green: 0.67, blue: 0.78))
            }
            .tint(Color(red: 0.58, green: 0.67, blue: 0.78))
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}
