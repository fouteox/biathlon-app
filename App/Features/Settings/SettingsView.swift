import SwiftUI

/// App settings: notification preferences and where the data comes from.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                }
            }

            #if DEBUG
                Section {
                    NavigationLink {
                        LiveActivityDemoView()
                    } label: {
                        Label {
                            Text(verbatim: "Live Activity demo")
                        } icon: {
                            Image(systemName: "hammer")
                        }
                    }
                } header: {
                    Text(verbatim: "Developer")
                }
            #endif

            Section {
                Link(destination: URL(string: "https://www.biathlonresults.com")!) {
                    LabeledContent("Data", value: "IBU Datacenter")
                }
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    LabeledContent("Version", value: version)
                }
            } header: {
                Text("About")
            } footer: {
                Text("Results, calendar and standings come from biathlonresults.com, the IBU Datacenter.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { dismiss() }
            }
        }
    }
}
