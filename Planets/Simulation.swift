//
//  Simulation.swift
//  Planets
//
//  Moteur physique (ancienne méthode -calcul: de AppController et PlaneteArray).
//
//  - Chaque planète est attirée par toutes les autres : a = G·m / d² (loi de Newton,
//    avec un léger adoucissement pour éviter les accélérations infinies au contact).
//  - Lors d'un choc, la plus grosse absorbe la plus petite : la masse (surface) et
//    la quantité de mouvement sont conservées, donc la plus grosse grandit.
//  - Au-delà de la taille critique, la planète explose en fragments de tailles,
//    vitesses et directions différentes.
//  - Un trou noir attire fortement les planètes, absorbe celles qui franchissent
//    son horizon, puis s'évanouit à la fin de sa durée de vie.
//
//  La classe n'est volontairement pas observable : elle est avancée par la vue à
//  chaque image (TimelineView) et ne déclenche donc aucune mise à jour SwiftUI.
//

import CoreGraphics
import Foundation

final class Simulation {
    private(set) var planets: [Planet] = []
    private(set) var blackHoles: [BlackHole] = []
    /// Temps de simulation en secondes (s'arrête pendant la pause).
    private(set) var time: Double = 0
    private(set) var bounds = CGSize.zero
    private(set) var settings = SimulationSettings.load()

    private var lastDate: Date?
    private var nextID = 0
    private var needsReset = true
    private var emptySince: Double?

    /// Constante de gravitation de base, multipliée par le réglage « Gravité ».
    static let baseG = 120.0
    /// Adoucissement de la gravité (points) pour éviter la singularité à distance nulle.
    static let softening = 6.0
    static let maxSpeed = 1500.0
    /// Limite de sécurité pour éviter les réactions en chaîne d'explosions.
    static let maxPlanets = 800
    /// Durée pendant laquelle les fragments d'une explosion ne fusionnent pas.
    static let fragmentImmunity = 0.8
    /// Pas d'intégration fixe : la physique reste stable quelle que soit la fréquence d'affichage.
    static let fixedStep = 1.0 / 120.0
    /// Masse d'un trou noir par point² de surface d'horizon, avant le réglage « Force ».
    static let blackHoleDensity = 4.0

    // MARK: - Commandes

    /// Recrée les planètes de départ à la prochaine image (avec la taille de fenêtre actuelle).
    func requestReset() {
        needsReset = true
    }

    /// À appeler en sortie de pause pour ne pas rattraper le temps écoulé.
    func resetClock() {
        lastDate = nil
    }

    func addBlackHole(at point: CGPoint) {
        blackHoles.append(BlackHole(
            id: makeID(),
            position: Vec2(point),
            birth: time,
            lifetime: max(0.5, settings.blackHoleLifetime),
            size: settings.blackHoleSize
        ))
    }

    // MARK: - Avancement

    /// Avance la simulation jusqu'à `date` dans une zone de taille `size`.
    func update(date: Date, size: CGSize) {
        settings = SimulationSettings.load()
        bounds = size
        guard size.width > 1, size.height > 1 else { return }

        if needsReset {
            reset()
            lastDate = date
            return
        }

        // Au plus 1/20 s par image : après une pause ou un ralentissement, on ne « saute » pas.
        let elapsed = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        var remaining = min(max(elapsed, 0), 0.05)
        while remaining > 1e-6 {
            let h = min(Self.fixedStep, remaining)
            step(h)
            remaining -= h
        }
    }

    private func reset() {
        needsReset = false
        time = 0
        emptySince = nil
        blackHoles.removeAll()
        planets = (0..<max(0, settings.planetCount)).map { _ in randomPlanet() }
    }

    private func step(_ h: Double) {
        time += h
        applyForces(h)
        resolveCollisions()
        absorbIntoBlackHoles()
        explodeOversizedPlanets()
        planets.removeAll { !$0.alive }
        blackHoles.removeAll { $0.isExpired(at: time) }
        keepAlive()
    }

    // MARK: - Gravité et mouvement

    private func applyForces(_ h: Double) {
        let n = planets.count
        guard n > 0 else { return }
        let g = Self.baseG * settings.gravity
        let eps2 = Self.softening * Self.softening
        let positions = planets.map(\.position)
        let masses = planets.map(\.mass)
        var acceleration = [Vec2](repeating: .zero, count: n)

        // Attraction mutuelle des planètes (chaque paire une seule fois).
        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = positions[j] - positions[i]
                let r2 = d.lengthSquared + eps2
                let inv = g / (r2 * r2.squareRoot())
                acceleration[i] += d * (masses[j] * inv)
                acceleration[j] -= d * (masses[i] * inv)
            }
        }

        // Attraction des trous noirs (ils ne bougent pas).
        for hole in blackHoles {
            let intensity = hole.intensity(at: time)
            let mass = hole.size * hole.size * Self.blackHoleDensity * settings.blackHoleStrength * intensity
            let eps = hole.size / 2
            for i in 0..<n {
                let d = hole.position - positions[i]
                let r2 = d.lengthSquared + eps * eps
                acceleration[i] += d * (Self.baseG * mass / (r2 * r2.squareRoot()))
            }
        }

        let width = Double(bounds.width)
        let height = Double(bounds.height)
        for i in 0..<n {
            var p = planets[i]
            p.velocity = (p.velocity + acceleration[i] * h).clamped(maxLength: Self.maxSpeed)
            p.position += p.velocity * h
            switch settings.edgeMode {
            case .wrap:
                p.position.x = wrap(p.position.x, width)
                p.position.y = wrap(p.position.y, height)
            case .bounce:
                bounce(&p.position.x, &p.velocity.x, radius: p.radius, limit: width)
                bounce(&p.position.y, &p.velocity.y, radius: p.radius, limit: height)
            }
            planets[i] = p
        }
    }

    private func wrap(_ value: Double, _ limit: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: limit)
        if v < 0 { v += limit }
        return v
    }

    private func bounce(_ position: inout Double, _ velocity: inout Double, radius: Double, limit: Double) {
        let damping = 0.9
        if position < radius {
            position = radius
            velocity = abs(velocity) * damping
        } else if position > limit - radius {
            position = max(radius, limit - radius)
            velocity = -abs(velocity) * damping
        }
    }

    // MARK: - Chocs

    private func resolveCollisions() {
        let n = planets.count
        for i in 0..<n {
            guard planets[i].alive, !planets[i].isImmune(at: time) else { continue }
            for j in (i + 1)..<n {
                guard planets[i].alive else { break }
                let other = planets[j]
                guard other.alive, !other.isImmune(at: time) else { continue }
                let reach = planets[i].radius + other.radius
                guard (other.position - planets[i].position).lengthSquared < reach * reach else { continue }

                let (big, small) = planets[i].mass >= other.mass ? (i, j) : (j, i)
                merge(small, into: big)
            }
        }
    }

    /// La plus grosse planète absorbe la plus petite : elle grandit, et sa nouvelle
    /// vitesse conserve la quantité de mouvement du couple.
    private func merge(_ small: Int, into big: Int) {
        let a = planets[big]
        let b = planets[small]
        let total = a.mass + b.mass
        planets[big].velocity = (a.velocity * a.mass + b.velocity * b.mass) / total
        planets[big].position = (a.position * a.mass + b.position * b.mass) / total
        planets[big].size = total.squareRoot()
        planets[small].alive = false
    }

    // MARK: - Trous noirs

    private func absorbIntoBlackHoles() {
        for h in blackHoles.indices {
            let hole = blackHoles[h]
            let horizon = hole.size / 2 * (0.4 + 0.6 * hole.intensity(at: time))
            for i in planets.indices where planets[i].alive {
                let reach = horizon + planets[i].radius * 0.3
                if (planets[i].position - hole.position).lengthSquared < reach * reach {
                    planets[i].alive = false
                    blackHoles[h].swallowedMass += planets[i].mass
                }
            }
        }
    }

    // MARK: - Explosions

    private func explodeOversizedPlanets() {
        var fragments: [Planet] = []
        for i in planets.indices where planets[i].alive && planets[i].size > settings.criticalSize {
            planets[i].alive = false
            fragments += makeFragments(of: planets[i], existing: planets.count + fragments.count)
        }
        planets += fragments
    }

    /// Découpe une planète en fragments de tailles, vitesses et directions variées.
    /// La masse totale est conservée ; les fragments partent en étoile autour du centre.
    private func makeFragments(of parent: Planet, existing: Int) -> [Planet] {
        let room = Self.maxPlanets - existing
        let wanted = min(30, Int.random(in: 6...12) + Int(parent.size / 12))
        let count = max(2, min(wanted, room))
        let weights = (0..<count).map { _ in Double.random(in: 0.3...1.0) }
        let totalWeight = weights.reduce(0, +)
        let baseAngle = Double.random(in: 0..<(2 * .pi))

        return (0..<count).map { k in
            let weight = weights[k]
            let angle = baseAngle + 2 * .pi * Double(k) / Double(count) + Double.random(in: -0.25...0.25)
            let direction = Vec2(angle: angle, length: 1)
            let speed = settings.explosionSpeed * Double.random(in: 0.6...1.4)
            return Planet(
                id: makeID(),
                position: parent.position + direction * (parent.radius * 0.5),
                velocity: parent.velocity + direction * speed,
                size: (parent.mass * weight / totalWeight).squareRoot(),
                immuneUntil: time + Self.fragmentImmunity
            )
        }
    }

    /// Comme dans la version d'origine : s'il ne reste qu'une planète, elle explose ;
    /// s'il n'en reste plus du tout, une nouvelle série est lancée.
    private func keepAlive() {
        guard blackHoles.isEmpty, planets.count <= 1 else {
            emptySince = nil
            return
        }
        if let last = planets.first, last.size >= 12 {
            planets = makeFragments(of: last, existing: 0)
            return
        }
        if let since = emptySince {
            if time - since > 1.5 { reset() }
        } else {
            emptySince = time
        }
    }

    // MARK: - Création

    private func randomPlanet() -> Planet {
        let minSize = max(1, settings.minSize)
        let maxSize = max(minSize, settings.maxSize)
        return Planet(
            id: makeID(),
            position: Vec2(
                x: Double.random(in: 0..<max(1, Double(bounds.width))),
                y: Double.random(in: 0..<max(1, Double(bounds.height)))
            ),
            velocity: Vec2(
                angle: Double.random(in: 0..<(2 * .pi)),
                length: Double.random(in: 0...max(0, settings.initialSpeed))
            ),
            size: Double.random(in: minSize...maxSize)
        )
    }

    private func makeID() -> Int {
        nextID += 1
        return nextID
    }
}
