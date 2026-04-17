import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @StateObject private var authService = EbayAuthService.shared
    @State private var isConnecting = false
    @State private var authError: String?
    @State private var showError = false
    @State private var showAPIKeySheet = false
    @State private var showEbayCredentialsSheet = false
    @State private var anthropicKey = APIConfig.anthropicAPIKey
    @State private var ebayClientID = APIConfig.ebayClientID
    @State private var ebayClientSecret = APIConfig.ebayClientSecret
    @State private var showDiagnosticSheet = false
    @State private var diagnosticReport: String = ""
    @State private var isRunningDiagnostic = false
    @State private var showLocalLLMSheet = false
    @State private var localLLMEnabled = APIConfig.localLLMEnabled

    private var ebayCredentialsConfigured: Bool {
        !ebayClientID.isEmpty
            && ebayClientID != "YOUR_EBAY_CLIENT_ID"
            && !ebayClientSecret.isEmpty
            && ebayClientSecret != "YOUR_EBAY_CLIENT_SECRET"
    }

    var body: some View {
        NavigationStack {
            List {
                // eBay Account Section
                Section {
                    if authService.isAuthenticated {
                        ebayConnectedRow
                    } else {
                        ebayConnectRow
                    }
                } header: {
                    Text("eBay Account")
                }

                // eBay Developer Credentials Section
                Section {
                    Button(action: { showEbayCredentialsSheet = true }) {
                        HStack {
                            Label("eBay API Credentials", systemImage: "key.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: ebayCredentialsConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(ebayCredentialsConfigured ? .green : .red)
                        }
                    }
                } header: {
                    Text("eBay Developer")
                } footer: {
                    Text("Required to connect your eBay account and create listings. Get credentials at developer.ebay.com")
                }

                // Claude AI Section
                Section {
                    Button(action: { showAPIKeySheet = true }) {
                        HStack {
                            Label("Anthropic API Key", systemImage: "key.fill")
                                .foregroundStyle(localLLMEnabled ? .secondary : .primary)
                            Spacer()
                            Image(systemName: anthropicKey.isEmpty ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(anthropicKey.isEmpty ? .red : .green)
                                .opacity(localLLMEnabled ? 0.4 : 1)
                        }
                    }
                    .disabled(localLLMEnabled)
                } header: {
                    Text("AI Configuration")
                } footer: {
                    Text(localLLMEnabled
                         ? "Claude is bypassed while Local LLM is active."
                         : "Required for item identification. Get your key at console.anthropic.com")
                }

                // Local LLM Section
                Section {
                    Toggle(isOn: $localLLMEnabled) {
                        Label("Use Local LLM", systemImage: "cpu.fill")
                    }
                    .onChange(of: localLLMEnabled) { _, newValue in
                        APIConfig.localLLMEnabled = newValue
                    }

                    if localLLMEnabled {
                        Button(action: { showLocalLLMSheet = true }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(APIConfig.localLLMModel)
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundStyle(.primary)
                                    Text(APIConfig.localLLMBaseURL)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("Local LLM")
                } footer: {
                    Text(localLLMEnabled
                         ? "Vision calls go to your local server. Make sure Ollama or LM Studio is running and the model supports images."
                         : "Run Gemma, Qwen, LLaVA, or any vision model on your Mac via Ollama or LM Studio — no API key needed.")
                }

                // Debug
                Section {
                    Button {
                        isRunningDiagnostic = true
                        Task {
                            diagnosticReport = await EbayMarketplaceService.shared.runDiagnostic(
                                lastItem: EbayMarketplaceService.shared.lastScannedItem
                            )
                            isRunningDiagnostic = false
                            showDiagnosticSheet = true
                        }
                    } label: {
                        HStack {
                            Label("Run eBay API Diagnostic", systemImage: "stethoscope")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isRunningDiagnostic {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(isRunningDiagnostic)
                } header: {
                    Text("Developer Tools")
                } footer: {
                    Text("Tests your eBay API credentials and reports the bottleneck. Results are also printed to the Xcode console.")
                }

                // App Settings
                Section("Settings") {
                    Toggle("eBay Sandbox Mode", isOn: .constant(APIConfig.useSandbox))
                    NavigationLink("Shipping Defaults") { Text("Coming soon") }
                    NavigationLink("Category Mappings") { Text("Coming soon") }
                }

                // Info
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Link("eBay Developer Portal", destination: URL(string: "https://developer.ebay.com")!)
                    Link("Anthropic Console", destination: URL(string: "https://console.anthropic.com")!)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 49) }
            .alert("eBay Auth Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(authError ?? "Unknown error")
            }
            .sheet(isPresented: $showAPIKeySheet) {
                APIKeySheet(key: $anthropicKey)
            }
            .sheet(isPresented: $showEbayCredentialsSheet) {
                EbayCredentialsSheet(clientID: $ebayClientID, clientSecret: $ebayClientSecret)
            }
            .sheet(isPresented: $showDiagnosticSheet) {
                DiagnosticReportSheet(report: diagnosticReport)
            }
            .sheet(isPresented: $showLocalLLMSheet) {
                LocalLLMSheet()
            }
        }
    }

    private var ebayConnectedRow: some View {
        HStack {
            Label("Connected to eBay", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Spacer()
            Button("Sign Out") {
                authService.signOut()
            }
            .foregroundStyle(.red)
            .font(.system(size: 14))
        }
    }

    private var ebayConnectRow: some View {
        Button(action: connectEbay) {
            HStack {
                if isConnecting {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                Label(
                    isConnecting ? "Connecting…" : "Connect eBay Account",
                    systemImage: "link"
                )
                Spacer()
                if !isConnecting {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(isConnecting || !ebayCredentialsConfigured)
    }

    private func connectEbay() {
        isConnecting = true
        Task {
            do {
                guard let anchor = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })
                else { return }

                try await authService.authenticate(presentationAnchor: anchor)
            } catch {
                await MainActor.run {
                    authError = error.localizedDescription
                    showError = true
                }
            }
            await MainActor.run { isConnecting = false }
        }
    }
}

// MARK: - eBay Credentials Sheet

struct EbayCredentialsSheet: View {
    @Binding var clientID: String
    @Binding var clientSecret: String
    @Environment(\.dismiss) var dismiss
    @State private var tempClientID = ""
    @State private var tempClientSecret = ""

    private var isSandbox: Bool { APIConfig.useSandbox }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter your eBay \(isSandbox ? "Sandbox" : "Production") app credentials. These are used to authenticate with the eBay API.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Client ID (App ID)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("YourApp-xxxx-SBX-xxxxxxxx", text: $tempClientID)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Client Secret (Cert ID)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    SecureField("SBX-xxxxxxxxxxxxxxxx", text: $tempClientSecret)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }

                if isSandbox {
                    Label("Using eBay Sandbox environment", systemImage: "flask.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Text("Credentials are stored locally on your device and only used to communicate with eBay's API.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(20)
            .navigationTitle("eBay Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        UserDefaults.standard.set(tempClientID, forKey: "ebay_client_id")
                        UserDefaults.standard.set(tempClientSecret, forKey: "ebay_client_secret")
                        clientID = tempClientID
                        clientSecret = tempClientSecret
                        dismiss()
                    }
                    .disabled(tempClientID.isEmpty || tempClientSecret.isEmpty)
                }
            }
            .onAppear {
                let savedID = UserDefaults.standard.string(forKey: "ebay_client_id") ?? ""
                let savedSecret = UserDefaults.standard.string(forKey: "ebay_client_secret") ?? ""
                tempClientID = (savedID == "YOUR_EBAY_CLIENT_ID") ? "" : savedID
                tempClientSecret = (savedSecret == "YOUR_EBAY_CLIENT_SECRET") ? "" : savedSecret
            }
        }
    }
}

// MARK: - Diagnostic Report Sheet

struct DiagnosticReportSheet: View {
    let report: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("eBay Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UIPasteboard.general.string = report
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

// MARK: - API Key Sheet

struct APIKeySheet: View {
    @Binding var key: String
    @Environment(\.dismiss) var dismiss
    @State private var tempKey = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter your Anthropic API key below. This is used to identify items via Claude Vision.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                SecureField("sk-ant-api...", text: $tempKey)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

                Text("Your key is stored locally on your device and never transmitted anywhere except directly to the Anthropic API.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(20)
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        UserDefaults.standard.set(tempKey, forKey: "anthropic_api_key")
                        key = tempKey
                        dismiss()
                    }
                    .disabled(tempKey.isEmpty)
                }
            }
            .onAppear { tempKey = key }
        }
    }
}

// MARK: - Local LLM Sheet

struct LocalLLMSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var baseURL = APIConfig.localLLMBaseURL
    @State private var model = APIConfig.localLLMModel

    private let presets: [(label: String, url: String, model: String)] = [
        ("Ollama – Gemma 3 12B",   "http://localhost:11434/v1", "gemma3:12b"),
        ("Ollama – Gemma 3 4B",    "http://localhost:11434/v1", "gemma3:4b"),
        ("Ollama – Qwen2.5-VL 7B", "http://localhost:11434/v1", "qwen2.5vl:7b"),
        ("Ollama – LLaVA 13B",     "http://localhost:11434/v1", "llava:13b"),
        ("LM Studio",              "http://localhost:1234/v1",  "loaded-model"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("http://localhost:11434/v1", text: $baseURL)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("gemma3:12b", text: $model)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("The iPhone must be on the same Wi-Fi network as the Mac running the local server.")
                }

                Section("Quick Presets") {
                    ForEach(presets, id: \.label) { preset in
                        Button {
                            baseURL = preset.url
                            model = preset.model
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.label)
                                        .foregroundStyle(.primary)
                                    Text("\(preset.url)  •  \(preset.model)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if baseURL == preset.url && model == preset.model {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Supported Models") {
                    infoRow(icon: "star.fill", color: .yellow,
                            title: "Gemma 3 (Google)",
                            detail: "ollama pull gemma3:12b  or  gemma3:4b")
                    infoRow(icon: "star.fill", color: .blue,
                            title: "Qwen2.5-VL (Alibaba)",
                            detail: "ollama pull qwen2.5vl:7b")
                    infoRow(icon: "star.fill", color: .purple,
                            title: "LLaVA / LLaVA-Llama3",
                            detail: "ollama pull llava:13b")
                    infoRow(icon: "star.fill", color: .green,
                            title: "Any OpenAI-compatible VLM",
                            detail: "Works with LM Studio, Jan.ai, etc.")
                }
            }
            .navigationTitle("Local LLM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        APIConfig.localLLMBaseURL = baseURL
                        APIConfig.localLLMModel = model
                        dismiss()
                    }
                    .disabled(baseURL.isEmpty || model.isEmpty)
                }
            }
        }
    }

    private func infoRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
