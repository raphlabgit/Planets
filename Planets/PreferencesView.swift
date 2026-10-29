//
//  PreferencesView.swift
//  Planets
//
//  Réglages de la simulation (feuille sur iPhone / iPad, fenêtre Réglages sur Mac).
//  Les valeurs sont enregistrées automatiquement.
//

import SwiftUI

struct PreferencesView: View {
    /// Affiché en feuille (bouton OK) ou dans la fenêtre Réglages de macOS.
    var isSheet = true

    @Environment(\.dismiss) private var dismiss

    @AppStorage(PrefKey.planetCount) private var planetCount = SimulationSettings.defaults.planetCount
    @AppStorage(PrefKey.minSize) private var minSize = SimulationSettings.defaults.minSize
    @AppStorage(PrefKey.maxSize) private var maxSize = SimulationSettings.defaults.maxSize
    @AppStorage(PrefKey.initialSpeed) private var initialSpeed = SimulationSettings.defaults.initialSpeed
    @AppStorage(PrefKey.gravity) private var gravity = SimulationSettings.defaults.gravity
    @AppStorage(PrefKey.criticalSize) private var criticalSize = SimulationSettings.defaults.criticalSize
    @AppStorage(PrefKey.explosionSpeed) private var explosionSpeed = SimulationSettings.defaults.explosionSpeed
    @AppStorage(PrefKey.edgeMode) private var edgeMode = SimulationSettings.defaults.edgeMode.rawValue
    @AppStorage(PrefKey.blackHoleLifetime) private var blackHoleLifetime = SimulationSettings.defaults.blackHoleLifetime
    @AppStorage(PrefKey.blackHoleSize) private var blackHoleSize = SimulationSettings.defaults.blackHoleSize
    @AppStorage(PrefKey.blackHoleStrength) private var blackHoleStrength = SimulationSettings.defaults.blackHoleStrength
    @AppStorage(PrefKey.showBackground) private var showBackground = SimulationSettings.defaults.showBackground
    @AppStorage(PrefKey.colorBySize) private var colorBySize = SimulationSettings.defaults.colorBySize
    @AppStorage(PrefKey.showVectors) private var showVectors = SimulationSettings.defaults.showVectors

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SliderRow(title: "Nombre de planètes", value: planetCountBinding, range: 2...100, step: 1) {
                        "\(Int($0))"
                    }
                    SliderRow(title: "Taille minimale", value: $minSize, range: 2...30, step: 1) { "\(Int($0)) px" }
                    SliderRow(title: "Taille maximale", value: $maxSize, range: 2...30, step: 1) { "\(Int($0)) px" }
                    SliderRow(title: "Vitesse initiale max.", value: $initialSpeed, range: 0...200, step: 5) {
                        "\(Int($0)) px/s"
                    }
                    Button {
                        NotificationCenter.default.post(name: .planetsReset, object: nil)
                        if isSheet { dismiss() }
                    } label: {
                        Label("Réinitialiser l'animation", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Lancement")
                } footer: {
                    Text("Ces réglages s'appliquent à la prochaine réinitialisation. Les tailles sont données pour une fenêtre de 720 px de côté et s'adaptent à la taille réelle de l'écran (plus petites sur iPhone).")
                }

                Section("Physique") {
                    SliderRow(title: "Gravité", value: $gravity, range: 0...10, step: 0.1) {
                        String(format: "× %.1f", $0)
                    }
                    SliderRow(title: "Taille critique avant explosion", value: $criticalSize, range: 15...150, step: 1) {
                        "\(Int($0)) px"
                    }
                    SliderRow(title: "Puissance des explosions", value: $explosionSpeed, range: 50...500, step: 10) {
                        "\(Int($0)) px/s"
                    }
                    Picker("Bords de la fenêtre", selection: $edgeMode) {
                        ForEach(EdgeMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Trou noir") {
                    SliderRow(title: "Durée de vie", value: $blackHoleLifetime, range: 1...60, step: 1) {
                        "\(Int($0)) s"
                    }
                    SliderRow(title: "Taille", value: $blackHoleSize, range: 20...200, step: 5) { "\(Int($0)) px" }
                    SliderRow(title: "Force d'attraction", value: $blackHoleStrength, range: 0...5, step: 0.1) {
                        String(format: "× %.1f", $0)
                    }
                }

                Section("Affichage") {
                    Toggle("Fond étoilé", isOn: $showBackground)
                    Toggle("Couleur selon la taille", isOn: $colorBySize)
                    Toggle("Vecteurs vitesse", isOn: $showVectors)
                }

                Section {
                    Button("Rétablir les valeurs par défaut", role: .destructive) {
                        SimulationSettings.resetToDefaults()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Préférences")
            .onChange(of: minSize) { _, newValue in
                if maxSize < newValue { maxSize = newValue }
            }
            .onChange(of: maxSize) { _, newValue in
                if minSize > newValue { minSize = newValue }
            }
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 520, idealHeight: 640)
        #endif
    }

    private var planetCountBinding: Binding<Double> {
        Binding(
            get: { Double(planetCount) },
            set: { planetCount = Int($0) }
        )
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
         format: @escaping (Double) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
        }
    }
}

#Preview {
    PreferencesView()
}
