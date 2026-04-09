//
//  ContentView.swift
//  TomatoTimer
//
//  Created by Florian Knaus on 4/8/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tomato = TomatoTimer()

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.055, green: 0.055, blue: 0.059)
                .ignoresSafeArea()

            // Ambient glow behind ring
            RadialGradient(
                gradient: Gradient(colors: [
                    tomato.mode.color.opacity(tomato.isRunning ? 0.18 : 0.07),
                    Color.clear
                ]),
                center: .center,
                startRadius: 10,
                endRadius: 260
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: tomato.isRunning)
            .animation(.easeInOut(duration: 0.6), value: tomato.mode)

            VStack(spacing: 0) {
                // Mode picker
                ModePicker(selectedMode: tomato.mode) { mode in
                    tomato.setMode(mode)
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)

                // Session label + dots
                VStack(spacing: 10) {
                    Text(tomato.mode.rawValue)
                        .font(.system(size: 18	, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(tomato.mode.color)
                        .animation(.easeInOut, value: tomato.mode)

                    SessionDots(filled: tomato.sessionDotsCompleted)
                }
                .padding(.top, 24)

                Spacer()

                // Timer ring
                TimerRingView(
                    progress: tomato.progress,
                    time: tomato.formattedTime,
                    color: tomato.mode.color,
                    isRunning: tomato.isRunning,
                    justCompleted: tomato.justCompleted
                )

                Spacer()

                // Controls
                ControlsView(
                    isRunning: tomato.isRunning,
                    accentColor: tomato.mode.color,
                    onPlayPause: {
                        if tomato.isRunning { tomato.pause() } else { tomato.start() }
                    },
                    onReset: { tomato.reset() },
                    onSkip: { tomato.skip() }
                )

                // Stats
                StatsRow(
                    sessions: tomato.completedSessions,
                    focusedMinutes: tomato.totalFocusedMinutes,
                    streak: tomato.dailyStreak,
                    onStatsReset: { tomato.resetStats() }
                )
                .padding(.top, 28)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            tomato.requestNotificationPermission()
        }
    }
}

// MARK: - Mode Picker

struct ModePicker: View {
    let selectedMode: TomatoMode
    let onSelect: (TomatoMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TomatoMode.allCases, id: \.self) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(selectedMode == mode ? Color(red: 0.96, green: 0.96, blue: 0.94) : Color(red: 0.42, green: 0.42, blue: 0.44))
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedMode == mode
                                    ? Color(red: 0.14, green: 0.14, blue: 0.15)
                                    : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
        )
    }
}

// MARK: - Session Dots

struct SessionDots: View {
    let filled: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < filled
                        ? Color(red: 1.0, green: 0.30, blue: 0.18)
                        : Color(red: 0.14, green: 0.14, blue: 0.15))
                    .frame(width: 6, height: 6)
                    .animation(.spring(response: 0.4), value: filled)
            }
        }
    }
}

// MARK: - Timer Ring

struct TimerRingView: View {
    let progress: Double
    let time: String
    let color: Color
    let isRunning: Bool
    let justCompleted: Bool

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(Color(red: 0.10, green: 0.10, blue: 0.11), lineWidth: 8)
                .frame(width: 240, height: 240)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 240, height: 240)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 8)
                .animation(.easeInOut(duration: 0.5), value: progress)
                .animation(.easeInOut(duration: 0.5), value: color)

            // Time display
            VStack(spacing: 6) {
                Text(time)
                    .font(.system(size: 58, weight: .light, design: .monospaced))
                    .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.94))
                    .monospacedDigit()
                    .scaleEffect(scale)

                Text(isRunning ? "remaining" : justCompleted ? "complete" : "ready")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 0.42, green: 0.42, blue: 0.44))
                    .kerning(1.5)
                    .textCase(.uppercase)
            }
        }
        .onChange(of: justCompleted) { oldValue, newValue in
            if newValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                    scale = 1.06
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.3)) {
                        scale = 1.0
                    }
                }
            }
        }
    }
}

// MARK: - Controls

struct ControlsView: View {
    let isRunning: Bool
    let accentColor: Color
    let onPlayPause: () -> Void
    let onReset: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            
            // Reset
            CircleButton(systemImage: "arrow.counterclockwise", size: 52, fontSize: 18) {
                onReset()
            }

            // Play / Pause
            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 76, height: 76)
                        .shadow(color: accentColor.opacity(0.45), radius: 16, y: 6)

                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                        .offset(x: isRunning ? 0 : 2)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: accentColor)

            // Skip
            CircleButton(systemImage: "forward.end.fill", size: 52, fontSize: 16) {
                onSkip()
            }
        }
    }
}

struct CircleButton: View {
    let systemImage: String
    let size: CGFloat
    let fontSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
                    .frame(width: size, height: size)
                Image(systemName: systemImage)
                    .font(.system(size: fontSize))
                    .foregroundColor(Color(red: 0.42, green: 0.42, blue: 0.44))
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct CircleAlertButton: View {
    let systemImage: String
    let size: CGFloat
    let fontSize: CGFloat
    let action: () -> Void
    @State private var showingConfirm = false

    var body: some View {
        Button(action: { showingConfirm = true }) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
                    .frame(width: size, height: size)
                Image(systemName: systemImage)
                    .font(.system(size: fontSize))
                    .foregroundColor(Color(red: 0.42, green: 0.42, blue: 0.44))
            }
        }
        .alert("Are you sure you want to reset the stats?", isPresented: $showingConfirm) {
            Button("OK", role: .destructive) {
                action(); showingConfirm.toggle() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Stats Row

struct StatsRow: View {
    let sessions: Int
    let focusedMinutes: Int
    let streak: Int
    let onStatsReset: () -> Void

    var focusedFormatted: String {
        if focusedMinutes >= 60 {
            let h = focusedMinutes / 60
            let m = focusedMinutes % 60
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(focusedMinutes)m"
    }

    var body: some View {
        HStack(spacing: 10) {
            StatCard(value: "\(sessions)", label: "Sessions")
            StatCard(value: focusedFormatted, label: "Focused")
            StatCard(value: "\(streak)", label: "Streak")
            // Full Reset
            CircleAlertButton(systemImage: "eraser", size: 62, fontSize: 21) {
                onStatsReset()
            }
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.94))
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(Color(red: 0.42, green: 0.42, blue: 0.44))
                .kerning(1.0)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
        )
    }
}

#Preview {
    ContentView()
}

