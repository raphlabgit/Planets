//
//  SimulationSettings.swift
//  Planets
//
//  Préférences de la simulation, enregistrées dans UserDefaults.
//  Les écrans utilisent @AppStorage avec les mêmes clés ; la simulation relit
//  les valeurs à chaque image, donc tout changement s'applique immédiatement
//  (sauf les réglages de lancement, appliqués à la prochaine réinitialisation).
//

import CoreGraphics
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
    static let showPlanetCount = "showPlanetCount"
    static let gameMode = "gameMode"
    static let gameSounds = "gameSounds"
    static let gameHaptics = "gameHaptics"
    static let shipPlanetCount = "shipPlanetCount"
    static let shipSounds = "shipSounds"

    /// Réglages remis à zéro par « Rétablir les valeurs par défaut » (le mode jeu n'en fait pas partie).
    static let all = [
        planetCount, minSize, maxSize, initialSpeed, gravity, criticalSize, explosionSpeed, edgeMode,
        blackHoleLifetime, blackHoleSize, blackHoleStrength, showBackground, colorBySize, showVectors,
        showPlanetCount, gameSounds, gameHaptics, shipPlanetCount, shipSounds,
    ]
}

struct SimulationSettings {
    var planetCount = 80
    var minSize = 2.0
    var maxSize = 10.0
    var initialSpeed = 80.0
    var gravity = 3.0
    var criticalSize = 80.0
    var explosionSpeed = 600.0
    var edgeMode = EdgeMode.wrap
    var blackHoleLifetime = 10.0
    var blackHoleSize = 60.0
    var blackHoleStrength = 1.0
    var showBackground = true
    var colorBySize = true
    var showVectors = false
    var showPlanetCount = true
    /// Mode jeu « Deviens un soleil » (sinon mode contemplation).
    var gameMode = false
    /// Mode jeu : jingles de victoire et de défaite.
    var gameSounds = true
    /// Mode jeu : vibrations (iPhone) à chaque absorption, à la victoire et à la défaite.
    var gameHaptics = true
    /// Contemplation : le vaisseau ovni apparaît quand il ne reste que ce nombre de planètes,
    /// ou moins (0 : jamais).
    var shipPlanetCount = 5
    /// Contemplation : bruit de blaster à chaque tir du vaisseau.
    var shipSounds = true

    static let defaults = SimulationSettings()

    /// Les tailles des préférences sont données pour une fenêtre de référence dont le petit côté
    /// mesure 720 points (une fenêtre Mac ou un iPad). Sur un écran plus petit, comme l'iPhone,
    /// tout est réduit dans la même proportion : planètes, taille critique et trous noirs.
    static let referenceSide = 720.0

    /// Facteur d'échelle des tailles pour une fenêtre donnée (borné entre 0,4 et 2).
    static func sizeScale(for size: CGSize) -> Double {
        min(2, max(0.4, Double(min(size.width, size.height)) / referenceSide))
    }

    /// Les mêmes réglages, avec les tailles adaptées à la fenêtre.
    func scaled(for size: CGSize) -> SimulationSettings {
        let k = Self.sizeScale(for: size)
        var s = self
        s.minSize *= k
        s.maxSize *= k
        s.criticalSize *= k
        s.blackHoleSize *= k
        return s
    }

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
            PrefKey.showPlanetCount: d.showPlanetCount,
            PrefKey.gameMode: d.gameMode,
            PrefKey.gameSounds: d.gameSounds,
            PrefKey.gameHaptics: d.gameHaptics,
            PrefKey.shipPlanetCount: d.shipPlanetCount,
            PrefKey.shipSounds: d.shipSounds,
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
        s.showPlanetCount = bool(PrefKey.showPlanetCount, s.showPlanetCount)
        s.gameMode = bool(PrefKey.gameMode, s.gameMode)
        s.gameSounds = bool(PrefKey.gameSounds, s.gameSounds)
        s.gameHaptics = bool(PrefKey.gameHaptics, s.gameHaptics)
        s.shipPlanetCount = (store.object(forKey: PrefKey.shipPlanetCount) as? NSNumber)?.intValue ?? s.shipPlanetCount
        s.shipSounds = bool(PrefKey.shipSounds, s.shipSounds)
        return s
    }
}

extension Notification.Name {
    /// Demande de réinitialisation de l'animation (bouton des préférences, menu macOS).
    static let planetsReset = Notification.Name("PlanetsReset")
}
