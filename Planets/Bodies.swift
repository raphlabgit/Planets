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
}

struct BlackHole: Identifiable {
    let id: Int
    let position: Vec2
    let birth: Double
    /// Durée de vie en secondes.
    let lifetime: Double
    /// Diamètre de l'horizon : toute planète qui y entre est absorbée.
    let size: Double
    /// Masse totale absorbée (pour information).
    var swallowedMass: Double = 0

    func age(at time: Double) -> Double { time - birth }

    func isExpired(at time: Double) -> Bool { age(at: time) >= lifetime }

    /// 0 → 1 à l'apparition, 1 pendant la vie, 1 → 0 quand il s'évanouit.
    func intensity(at time: Double) -> Double {
        let age = age(at: time)
        let fadeIn = min(0.5, lifetime * 0.2)
        let fadeOut = min(1.5, lifetime * 0.4)
        let rampIn = fadeIn > 0 ? age / fadeIn : 1
        let rampOut = fadeOut > 0 ? (lifetime - age) / fadeOut : 1
        return min(1, max(0, min(rampIn, rampOut)))
    }

    /// Angle de rotation (radians) : le trou noir tourne de plus en plus vite,
    /// comme l'image tournante de l'ancienne version.
    func rotation(at time: Double) -> Double {
        let age = age(at: time)
        return -(age * 1.5 + age * age * 0.12)
    }
}
