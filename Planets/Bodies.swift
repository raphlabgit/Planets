//
//  Bodies.swift
//  Planets
//
//  Les corps de la simulation : planètes et trous noirs
//  (anciennes classes Planete et TrouNoir).
//

import Foundation

struct Planet: Identifiable {
    let id: Int
    var position: Vec2
    var velocity: Vec2
    /// Diamètre en points.
    var size: Double
    /// Instant (temps de simulation) avant lequel la planète ne peut pas fusionner.
    /// Évite que les fragments d'une explosion se recollent immédiatement.
    var immuneUntil: Double = 0
    var alive = true

    var radius: Double { size / 2 }

    /// La masse est définie par la taille : proportionnelle à la surface du disque,
    /// comme dans la version Objective-C ((taille / 2)² × constante).
    var mass: Double { size * size }

    func isImmune(at time: Double) -> Bool { time < immuneUntil }

    /// Part de sa vitesse avec laquelle la planète se déplace réellement : la vitesse est
    /// inversement proportionnelle à la taille. Jusqu'à `reference` (la taille maximale
    /// au lancement) la planète bouge normalement ; deux fois plus grosse, deux fois moins vite.
    func mobility(reference: Double) -> Double {
        min(1, max(1, reference) / size)
    }
}

struct BlackHole: Identifiable {
    let id: Int
    let position: Vec2
    let birth: Double
    /// Durée de vie en secondes.
    let lifetime: Double
    /// Diamètre de l'horizon : toute planète qui y entre est absorbée.
    let size: Double
    /// Masse totale absorbée, relâchée quand le trou noir disparaît.
    var swallowedMass: Double = 0

    func age(at time: Double) -> Double { time - birth }

    func isExpired(at time: Double) -> Bool { age(at: time) >= lifetime }

    private var fadeIn: Double { min(0.5, lifetime * 0.2) }
    private var fadeOut: Double { min(1.5, lifetime * 0.4) }

    /// Progression de l'apparition : 0 → 1.
    private func rampIn(at time: Double) -> Double {
        fadeIn > 0 ? min(1, max(0, age(at: time) / fadeIn)) : 1
    }

    /// Progression de la disparition : 1 pendant la vie, puis 1 → 0.
    private func rampOut(at time: Double) -> Double {
        fadeOut > 0 ? min(1, max(0, (lifetime - age(at: time)) / fadeOut)) : 1
    }

    /// 0 → 1 à l'apparition, 1 pendant la vie, 1 → 0 quand il s'évanouit.
    func intensity(at time: Double) -> Double {
        min(rampIn(at: time), rampOut(at: time))
    }

    /// Échelle d'affichage et de l'horizon : il grandit en apparaissant, puis gonfle
    /// de plus en plus vite (jusqu'à ×1,8) juste avant d'exploser.
    func scale(at time: Double) -> Double {
        let growIn = 0.6 + 0.4 * rampIn(at: time)
        let progress = 1 - rampOut(at: time)
        return growIn * (1 + 0.8 * progress * progress)
    }

    /// Opacité d'affichage : le trou noir reste bien visible pendant qu'il gonfle
    /// et ne s'efface que dans les derniers instants, au moment de l'explosion.
    func opacity(at time: Double) -> Double {
        let progress = 1 - rampOut(at: time)
        let vanish = progress < 0.85 ? 1 : (1 - progress) / 0.15
        return min(rampIn(at: time), vanish)
    }

    /// Angle de rotation (radians) : le trou noir tourne de plus en plus vite,
    /// comme l'image tournante de l'ancienne version.
    func rotation(at time: Double) -> Double {
        let age = age(at: time)
        return -(age * 1.5 + age * age * 0.12)
    }
}
