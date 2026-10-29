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
//  Mode jeu « Deviens un soleil » : le joueur pilote sa planète (doigt ou souris), absorbe
//  les plus petites et doit fuir les plus grosses. Il gagne en devenant un soleil (80 % de
//  la taille critique) ; il perd s'il est percuté par plus gros, avalé par un trou noir ou
//  s'il dépasse la taille critique et explose.
//
//  La classe n'est volontairement pas observable : elle est avancée par la vue à
//  chaque image (TimelineView) et ne déclenche donc aucune mise à jour SwiftUI.
//

import CoreGraphics
import Foundation

final class Simulation {
    private(set) var planets: [Planet] = []
    private(set) var blackHoles: [BlackHole] = []
    /// Chocs récents sur les grosses planètes, pour l'animation d'impact.
    private(set) var impacts: [Impact] = []
    /// Temps de simulation en secondes.
    private(set) var time: Double = 0
    private(set) var bounds = CGSize.zero
    private(set) var settings = SimulationSettings.load()

    private var lastDate: Date?
    private var nextID = 0
    private var needsReset = true
    private var emptySince: Double?

    // MARK: Mode jeu

    /// Vrai en mode jeu, faux en mode contemplation.
    private(set) var isGame = false
    private(set) var gameState = GameState.playing
    /// Durée de la partie en cours (s'arrête à la victoire ou à la défaite).
    private(set) var gameTime: Double = 0
    /// Identifiant de la planète du joueur (nil en contemplation ou après une défaite).
    private(set) var playerID: Int?
    /// Point vers lequel le joueur dirige sa planète (doigt ou souris enfoncé).
    private var steerTarget: Vec2?
    private var nextBlackHoleTime: Double = 0
    private var nextSpawnTime: Double = 0

    /// Constante de gravitation de base, multipliée par le réglage « Gravité ».
    static let baseG = 300.0
    /// Adoucissement de la gravité (points) pour éviter la singularité à distance nulle.
    static let softening = 6.0
    static let maxSpeed = 500.0
    /// Limite de sécurité pour éviter les réactions en chaîne d'explosions.
    static let maxPlanets = 100
    /// Durée pendant laquelle les fragments d'une explosion ne fusionnent pas.
    static let fragmentImmunity = 0.8
    /// Pas d'intégration fixe : la physique reste stable quelle que soit la fréquence d'affichage.
    static let fixedStep = 1.0 / 120.0
    /// Masse d'un trou noir par point² de surface d'horizon, avant le réglage « Force ».
    static let blackHoleDensity = 4.0
    /// Nombre maximal d'animations d'impact simultanées.
    static let maxImpacts = 40
    /// Vitesse maximale de la planète du joueur vers le doigt (points/s, pour la fenêtre de référence).
    static let playerSpeed = 260.0
    /// Rapidité avec laquelle la planète du joueur obéit au doigt (1/s).
    static let playerResponse = 4.0
    /// Freinage de la planète du joueur quand le doigt est levé (1/s).
    static let playerDrag = 0.9
    /// La planète du joueur ralentit en grossissant, mais garde au moins cette mobilité.
    static let playerMinMobility = 0.35
    /// En mode jeu, on gagne en devenant un soleil : 80 % de la taille critique.
    static let sunThreshold = 0.8
    /// Clé UserDefaults du meilleur temps pour devenir un soleil.
    static let bestTimeKey = "bestSunTime"

    /// La planète du joueur, si elle existe encore.
    var player: Planet? {
        guard let playerID else { return nil }
        return planets.first { $0.id == playerID }
    }

    /// Progression vers le soleil : 0 au départ, 1 à la victoire.
    var playerProgress: Double {
        guard let player else { return gameState.isWon ? 1 : 0 }
        return min(1, player.size / (settings.criticalSize * Self.sunThreshold))
    }

    /// Meilleur temps enregistré pour devenir un soleil, en secondes.
    var bestTime: Double? {
        let value = UserDefaults.standard.double(forKey: Self.bestTimeKey)
        return value > 0 ? value : nil
    }

    // MARK: - Commandes

    /// Recrée les planètes de départ à la prochaine image (avec la taille de fenêtre actuelle).
    func requestReset() {
        needsReset = true
    }

    /// Mode jeu : dirige la planète du joueur vers ce point (nil quand le doigt est levé).
    func steer(to point: CGPoint?) {
        steerTarget = point.map { Vec2($0) }
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
        let preferences = SimulationSettings.load()
        settings = preferences
        guard size.width > 1, size.height > 1 else { return }
        // Tailles proportionnelles à la fenêtre : plus petites sur iPhone que sur iPad ou Mac.
        settings = preferences.scaled(for: size)
        if size != bounds {
            fit(to: size)
        }
        if settings.gameMode != isGame {
            isGame = settings.gameMode
            needsReset = true
        }

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

    /// Adapte la scène à la nouvelle taille de la fenêtre (premier affichage, redimensionnement,
    /// rotation de l'écran) : positions mises à l'échelle pour garder la même répartition, et
    /// tailles ajustées comme les réglages (voir `SimulationSettings.scaled(for:)`), pour que
    /// les planètes gardent la même taille par rapport à la taille critique.
    private func fit(to size: CGSize) {
        let old = bounds
        bounds = size
        guard old.width > 1, old.height > 1 else { return }
        let sx = Double(size.width / old.width)
        let sy = Double(size.height / old.height)
        let ks = SimulationSettings.sizeScale(for: size) / SimulationSettings.sizeScale(for: old)
        for i in planets.indices {
            planets[i].position.x *= sx
            planets[i].position.y *= sy
            planets[i].size *= ks
        }
        for h in blackHoles.indices {
            blackHoles[h].position.x *= sx
            blackHoles[h].position.y *= sy
            blackHoles[h].size *= ks
        }
    }

    private func reset() {
        needsReset = false
        time = 0
        emptySince = nil
        blackHoles.removeAll()
        impacts.removeAll()
        planets = (0..<max(0, settings.planetCount)).map { _ in randomPlanet() }
        playerID = nil
        steerTarget = nil
        gameState = .playing
        gameTime = 0
        if isGame {
            startGame()
        }
    }

    // MARK: - Mode jeu

    /// Place la planète du joueur au centre, un peu plus grosse que la moyenne, et dégage
    /// les planètes trop proches pour laisser un départ tranquille.
    private func startGame() {
        let center = Vec2(x: Double(bounds.width) / 2, y: Double(bounds.height) / 2)
        let clearance = Double(min(bounds.width, bounds.height)) * 0.2
        planets.removeAll { ($0.position - center).length < clearance }
        let player = Planet(
            id: makeID(),
            position: center,
            velocity: .zero,
            size: settings.maxSize * 1.2,
            immuneUntil: time + 1.5
        )
        playerID = player.id
        planets.append(player)
        nextBlackHoleTime = time + Double.random(in: 8...12)
        nextSpawnTime = time
    }

    private func endGame(_ state: GameState) {
        guard isGame, gameState == .playing else { return }
        gameState = state
        steerTarget = nil
        if case .won(let duration) = state, bestTime.map({ duration < $0 }) ?? true {
            UserDefaults.standard.set(duration, forKey: Self.bestTimeKey)
        }
    }

    /// À chaque pas en mode jeu : chrono, victoire, nouvelles planètes pour nourrir le
    /// joueur, et trous noirs pièges qui apparaissent d'eux-mêmes.
    private func updateGame(_ h: Double) {
        guard isGame else { return }
        if gameState == .playing {
            gameTime += h
            if let player, player.size >= settings.criticalSize * Self.sunThreshold {
                endGame(.won(gameTime))
            }
        }

        // De nouvelles petites planètes arrivent par les bords quand il en reste peu.
        let others = planets.count - (playerID == nil ? 0 : 1)
        if time >= nextSpawnTime, others < max(5, settings.planetCount / 2) {
            planets.append(edgePlanet())
            nextSpawnTime = time + 0.5
        }

        // Un trou noir piège apparaît de temps en temps, loin du joueur.
        if blackHoles.isEmpty, time >= nextBlackHoleTime {
            let spot = randomPoint(awayFrom: player?.position, distance: Double(min(bounds.width, bounds.height)) / 3)
            addBlackHole(at: spot.cgPoint)
            nextBlackHoleTime = time + settings.blackHoleLifetime + Double.random(in: 6...12)
        }
    }

    /// Petite planète qui entre par un bord de la fenêtre, en direction de l'intérieur.
    private func edgePlanet() -> Planet {
        var planet = randomPlanet()
        let width = Double(bounds.width)
        let height = Double(bounds.height)
        switch Int.random(in: 0..<4) {
        case 0: planet.position = Vec2(x: 0, y: Double.random(in: 0..<height))
        case 1: planet.position = Vec2(x: width, y: Double.random(in: 0..<height))
        case 2: planet.position = Vec2(x: Double.random(in: 0..<width), y: 0)
        default: planet.position = Vec2(x: Double.random(in: 0..<width), y: height)
        }
        let center = Vec2(x: width / 2, y: height / 2)
        let inward = center - planet.position
        let distance = max(1, inward.length)
        planet.velocity = inward / distance * max(20, settings.initialSpeed) * Double.random(in: 0.5...1)
        return planet
    }

    /// Point au hasard dans la fenêtre, si possible à au moins `distance` de `origin`.
    private func randomPoint(awayFrom origin: Vec2?, distance: Double) -> Vec2 {
        var point = Vec2.zero
        for _ in 0..<12 {
            point = Vec2(
                x: Double.random(in: 0..<max(1, Double(bounds.width))),
                y: Double.random(in: 0..<max(1, Double(bounds.height)))
            )
            guard let origin else { return point }
            if (point - origin).length >= distance { return point }
        }
        return point
    }

    private func step(_ h: Double) {
        time += h
        applyForces(h)
        resolveCollisions()
        absorbIntoBlackHoles()
        explodeOversizedPlanets()
        planets.removeAll { !$0.alive }
        releaseExpiredBlackHoles()
        impacts.removeAll { $0.progress(at: time) >= 1 }
        updateGame(h)
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

        // Mode jeu : la planète du joueur file vers le doigt et ralentit en arrivant dessus
        // (sans tourner autour) ; doigt levé, elle est simplement freinée.
        var playerIndex: Int?
        if let playerID, gameState == .playing {
            playerIndex = planets.firstIndex { $0.id == playerID }
        }
        if let index = playerIndex {
            if let target = steerTarget {
                let toward = target - positions[index]
                let distance = toward.length
                let mobility = playerMobility(planets[index])
                let speed = min(Self.playerSpeed * SimulationSettings.sizeScale(for: bounds), distance * 4)
                let wanted = distance > 0.5 ? toward * (speed / distance / mobility) : .zero
                acceleration[index] += (wanted - planets[index].velocity) * Self.playerResponse
            } else {
                acceleration[index] -= planets[index].velocity * Self.playerDrag
            }
        }

        let width = Double(bounds.width)
        let height = Double(bounds.height)
        for i in 0..<n {
            var p = planets[i]
            p.velocity = (p.velocity + acceleration[i] * h).clamped(maxLength: Self.maxSpeed)
            let mobility = i == playerIndex ? playerMobility(p) : p.mobility(reference: settings.maxSize)
            p.position += p.velocity * (h * mobility)
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

    /// Comme les autres planètes, celle du joueur ralentit en grossissant, mais moins :
    /// elle reste pilotable jusqu'au soleil.
    private func playerMobility(_ planet: Planet) -> Double {
        max(Self.playerMinMobility, planet.mobility(reference: settings.maxSize))
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
        if b.id == playerID {
            playerID = nil
            endGame(.lost("Percuté par une planète plus grosse"))
        }

        // Seules les grosses planètes (40 % de la taille critique et plus) réagissent au choc.
        if planets[big].size >= settings.criticalSize * 0.4, impacts.count < Self.maxImpacts {
            let toward = b.position - a.position
            let distance = toward.length
            impacts.append(Impact(
                planetID: a.id,
                direction: distance > 0 ? toward / distance : Vec2(angle: Double.random(in: 0..<(2 * .pi)), length: 1),
                birth: time
            ))
        }
    }

    // MARK: - Trous noirs

    private func absorbIntoBlackHoles() {
        for h in blackHoles.indices {
            let hole = blackHoles[h]
            let horizon = hole.size / 2 * hole.scale(at: time)
            for i in planets.indices where planets[i].alive {
                let reach = horizon + planets[i].radius * 0.3
                if (planets[i].position - hole.position).lengthSquared < reach * reach {
                    planets[i].alive = false
                    blackHoles[h].swallowedMass += planets[i].mass
                    if planets[i].id == playerID {
                        playerID = nil
                        endGame(.lost("Avalé par un trou noir"))
                    }
                }
            }
        }
    }

    /// En disparaissant, le trou noir explose et relâche toute la masse qu'il a avalée.
    private func releaseExpiredBlackHoles() {
        for hole in blackHoles where hole.isExpired(at: time) && hole.swallowedMass > 0 {
            planets += scatter(
                mass: hole.swallowedMass,
                around: hole.position,
                spread: hole.size / 2,
                velocity: .zero,
                pieceSize: max(2, (settings.minSize + settings.maxSize) / 2),
                speed: settings.explosionSpeed
            )
        }
        blackHoles.removeAll { $0.isExpired(at: time) }
    }

    /// Répartit une masse en planètes projetées dans toutes les directions (explosion d'un trou
    /// noir, explosion finale de la dernière planète). La masse est conservée. Le nombre de
    /// planètes est `count` s'il est donné, sinon autant qu'il en faut pour qu'elles fassent
    /// environ `pieceSize`.
    private func scatter(mass: Double, around center: Vec2, spread: Double, velocity: Vec2,
                         pieceSize: Double = 1, count: Int? = nil, speed: Double) -> [Planet] {
        let room = max(1, Self.maxPlanets - planets.count)
        let wanted = count ?? Int((mass / (pieceSize * pieceSize)).rounded())
        let pieces = min(room, max(1, wanted))
        let weights = (0..<pieces).map { _ in Double.random(in: 0.5...1.5) }
        let totalWeight = weights.reduce(0, +)

        return weights.map { weight in
            let direction = Vec2(angle: Double.random(in: 0..<(2 * .pi)), length: 1)
            // Taille plafonnée sous la taille critique pour éviter une explosion en chaîne immédiate.
            let size = min((mass * weight / totalWeight).squareRoot(), settings.criticalSize * 0.9)
            return Planet(
                id: makeID(),
                position: center + direction * (spread * Double.random(in: 0.2...1)),
                velocity: velocity + direction * speed * Double.random(in: 0.6...1.4),
                size: size,
                immuneUntil: time + Self.fragmentImmunity
            )
        }
    }

    // MARK: - Explosions

    private func explodeOversizedPlanets() {
        var fragments: [Planet] = []
        for i in planets.indices where planets[i].alive && planets[i].size > settings.criticalSize {
            planets[i].alive = false
            if planets[i].id == playerID {
                playerID = nil
                endGame(.lost("Trop gros : tu as dépassé la taille critique et explosé"))
            }
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
                velocity: parent.velocity * parent.mobility(reference: settings.maxSize) + direction * speed,
                size: (parent.mass * weight / totalWeight).squareRoot(),
                immuneUntil: time + Self.fragmentImmunity
            )
        }
    }

    /// S'il ne reste qu'une planète et plus de trou noir actif, elle explose en
    /// autant de petites planètes que le « Nombre de planètes » des préférences, et l'animation
    /// continue. S'il n'en reste aucune, l'animation recommence depuis le début après un court instant.
    private func keepAlive() {
        // En mode jeu, de nouvelles planètes arrivent par les bords (voir `updateGame`).
        guard !isGame, blackHoles.isEmpty, planets.count <= 1 else {
            emptySince = nil
            return
        }
        if let last = planets.first {
            let count = max(2, settings.planetCount)
            // Éclats d'au moins 1 px en moyenne, sinon on recommence plutôt depuis le début.
            if last.mass / Double(count) >= 1 {
                planets = scatter(
                    mass: last.mass,
                    around: last.position,
                    spread: last.radius,
                    velocity: last.velocity * last.mobility(reference: settings.maxSize),
                    count: count,
                    speed: settings.explosionSpeed
                )
                emptySince = nil
                return
            }
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

/// État d'une partie en mode jeu.
enum GameState: Equatable {
    case playing
    /// Devenu un soleil, avec le temps mis en secondes.
    case won(Double)
    /// Partie perdue, avec la raison à afficher.
    case lost(String)

    var isWon: Bool {
        if case .won = self { return true }
        return false
    }
}
