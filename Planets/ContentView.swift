//
//  ContentView.swift
//  Planets
//
//  Fenêtre principale : fond étoilé, simulation, compteur de planètes et bouton des préférences.
//  Un clic (ou un toucher) dans l'espace fait apparaître un trou noir.
//

import SwiftUI

struct ContentView: View {
    @State private var simulation = Simulation()
    @State private var showPreferences = false
    @AppStorage(PrefKey.showBackground) private var showBackground = SimulationSettings.defaults.showBackground
    @AppStorage(PrefKey.showPlanetCount) private var showPlanetCount = SimulationSettings.defaults.showPlanetCount

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
            SpaceView(simulation: simulation)
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
            if showPlanetCount {
                PlanetCounter(simulation: simulation)
            }
            ControlButton(systemImage: "gearshape.fill", label: "Préférences") {
                showPreferences = true
            }
        }
    }
}

/// Nombre de planètes, rafraîchi 4 fois par seconde seulement : un simple texte, sans
/// redessiner l'espace, donc pratiquement gratuit.
private struct PlanetCounter: View {
    let simulation: Simulation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let count = simulation.planets.count
            Text("\(count) planète\(count > 1 ? "s" : "")")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("Nombre de planètes")
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
