//
//  SimulationSettings.swift
//  Planets
//
//  Préférences de la simulation, enregistrées dans UserDefaults.
//  Les écrans utilisent @AppStorage avec les mêmes clés ; la simulation relit
//  les valeurs à chaque image, donc tout changement s'applique immédiatement
//  (sauf les réglages de lancement, appliqués à la prochaine réinitialisation).
//

import Foundation

enum EdgeMode: String, CaseIterable, Identifiable {
    /// La planète qui sort d'un côté réapparaît de l'autre (comportement d'origine).
    case wrap
    /// La planète rebondit sur les bords de la fenêtre.
    case bounce

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wrap: "Traverser"
        case .bounce: "Rebondir"
        }
    }
}

enum PrefKey {
    static let planetCount = "planetCount"
    static let minSize = "minSize"
    static let maxSize = "maxSize"
    static let initialSpeed = "initialSpeed"
    static let gravity = "gravity"
    static let criticalSize = "criticalSize"
    static let explosionSpeed = "explosionSpeed"
    static let edgeMode = "edgeMode"
    static let blackHoleLifetime = "blackHoleLifetime"
    static let blackHoleSize = "blackHoleSize"
    static let blackHoleStrength = "blackHoleStrength"
    static let showBackground = "showBackground"
    static let colorBySize = "colorBySize"
    static let showVectors = "showVectors"

    static let all = [
        planetCount, minSize, maxSize, initialSpeed, gravity, criticalSize, explosionSpeed, edgeMode,
        blackHoleLifetime, blackHoleSize, blackHoleStrength, showBackground, colorBySize, showVectors,
    ]
}

struct SimulationSettings {
    var planetCount = 100
    var minSize = 4.0
    var maxSize = 10.0
    var initialSpeed = 40.0
    var gravity = 1.0
    var criticalSize = 40.0
    var explosionSpeed = 120.0
    var edgeMode = EdgeMode.wrap
    var blackHoleLifetime = 10.0
    var blackHoleSize = 60.0
    var blackHoleStrength = 1.0
    var showBackground = true
    var colorBySize = true
    var showVectors = false

    static let defaults = SimulationSettings()

    static func registerDefaults(in store: UserDefaults = .standard) {
        let d = defaults
        store.register(defaults: [
            PrefKey.planetCount: d.planetCount,
            PrefKey.minSize: d.minSize,
            PrefKey.maxSize: d.maxSize,
            PrefKey.initialSpeed: d.initialSpeed,
            PrefKey.gravity: d.gravity,
            PrefKey.criticalSize: d.criticalSize,
            PrefKey.explosionSpeed: d.explosionSpeed,
            PrefKey.edgeMode: d.edgeMode.rawValue,
            PrefKey.blackHoleLifetime: d.blackHoleLifetime,
            PrefKey.blackHoleSize: d.blackHoleSize,
            PrefKey.blackHoleStrength: d.blackHoleStrength,
            PrefKey.showBackground: d.showBackground,
            PrefKey.colorBySize: d.colorBySize,
            PrefKey.showVectors: d.showVectors,
        ])
    }

    static func resetToDefaults(in store: UserDefaults = .standard) {
        PrefKey.all.forEach { store.removeObject(forKey: $0) }
    }

    static func load(from store: UserDefaults = .standard) -> SimulationSettings {
        var s = SimulationSettings()
        func double(_ key: String, _ fallback: Double) -> Double {
            (store.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            (store.object(forKey: key) as? NSNumber)?.boolValue ?? fallback
        }
        s.planetCount = (store.object(forKey: PrefKey.planetCount) as? NSNumber)?.intValue ?? s.planetCount
        s.minSize = double(PrefKey.minSize, s.minSize)
        s.maxSize = max(s.minSize, double(PrefKey.maxSize, s.maxSize))
        s.initialSpeed = double(PrefKey.initialSpeed, s.initialSpeed)
        s.gravity = double(PrefKey.gravity, s.gravity)
        s.criticalSize = double(PrefKey.criticalSize, s.criticalSize)
        s.explosionSpeed = double(PrefKey.explosionSpeed, s.explosionSpeed)
        s.edgeMode = store.string(forKey: PrefKey.edgeMode).flatMap(EdgeMode.init(rawValue:)) ?? s.edgeMode
        s.blackHoleLifetime = double(PrefKey.blackHoleLifetime, s.blackHoleLifetime)
        s.blackHoleSize = double(PrefKey.blackHoleSize, s.blackHoleSize)
        s.blackHoleStrength = double(PrefKey.blackHoleStrength, s.blackHoleStrength)
        s.showBackground = bool(PrefKey.showBackground, s.showBackground)
        s.colorBySize = bool(PrefKey.colorBySize, s.colorBySize)
        s.showVectors = bool(PrefKey.showVectors, s.showVectors)
        return s
    }
}

extension Notification.Name {
    /// Demande de réinitialisation de l'animation (bouton des préférences, menu macOS).
    static let planetsReset = Notification.Name("PlanetsReset")
}
