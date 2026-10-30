//
//  Bodies.swift
//  Planets
//
//  Les corps de la simulation : planètes et trous noirs
//  (anciennes classes Planete et TrouNoir), et le vaisseau ovni du mode contemplation.
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
    var position: Vec2
    let birth: Double
    /// Durée de vie en secondes.
    let lifetime: Double
    /// Diamètre de l'horizon : toute planète qui y entre est absorbée.
    var size: Double
    /// Masse totale absorbée, relâchée quand le trou noir disparaît.
    var swallowedMass: Double = 0
    /// Trou noir piège du mode jeu : il naît minuscule, grandit pendant `trapGrowTime`,
    /// puis attire très fort tout ce qui passe près de lui.
    var isTrap = false

    /// Mode jeu : durée de croissance d'un trou noir piège.
    static let trapGrowTime = 2.0
    /// Mode jeu : taille de départ d'un trou noir piège, par rapport à sa taille normale.
    static let trapStartScale = 0.05

    func age(at time: Double) -> Double { time - birth }

    func isExpired(at time: Double) -> Bool { age(at: time) >= lifetime }

    private var fadeIn: Double { isTrap ? Self.trapGrowTime : min(0.5, lifetime * 0.2) }
    private var fadeOut: Double { min(1.5, lifetime * 0.4) }

    /// Progression de l'apparition : 0 → 1.
    private func rampIn(at time: Double) -> Double {
        fadeIn > 0 ? min(1, max(0, age(at: time) / fadeIn)) : 1
    }

    /// Progression de la disparition : 1 pendant la vie, puis 1 → 0.
    private func rampOut(at time: Double) -> Double {
        fadeOut > 0 ? min(1, max(0, (lifetime - age(at: time)) / fadeOut)) : 1
    }

    /// Force de la gravité : 0 → 1 à l'apparition, 1 pendant la vie, 1 → 0 quand il s'évanouit.
    /// Un piège encore en croissance n'attire presque pas : sa force monte comme le carré
    /// de sa croissance.
    func intensity(at time: Double) -> Double {
        let ramp = rampIn(at: time)
        return min(isTrap ? ramp * ramp : ramp, rampOut(at: time))
    }

    /// Vrai une fois la croissance terminée (le piège attire alors à pleine force).
    func isFormed(at time: Double) -> Bool { rampIn(at: time) >= 1 }

    /// Échelle d'affichage et de l'horizon : il grandit en apparaissant (un piège part de
    /// presque rien), puis gonfle de plus en plus vite (jusqu'à ×1,8) juste avant d'exploser.
    func scale(at time: Double) -> Double {
        let start = isTrap ? Self.trapStartScale : 0.6
        let growIn = start + (1 - start) * rampIn(at: time)
        let progress = 1 - rampOut(at: time)
        return growIn * (1 + 0.8 * progress * progress)
    }

    /// Opacité d'affichage : le trou noir reste bien visible pendant qu'il gonfle
    /// et ne s'efface que dans les derniers instants, au moment de l'explosion.
    func opacity(at time: Double) -> Double {
        let progress = 1 - rampOut(at: time)
        let vanish = progress < 0.85 ? 1 : (1 - progress) / 0.15
        // Un piège est bien visible dès sa naissance, même minuscule.
        let appear = isTrap ? min(1, age(at: time) / 0.3) : rampIn(at: time)
        return min(appear, vanish)
    }

    /// Angle de rotation (radians) : le trou noir tourne de plus en plus vite,
    /// comme l'image tournante de l'ancienne version.
    func rotation(at time: Double) -> Double {
        let age = age(at: time)
        return -(age * 1.5 + age * age * 0.12)
    }
}

/// Choc reçu par une grosse planète : petite animation très brève (éclair au point
/// d'impact et onde de choc autour de la planète).
struct Impact {
    let planetID: Int
    /// Direction du point d'impact depuis le centre de la planète.
    let direction: Vec2
    let birth: Double

    static let duration = 0.35

    /// 0 → 1 pendant l'animation.
    func progress(at time: Double) -> Double { (time - birth) / Self.duration }
}

/// Vaisseau ovni du mode contemplation, purement décoratif : sans masse, il traverse l'écran
/// porté par sa vitesse de départ et dévié par la gravité des planètes et des trous noirs.
/// Seule la gravité change sa direction : il ne touche jamais les planètes et passe au-dessus.
/// Il tire au laser sur les planètes devant lui, et un trou noir peut l'avaler.
struct Ship {
    var position: Vec2
    var velocity: Vec2
    let birth: Double
    /// Largeur d'affichage en points.
    var width: Double
    /// Instant (temps de simulation) du prochain tir possible.
    var nextShot: Double
    /// Aspiration par un trou noir : début, centre du trou noir, position de départ et sens
    /// de rotation (+1 ou -1, celui dans lequel il arrivait autour du trou noir).
    var fall: (start: Double, center: Vec2, from: Vec2, turn: Double)?

    /// Largeur du vaisseau dans une fenêtre de référence (720 points de petit côté).
    static let baseWidth = 70.0
    /// Vitesse de départ (points/s) : il traverse l'écran tranquillement.
    static let launchSpeed = 55.0...80.0
    static let maxSpeed = 300.0
    /// Virage maximal sous l'effet de la gravité (radians/s) : sa trajectoire s'infléchit
    /// sans jamais repartir brusquement en arrière.
    static let maxTurnRate = 0.6
    /// Au-delà, il s'éclipse doucement (s'il reste par exemple pris en orbite autour d'une planète).
    static let maxLifetime = 40.0
    static let fadeOut = 1.0
    /// Durée de l'aspiration en spirale dans un trou noir.
    static let fallDuration = 0.8
    /// Portée du laser, en part du petit côté de la fenêtre.
    static let laserRange = 0.45
    /// Demi-angle (radians) du cône de tir devant le vaisseau.
    static let laserCone = 0.35
    /// Délai entre deux tirs (s).
    static let reloadTime = 1.2...2.2
    /// Temps pendant lequel il épargne les débris de son dernier tir (s).
    static let debrisRespite = 3.0

    func age(at time: Double) -> Double { time - birth }

    /// Aspiration par un trou noir : 0 → 1 (nil s'il n'est pas aspiré).
    func fallProgress(at time: Double) -> Double? {
        fall.map { min(1, max(0, (time - $0.start) / Self.fallDuration)) }
    }

    /// Vrai une fois avalé par un trou noir ou à la fin de sa durée de vie.
    func isGone(at time: Double) -> Bool {
        age(at: time) >= Self.maxLifetime || (fallProgress(at: time) ?? 0) >= 1
    }

    /// Position pendant l'aspiration : il tourne autour du trou noir en s'en rapprochant.
    func fallPosition(progress: Double) -> Vec2? {
        guard let fall else { return nil }
        let offset = fall.from - fall.center
        let angle = 3 * .pi * progress * fall.turn
        let shrink = pow(1 - progress, 1.5)
        let turned = Vec2(x: offset.x * cos(angle) - offset.y * sin(angle),
                          y: offset.x * sin(angle) + offset.y * cos(angle))
        return fall.center + turned * shrink
    }

    /// Opacité : il s'efface à la fin de sa durée de vie ou en tombant dans un trou noir.
    func opacity(at time: Double) -> Double {
        let fading = min(1, max(0, (Self.maxLifetime - age(at: time)) / Self.fadeOut))
        return min(fading, 1 - (fallProgress(at: time) ?? 0))
    }
}

/// Tir de laser du vaisseau : rayon très bref et éclair sur la planète touchée.
struct Laser {
    let from: Vec2
    let to: Vec2
    let birth: Double

    static let duration = 0.3

    /// 0 → 1 pendant l'animation.
    func progress(at time: Double) -> Double { (time - birth) / Self.duration }
}
