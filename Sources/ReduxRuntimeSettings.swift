import SwiftUI
import AppKit
import MacWisprCore

struct ReduxRuntimeSettings: View {
    @Environment(AppState.self) var appState
    @State private var confirmMLX = false
    @State private var mlxPythonDraft = ""

    var body: some View {
        Group {
            if ReduxMLXSidecar.isAvailable || appState.reduxRuntimeConfiguration.runtime == .mlx {
                Section("Experimental Redux MLX") {
                    experimentalRuntimeControls
                }
            }
        }
        .alert("Use experimental Redux MLX?", isPresented: $confirmMLX) {
            Button("Use MLX") { applyRuntime(.mlx) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This uses the converted Redux weights with a Python MLX runtime. Quiet-audio numerical checks still fail. Photon remains available in this picker.")
        }
        .onAppear {
            mlxPythonDraft = appState.reduxRuntimeConfiguration.pythonPath
        }
    }

    @ViewBuilder
    private var experimentalRuntimeControls: some View {
        Picker("Speech runtime", selection: Binding(
            get: { appState.reduxRuntimeConfiguration.runtime },
            set: { runtime in
                if runtime == .mlx { confirmMLX = true }
                else { applyRuntime(runtime) }
            }
        )) {
            ForEach(ReduxRuntime.allCases) { runtime in
                Text(runtime.displayName).tag(runtime)
            }
        }
        .disabled(!appState.canChangeReduxRuntime)

        HStack {
            TextField("MLX Python executable", text: $mlxPythonDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { applyRuntime(appState.reduxRuntimeConfiguration.runtime) }
            Button("Apply") { applyRuntime(appState.reduxRuntimeConfiguration.runtime) }
        }
        .disabled(!appState.canChangeReduxRuntime)

        LabeledContent("Converted weights") {
            VStack(alignment: .trailing, spacing: 4) {
                Text(appState.reduxRuntimeConfiguration.weightsPath.isEmpty
                     ? "Choose a converted model folder" : appState.reduxRuntimeConfiguration.weightsPath)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Button("Choose Folder…") { chooseConvertedWeights() }
                    .disabled(!appState.canChangeReduxRuntime)
            }
        }
        Text("Experimental · Python remains required. Quiet-audio tensor checks currently fail. Choose Photon to return to the original runtime.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let stats = appState.reduxMemoryDiagnostics {
            LabeledContent("MLX process", value: "PID \(stats.pid)")
            LabeledContent("Process peak resident RAM", value: memoryLabel(stats.processPeakRSSBytes))
            LabeledContent("Active GPU allocation", value: memoryLabel(stats.activeGPUBytes))
            LabeledContent("Peak GPU allocation", value: memoryLabel(stats.peakGPUBytes))
            Text("Process and GPU counters share memory on Apple Silicon. Read these counters separately. Peak values cover the current backend process.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let error = appState.reduxDiagnosticsError {
            Text("Memory diagnostics: \(error)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if appState.reduxRuntimeConfiguration.runtime == .mlx {
            Button("Refresh Memory Counters") {
                Task { await appState.refreshReduxMemoryDiagnostics() }
            }
            .disabled(!appState.isModelLoaded || appState.dictationPhase.isBusy || appState.isModelLoading)
        }
    }

    private func memoryLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func applyRuntime(_ runtime: ReduxRuntime) {
        let configuration = ReduxRuntimeConfiguration(
            runtime: runtime,
            pythonPath: mlxPythonDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            weightsPath: appState.reduxRuntimeConfiguration.weightsPath
        )
        appState.setReduxRuntimeConfiguration(configuration)
    }

    private func chooseConvertedWeights() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the converted Redux folder containing conversion.json and model.safetensors."
        panel.prompt = "Use Converted Weights"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setReduxRuntimeConfiguration(ReduxRuntimeConfiguration(
            runtime: appState.reduxRuntimeConfiguration.runtime,
            pythonPath: mlxPythonDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            weightsPath: url.path
        ))
    }

}
