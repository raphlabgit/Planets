//
//  ContentView.swift
//  Planets
//
//  Fenêtre principale : fond étoilé, simulation, compteur de planètes, bouton du mode et
//  bouton des préférences.
//  Mode contemplation : un clic (ou un toucher) dans l'espace fait apparaître un trou noir.
//  Mode jeu : appuyer vise (ligne pointillée), relâcher lance la planète du joueur dans
//  cette direction ; elle continue ensuite tout droit.
//

import SwiftUI

struct ContentView: View {
    @State private var simulation = Simulation()
    @State private var showPreferences = false
    /// Vrai pendant que le doigt est appuyé ; revient à faux même si le geste est interrompu
    /// (appel, centre de contrôle…), pour effacer la ligne de visée.
    @GestureState private var pressing = false
    @AppStorage(PrefKey.showBackground) private var showBackground = SimulationSettings.defaults.showBackground
    @AppStorage(PrefKey.showPlanetCount) private var showPlanetCount = SimulationSettings.defaults.showPlanetCount
    @AppStorage(PrefKey.gameMode) private var gameMode = SimulationSettings.defaults.gameMode

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
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($pressing) { _, state, _ in state = true }
                        .onChanged { value in
                            if gameMode { simulation.aim(at: value.location) }
                        }
                        .onEnded { value in
                            if gameMode {
                                simulation.launch(toward: value.location)
                            } else if hypot(value.translation.width, value.translation.height) < 10 {
                                // Un simple toucher (sans glisser) crée un trou noir.
                                simulation.addBlackHole(at: value.location)
                            }
                        }
                )
                .onChange(of: pressing) { _, isPressing in
                    if !isPressing { simulation.aim(at: nil) }
                }
                .accessibilityLabel("Espace")
                .accessibilityHint(gameMode
                    ? "Touchez pour lancer votre planète dans cette direction"
                    : "Touchez pour créer un trou noir")
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            controls
                .padding(12)
        }
        .overlay(alignment: .topLeading) {
            if gameMode {
                GameHUD(simulation: simulation)
                    .padding(12)
            }
        }
        .overlay {
            if gameMode {
                GameOverCard(simulation: simulation) {
                    gameMode = false
                }
            }
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
            ControlButton(systemImage: gameMode ? "sparkles" : "gamecontroller.fill",
                          label: gameMode ? "Mode contemplation" : "Mode jeu : deviens un soleil") {
                gameMode.toggle()
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
            // Text("\(count) planète\(count > 1 ? "s" : "")")
            Text("\(count)")
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

/// Mode jeu : progression vers le soleil et chrono, rafraîchis 10 fois par seconde.
private struct GameHUD: View {
    let simulation: Simulation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let progress = simulation.playerProgress
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 120 * progress)
                }
                .frame(width: 120, height: 8)
                Text(formatDuration(simulation.gameTime))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression vers le soleil")
    }
}

/// Mode jeu : carte de fin de partie (victoire ou défaite), avec « Rejouer ».
private struct GameOverCard: View {
    let simulation: Simulation
    let onContemplate: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            switch simulation.gameState {
            case .playing:
                Color.clear.allowsHitTesting(false)
            case .won(let duration):
                card(title: "Tu es devenu un soleil !",
                     message: "En \(formatDuration(duration))" + bestTimeText,
                     symbol: "sun.max.fill", tint: .orange)
            case .lost(let reason):
                card(title: "Perdu", message: reason + bestTimeText,
                     symbol: "burst.fill", tint: .red)
            }
        }
    }

    private var bestTimeText: String {
        simulation.bestTime.map { "\nMeilleur temps : \(formatDuration($0))" } ?? ""
    }

    private func card(title: String, message: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(tint)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Contemplation", action: onContemplate)
                    .buttonStyle(.bordered)
                Button("Rejouer") { simulation.requestReset() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
    }
}

/// Durée au format minutes:secondes.
private func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
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
