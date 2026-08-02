import SwiftUI

struct StatusMenuView: View {
    let appModel: AppModel
    @State private var store = StatusMenuStore.shared

    private var presentation: StatusPresentation {
        store.presentation(launch: appModel.launchKind)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch appModel.launchState {
            case .starting:
                launchProgress
            case .ready:
                activityCard
                controls
                deliverySummary
            case let .failed(message):
                launchFailure(message: message)
            }
            footer
        }
        .frame(width: 320)
        .background(panelBackground)
        .onAppear {
            store.refreshCurrentState()
            store.refreshKeepAwakeState()
        }
    }

    private var launchProgress: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Preparing local data...")
                .font(.system(size: 12, weight: .medium))
            Text("Statusa will start monitoring after its database is ready.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }

    private func launchFailure(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            Text("Statusa could not start")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Statusa")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("YOUR CURRENT STATUS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: presentation.headlineSymbol)
                .font(.system(size: 8, weight: .bold))
            Text(presentation.headline)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
        }
        .foregroundStyle(badgeForeground)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(badgeBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status \(presentation.headline)")
    }

    private var activityCard: some View {
        Button {
            store.sendNow(using: appModel)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.currentProcess)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(store.currentProcessDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(store.isReporting ? .secondary : .tertiary)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24)
                    Text(store.currentMedia)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(StatusPanelButtonStyle(cornerRadius: 12))
        .disabled(appModel.launchState != .ready || !store.isReporting || store.deliveryState == .sending)
        .help(store.isReporting ? "Send the current status now" : "Enable reporting to send")
        .padding(.horizontal, 12)
    }

    private var controls: some View {
        VStack(spacing: 2) {
            StatusToggleRow(
                icon: "bolt.horizontal.circle",
                title: "Vibe Coding Mode",
                detail: store.keepAwakeDetail,
                isOn: Binding(
                    get: { store.keepMacAwake },
                    set: { store.setKeepMacAwake($0) }
                )
            )

            if store.keepMacAwake {
                StatusActionRow(
                    icon: "display",
                    title: "Turn Display Off Now",
                    detail: "Vibe Coding keeps running in the background",
                    action: store.turnDisplayOffNow
                )
            }

            StatusToggleRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "Reporting",
                detail: store.isEnabled ? "Monitoring is enabled" : "All monitoring is paused",
                isOn: Binding(
                    get: { store.isEnabled },
                    set: { store.setEnabled($0) }
                )
            )

            StatusToggleRow(
                icon: "macwindow",
                title: "Applications",
                detail: "App name, window and foreground time",
                isOn: Binding(
                    get: { store.enabledTypes.contains(.process) },
                    set: { store.setReportType(.process, enabled: $0) }
                )
            )
            .disabled(!store.isEnabled)

            StatusToggleRow(
                icon: "play.rectangle",
                title: "Now Playing",
                detail: "Media title, artist and playback state",
                isOn: Binding(
                    get: { store.enabledTypes.contains(.media) },
                    set: { store.setReportType(.media, enabled: $0) }
                )
            )
            .disabled(!store.isEnabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var deliverySummary: some View {
        VStack(spacing: 0) {
            summaryRow(
                icon: deliveryIcon,
                title: store.lastDeliveryTitle,
                detail: store.lastDeliveryDetail
            )
            Divider().padding(.leading, 43)
            summaryRow(
                icon: "terminal",
                title: store.shellSummary,
                detail: store.screenState == .off
                    ? "Screen-off event queued or delivered"
                    : "Receives report and screen-state events"
            )

            if !store.accessibilityEnabled {
                Divider().padding(.leading, 43)
                Button {
                    store.openSettings()
                } label: {
                    summaryRow(
                        icon: "hand.raised",
                        title: "Window titles unavailable",
                        detail: "Grant Accessibility permission in Settings"
                    )
                }
                .buttonStyle(StatusPanelButtonStyle(cornerRadius: 8))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .padding(.horizontal, 12)
    }

    private func summaryRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("v\(store.appVersion)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            footerButton("Refresh", systemImage: "arrow.clockwise") {
                store.refreshCurrentState()
            }

            footerButton("Settings", systemImage: "gearshape") {
                store.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            footerButton("Quit", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func footerButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(StatusPanelButtonStyle(cornerRadius: 6))
        .help(title)
    }

    private var panelBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.2))
    }

    private var badgeForeground: Color {
        appModel.launchState == .ready
            && store.isReporting
            && store.deliveryState != .failure
            && store.screenState == .on
            ? Color(nsColor: .windowBackgroundColor)
            : .secondary
    }

    private var badgeBackground: Color {
        appModel.launchState == .ready
            && store.isReporting
            && store.deliveryState != .failure
            && store.screenState == .on
            ? .primary.opacity(0.85)
            : Color(nsColor: .tertiarySystemFill)
    }

    private var deliveryIcon: String {
        switch store.deliveryState {
        case .idle:
            return "clock"
        case .sending:
            return "arrow.up.circle"
        case .success:
            return "checkmark.circle"
        case .partialFailure:
            return "exclamationmark.circle"
        case .failure:
            return "xmark.circle"
        }
    }
}

private struct StatusActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "moon.zzz")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color(nsColor: .quaternarySystemFill) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct StatusToggleRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(StatusPanelSwitchStyle())
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color(nsColor: .quaternarySystemFill) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

private struct StatusPanelSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(
                configuration.isOn
                    ? AnyShapeStyle(Color.primary.opacity(0.82))
                    : AnyShapeStyle(Color(nsColor: .tertiarySystemFill))
            )
            .frame(width: 28, height: 16)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(
                        configuration.isOn
                            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                            : AnyShapeStyle(Color.white)
                    )
                    .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                    .padding(2)
            }
    }
}

private struct StatusPanelButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.06 : 0))
            }
    }
}
