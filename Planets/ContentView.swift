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
                // En jeu, le fond tremble avec les planètes lors d'une défaite.
                TimelineView(.animation(minimumInterval: nil, paused: !gameMode)) { _ in
                    Color.clear
                        .overlay {
                            // Légèrement agrandi pour que la secousse ne découvre pas les bords.
                            Image("Space")
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(gameMode ? 1.04 : 1)
                                .offset(simulation.defeatShake())
                        }
                        .clipped()
                }
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
                GameFeedback(simulation: simulation)
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
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let state = simulation.gameState
            ZStack {
                switch state {
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
            // La carte arrive en rebondissant, juste après l'onde de victoire ou l'éclair de défaite.
            // Elle disparaît vite quand on rejoue.
            .animation(state == .playing ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.4).delay(0.35),
                       value: state)
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
                .symbolEffect(.pulse)
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
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

/// Mode jeu : vibrations (à chaque planète absorbée, à la victoire et à la défaite) et jingles.
/// L'état de la partie est relu 20 fois par seconde, sans redessiner l'espace.
private struct GameFeedback: View {
    let simulation: Simulation
    @AppStorage(PrefKey.gameSounds) private var sounds = SimulationSettings.defaults.gameSounds
    @AppStorage(PrefKey.gameHaptics) private var haptics = SimulationSettings.defaults.gameHaptics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            FeedbackTrigger(
                absorptions: simulation.playerAbsorptions,
                absorbedRatio: simulation.lastAbsorbedRatio,
                state: simulation.gameState,
                sounds: sounds,
                haptics: haptics
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Charge les jingles dès l'entrée en jeu, pour qu'ils partent sans délai.
        .onAppear { _ = GameSounds.shared }
    }
}

private struct FeedbackTrigger: View {
    let absorptions: Int
    let absorbedRatio: Double
    let state: GameState
    let sounds: Bool
    let haptics: Bool

    var body: some View {
        Color.clear
            .sensoryFeedback(trigger: absorptions) { old, new in
                // Pas de choc au moment de la victoire ou de la défaite : leur propre vibration suffit.
                guard haptics, new > old, state == .playing else { return nil }
                // Plus la planète avalée est grosse par rapport à la nôtre, plus le choc est fort.
                let weight: SensoryFeedback.Weight = absorbedRatio > 0.3 ? .heavy : absorbedRatio > 0.08 ? .medium : .light
                return .impact(weight: weight, intensity: min(1, 0.5 + absorbedRatio * 1.5))
            }
            .sensoryFeedback(trigger: state) { _, new in
                guard haptics else { return nil }
                switch new {
                case .playing: return nil
                case .won: return .success
                case .lost: return .error
                }
            }
            .onChange(of: state) { _, new in
                guard sounds else { return }
                switch new {
                case .playing: break
                case .won: GameSounds.shared.playWin()
                case .lost: GameSounds.shared.playLose()
                }
            }
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
