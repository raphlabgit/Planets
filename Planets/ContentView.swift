//
//  ContentView.swift
//  Planets
//
//  Fenêtre principale : fond étoilé, simulation, et boutons pause / préférences.
//  Un clic (ou un toucher) dans l'espace fait apparaître un trou noir.
//

import SwiftUI

struct ContentView: View {
    @State private var simulation = Simulation()
    @State private var paused = false
    @State private var showPreferences = false
    @AppStorage(PrefKey.showBackground) private var showBackground = SimulationSettings.defaults.showBackground

    var body: some View {
        ZStack {
            Color.black
            if showBackground {
                Color.clear
                    .overlay {
                        Image("Space")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            }
            SpaceView(simulation: simulation, paused: paused)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    simulation.addBlackHole(at: location)
                }
                .accessibilityLabel("Espace")
                .accessibilityHint("Touchez pour créer un trou noir")
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            controls
                .padding(12)
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView(isSheet: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .planetsReset)) { _ in
            simulation.requestReset()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #else
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    private var controls: some View {
        HStack(spacing: 10) {
            ControlButton(systemImage: paused ? "play.fill" : "pause.fill",
                          label: paused ? "Reprendre" : "Pause") {
                paused.toggle()
                if !paused { simulation.resetClock() }
            }
            ControlButton(systemImage: "gearshape.fill", label: "Préférences") {
                showPreferences = true
            }
        }
    }
}

private struct ControlButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

#Preview {
    ContentView()
}
