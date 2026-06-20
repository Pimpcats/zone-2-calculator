import SwiftUI

/// Connect to the **Google Health API** (the successor to the legacy Fitbit Web API)
/// to pull your all-day data — steps, resting HR, sleep — separately from the H9
/// workout data. Client ID / Secret / scopes / data type are editable so we can
/// iterate against Google's new identifiers, and a "Test API call" dumps the raw
/// JSON response so we can see exactly what your account returns.
struct GoogleHealthView: View {
    @ObservedObject var service: GoogleHealthService
    @State private var pasted = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Health").font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if service.connected {
                        connectedView
                    } else {
                        setupView
                    }

                    if !service.status.isEmpty {
                        Text(service.status).font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !service.rawOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Raw response").font(.caption.bold())
                            ScrollView(.horizontal) {
                                Text(service.rawOutput)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pull your daily steps, resting heart rate, and sleep from Google Health — kept completely separate from your H9 workout data.")
                .font(.subheadline).foregroundColor(.secondary)

            field("Client ID", text: $service.clientID, placeholder: "Paste your OAuth Client ID")
            field("Client Secret", text: $service.clientSecret, placeholder: "Paste your Client Secret")
            field("Scopes (space-separated)", text: $service.scopes, placeholder: "health.* read scopes")
            field("Data type", text: $service.dataType, placeholder: "heart_rate")

            Button { service.openSignIn() } label: {
                Label("Sign in with Google", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.blue)
            .disabled(service.clientID.trimmingCharacters(in: .whitespaces).isEmpty)

            VStack(alignment: .leading, spacing: 6) {
                Text("After authorizing, Google redirects to google.com with a code=… in the URL. Copy the whole address bar (or just the code) and paste it here:")
                    .font(.caption2).foregroundColor(.secondary)
                TextField("Paste redirected URL or code", text: $pasted)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                Button { service.submit(pasted); pasted = "" } label: {
                    Label("Exchange code", systemImage: "arrow.right.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("First time? Set up a free Google Cloud OAuth client:").font(.caption.bold())
                Text("1. console.cloud.google.com → APIs & Services → Credentials").font(.caption2).foregroundColor(.secondary)
                Text("2. Create OAuth client → Web application").font(.caption2).foregroundColor(.secondary)
                Text("3. Authorized redirect URI: https://www.google.com").font(.caption2).foregroundColor(.secondary)
                Text("4. Enable the Health API and add yourself as a test user").font(.caption2).foregroundColor(.secondary)
                Text("5. Copy the Client ID and Secret above.").font(.caption2).foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

            Text("This is the only part of Zone Alert that uses the internet. Your Google sign-in happens in the browser; the app only stores the access token on your phone.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Connected to Google Health", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green).font(.subheadline.bold())
                Spacer()
                if service.loading { ProgressView() }
            }

            field("Data type", text: $service.dataType, placeholder: "heart_rate")

            Button { service.testFetch() } label: {
                Label("Test API call", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.blue)

            Button(role: .destructive) { service.disconnect() } label: {
                Label("Disconnect", systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)

            Text("Tap “Test API call” to fetch raw data points for the data type above. We’ll parse and lay these out once we confirm the exact response your account returns.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        }
    }
}
