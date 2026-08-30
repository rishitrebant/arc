import SwiftUI

struct AudioOutputPicker: View {

    @ObservedObject var manager:
        AudioOutputDeviceManager

    let onDismiss: () -> Void

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Text("Output Device")
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            VStack(spacing: 7) {

                ForEach(manager.devices) { device in

                    Button {

                        manager.select(device)
                        onDismiss()

                    } label: {

                        HStack(spacing: 13) {

                            Image(
                                systemName:
                                    device.type.systemImage
                            )
                            .font(
                                .system(
                                    size: 18,
                                    weight: .medium
                                )
                            )
                            .frame(width: 25)

                            Text(device.name)
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .semibold
                                    )
                                )
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            if device.isActive {

                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .bold
                                    )
                                )
                            }
                        }
                        .foregroundStyle(
                            device.isActive
                                ? Color.black
                                : Color.white
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background {

                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .fill(
                                device.isActive
                                    ? Color.white.opacity(
                                        selectedOpacity(
                                            for: device
                                        )
                                    )
                                    : Color.white.opacity(
                                        0.10
                                    )
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 290)
        .background(.ultraThinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {

            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.18),
                lineWidth: 1
            )
        }
    }

    private func selectedOpacity(
        for device: OutputDevice
    ) -> Double {

        let volume =
            device.volume ?? 0.5

        return 0.10 +
            (
                min(
                    max(volume, 0),
                    1
                )
                * 0.80
            )
    }
}

// MARK: - Output Picker Notifications

extension Notification.Name {

    static let islandOutputPickerWillPresent =
        Notification.Name(
            "IslandOutputPickerWillPresent"
        )

    static let islandOutputPickerDidDismiss =
        Notification.Name(
            "IslandOutputPickerDidDismiss"
        )
}
