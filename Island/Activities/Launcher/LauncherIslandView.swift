import SwiftUI

/// Renders `LauncherActivity`: a full-size island panel with a Now
/// Playing row on top and three Clock-style tiles (Timer, Pomodoro,
/// Stopwatch) beneath. Timer and Pomodoro open a small setup page in the
/// same panel; Stopwatch starts immediately.
struct LauncherIslandView: View {

    @ObservedObject var activity: LauncherActivity
    @ObservedObject var music: MusicActivity

    private typealias Metrics = DesignTokens.LauncherMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var panelSize: CGSize {
        activity.expandedSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - panelSize.width) / 2
    }

    var body: some View {

        ZStack(alignment: .topLeading) {

            IslandShape(
                topRadius: DesignTokens.Shape.expandedTopRadius,
                bottomRadius: DesignTokens.Shape.expandedBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: canvasSize.width / 2, y: panelSize.height / 2)

            VStack(spacing: 0) {

                // Reserves the physical notch cutout — nothing renders here.
                Color.clear
                    .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

                Group {
                    switch activity.page {
                    case .home:
                        homePage
                    case .timer:
                        timerPage
                    case .pomodoro:
                        pomodoroPage
                    }
                }
                .transition(.opacity)
                .padding(.horizontal, Metrics.edgePadding)
                .padding(.bottom, Metrics.bottomPadding)
                .frame(maxHeight: .infinity)
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(.easeInOut(duration: 0.2), value: activity.page)
    }

    // MARK: - Home

    private var homePage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            nowPlayingRow

            HStack(spacing: Metrics.tileSpacing) {

                tile(
                    symbol: "timer",
                    title: "Timer",
                    tint: DesignTokens.Color.timerAccent
                ) {
                    activity.page = .timer
                }

                tile(
                    symbol: "brain.head.profile",
                    title: "Pomodoro",
                    tint: DesignTokens.Color.pomodoroAccent
                ) {
                    activity.page = .pomodoro
                }

                tile(
                    symbol: "stopwatch.fill",
                    title: "Stopwatch",
                    tint: DesignTokens.Color.timerAccent
                ) {
                    activity.startStopwatch()
                }
            }
        }
    }

    // MARK: Now Playing

    private var nowPlayingRow: some View {

        HStack(spacing: 12) {

            if let state = music.playbackState {

                AlbumArtView(
                    image: state.artwork,
                    size: Metrics.artSize,
                    cornerRadius: Metrics.artCornerRadius
                )

                VStack(alignment: .leading, spacing: 2) {

                    Text(state.title)
                        .font(Metrics.titleFont)
                        .tracking(DesignTokens.Typography.letterSpacingTight)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)

                    Text(state.artist)
                        .font(Metrics.subtitleFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                PlaybackButton(
                    systemName: state.isPlaying ? "pause.fill" : "play.fill",
                    action: { withAnimation { music.togglePlayPause() } },
                    size: 20,
                    buttonSize: Metrics.transportButtonSize
                )

                PlaybackButton(
                    systemName: "forward.fill",
                    action: { music.skipForward() },
                    size: 18,
                    buttonSize: Metrics.transportButtonSize
                )

            } else {

                RoundedRectangle(
                    cornerRadius: Metrics.artCornerRadius,
                    style: .continuous
                )
                .fill(DesignTokens.Color.deviceIconBackground)
                .frame(width: Metrics.artSize, height: Metrics.artSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {

                    Text("Not Playing")
                        .font(Metrics.titleFont)
                        .foregroundStyle(DesignTokens.Color.primaryText)

                    Text("Play something in Music or Spotify")
                        .font(Metrics.subtitleFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: Metrics.artSize)
    }

    private func tile(
        symbol: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            VStack(spacing: 6) {

                Image(systemName: symbol)
                    .font(.system(size: Metrics.tileGlyphSize, weight: .medium))
                    .foregroundStyle(tint)

                Text(title)
                    .font(Metrics.tileFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.tileHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Metrics.tileCornerRadius,
                    style: .continuous
                )
                .fill(DesignTokens.Color.deviceIconBackground)
            )
        }
        .buttonStyle(LauncherPressStyle())
    }

    // MARK: - Timer setup

    private let timerPresets = [1, 5, 10, 15, 25, 30]

    private var timerPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            header(
                title: "Timer",
                tint: DesignTokens.Color.timerAccent,
                startAction: { activity.startTimer() }
            )

            HStack(spacing: 8) {
                ForEach(timerPresets, id: \.self) { minutes in
                    chip(
                        minutes: minutes,
                        isSelected: activity.timerMinutes == minutes,
                        tint: DesignTokens.Color.timerAccent
                    ) {
                        activity.timerMinutes = minutes
                    }
                }
            }

            stepperRow(
                title: "Custom",
                value: $activity.timerMinutes,
                range: 1...999
            )
        }
    }

    // MARK: - Pomodoro setup

    private var pomodoroPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            header(
                title: "Pomodoro",
                tint: DesignTokens.Color.pomodoroAccent,
                startAction: { activity.startPomodoro() }
            )

            stepperRow(
                title: "Focus",
                value: $activity.focusMinutes,
                range: 1...180
            )

            stepperRow(
                title: "Break",
                value: $activity.breakMinutes,
                range: 1...60
            )
        }
    }

    // MARK: - Setup components

    private func header(
        title: String,
        tint: Color,
        startAction: @escaping () -> Void
    ) -> some View {

        HStack(spacing: 10) {

            Button {
                activity.page = .home
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                    .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
            }
            .buttonStyle(LauncherPressStyle())
            .accessibilityLabel("Back")

            Text(title)
                .font(Metrics.titleFont)
                .foregroundStyle(DesignTokens.Color.primaryText)

            Spacer(minLength: 0)

            Button(action: startAction) {
                Text("Start")
                    .font(Font.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20)
                    .frame(height: Metrics.startButtonHeight)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(LauncherPressStyle())
        }
    }

    private func chip(
        minutes: Int,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Text("\(minutes)m")
                .font(Metrics.tileFont)
                .foregroundStyle(isSelected ? Color.black : DesignTokens.Color.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.chipHeight)
                .background(
                    Capsule().fill(
                        isSelected ? tint : DesignTokens.Color.deviceIconBackground
                    )
                )
        }
        .buttonStyle(LauncherPressStyle())
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {

        HStack(spacing: 10) {

            Text(title)
                .font(Metrics.titleFont)
                .foregroundStyle(DesignTokens.Color.primaryText)

            Spacer(minLength: 0)

            stepperButton(symbol: "minus") {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            }

            Text("\(value.wrappedValue) min")
                .font(Metrics.valueFont)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(minWidth: 72)
                .contentTransition(.numericText())

            stepperButton(symbol: "plus") {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            }
        }
        .animation(AnimationTokens.stateUpdate, value: value.wrappedValue)
    }

    private func stepperButton(
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
        }
        .buttonStyle(LauncherPressStyle())
    }
}

/// Same press feedback as the other island buttons.
private struct LauncherPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
