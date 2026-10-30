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
//  Mode contemplation : quand il reste peu de planètes (5 ou moins par défaut), un vaisseau ovni
//  traverse l'écran (voir `Ship`) et détruit au laser les planètes qui passent devant lui.
//
//  Mode jeu « Deviens un soleil » : le joueur lance sa planète dans une direction (doigt ou
//  souris), absorbe les plus petites et doit fuir les plus grosses. Il gagne en devenant un soleil (80 % de
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
    /// Nombre de planètes absorbées par le joueur pendant la partie (pour la vibration).
    private(set) var playerAbsorptions = 0
    /// Masse de la dernière planète absorbée par rapport à celle du joueur (0 à 1).
    private(set) var lastAbsorbedRatio = 0.0
    /// Instant (temps de simulation) et lieu de la victoire ou de la défaite, pour les animations.
    private(set) var gameEndTime: Double?
    private(set) var gameEndPosition: Vec2?
    /// Point visé pendant que le doigt (ou la souris) est appuyé, pour la ligne de visée.
    private(set) var aimPoint: Vec2?
    /// Direction donnée par le dernier lancer, suivie jusqu'à `launchUntil`.
    private var launchDirection: Vec2?
    /// Vitesse visée par le dernier lancer (points/s).
    private var launchSpeed: Double = 0
    private var launchUntil: Double = 0
    private var nextBlackHoleTime: Double = 0
    private var nextSpawnTime: Double = 0

    // MARK: Vaisseau (contemplation)

    /// Vaisseau ovni qui traverse l'écran quand il reste peu de planètes.
    private(set) var ship: Ship?
    /// Tirs de laser récents, pour l'animation.
    private(set) var lasers: [Laser] = []
    private var nextShipTime: Double = 0
    /// Débris des tirs du vaisseau, avec l'instant jusqu'auquel il les épargne : il ne s'acharne
    /// pas dessus juste après son tir.
    private var shipDebris: [Int: Double] = [:]
    /// Nombre de tirs depuis le début (pour le bruit de blaster).
    private(set) var laserShots = 0

    /// Mode jeu : attraction d'un piège formé, multipliée jusqu'à (1 + trapPull) près de l'horizon
    /// et qui revient à la normale à `trapReach` fois son diamètre.
    static let trapPull = 8.0
    static let trapReach = 5.0
    /// Constante de gravitation de base, multipliée par le réglage « Gravité ».
    static let baseG = 300.0
    /// Adoucissement de la gravité (points) pour éviter la singularité à distance nulle.
    static let softening = 6.0
    static let maxSpeed = 500.0
    /// Les éclats d'une explosion dépassent `maxSpeed` tant qu'ils sont immunisés : sinon ils ne
    /// peuvent pas échapper à leur propre gravité, se regroupent, ré-explosent, et ainsi de suite.
    static let maxFragmentSpeed = 1500.0
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
    /// Vitesse donnée par un lancer à pleine puissance (points/s), avant la mobilité de la planète.
    static let playerSpeed = 320.0
    /// Longueur du trait de visée (en part du petit côté de la fenêtre) qui donne la pleine puissance.
    static let fullPowerAim = 0.35
    /// Temps de réaction d'une planète : après un lancer, elle met environ ce temps (s) à
    /// prendre sa nouvelle direction, puis elle continue tout droit.
    static let playerTurnTime = 1.0
    /// Rapidité avec laquelle la planète prend sa nouvelle direction pendant ce temps (1/s).
    static let playerResponse = 3.0
    /// La planète du joueur ralentit en grossissant, mais garde au moins cette mobilité.
    static let playerMinMobility = 0.5
    /// Relâcher le doigt sur sa propre planète (ou tout près) ne la lance pas.
    static let aimDeadZone = 4.0
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

    /// Mode jeu : point visé pendant que le doigt est appuyé (nil quand il est levé).
    func aim(at point: CGPoint?) {
        aimPoint = isGame && gameState == .playing ? point.map { Vec2($0) } : nil
    }

    /// Mode jeu : lance la planète du joueur vers ce point. Elle prend cette direction en
    /// `playerTurnTime` environ, puis continue tout droit jusqu'au prochain lancer.
    func launch(toward point: CGPoint) {
        aimPoint = nil
        guard isGame, gameState == .playing, let player, let shot = aim(from: player, to: Vec2(point)) else { return }
        launchDirection = shot.direction
        launchSpeed = Self.playerSpeed * shot.power
        launchUntil = time + Self.playerTurnTime
    }

    /// Visée comme une fronde : la direction va de la planète vers le doigt, et la puissance
    /// (0 à 1) grandit avec la longueur du trait, au-delà du bord de la planète. Nil si le doigt
    /// est sur la planète elle-même.
    func aim(from player: Planet, to point: Vec2) -> (direction: Vec2, power: Double, start: Double, end: Double)? {
        let toward = point - player.position
        let distance = toward.length
        let start = player.radius + Self.aimDeadZone
        guard distance > start else { return nil }
        let full = Self.fullPowerAim * Double(min(bounds.width, bounds.height))
        let length = min(distance - start, full)
        return (toward / distance, length / max(1, full), start, start + length)
    }

    func addBlackHole(at point: CGPoint) {
        addBlackHole(at: Vec2(point), trap: false)
    }

    private func addBlackHole(at position: Vec2, trap: Bool) {
        // Un piège doit vivre assez longtemps pour grandir puis rester un moment à pleine force.
        let minimum = trap ? BlackHole.trapGrowTime + 3 : 0.5
        blackHoles.append(BlackHole(
            id: makeID(),
            position: position,
            birth: time,
            lifetime: max(minimum, settings.blackHoleLifetime),
            size: settings.blackHoleSize,
            isTrap: trap
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
        // Le vaisseau garde sa place relative ; s'il était en train de tomber, il disparaît.
        if ship?.fall != nil {
            removeShip()
        }
        ship?.position.x *= sx
        ship?.position.y *= sy
        ship?.width *= ks
        lasers.removeAll()
    }

    private func reset() {
        needsReset = false
        time = 0
        emptySince = nil
        blackHoles.removeAll()
        impacts.removeAll()
        ship = nil
        lasers.removeAll()
        shipDebris.removeAll()
        nextShipTime = 2
        planets = (0..<max(0, settings.planetCount)).map { _ in randomPlanet() }
        playerID = nil
        aimPoint = nil
        launchDirection = nil
        gameState = .playing
        gameTime = 0
        playerAbsorptions = 0
        lastAbsorbedRatio = 0
        gameEndTime = nil
        gameEndPosition = nil
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

    private func endGame(_ state: GameState, at position: Vec2) {
        guard isGame, gameState == .playing else { return }
        gameState = state
        gameEndTime = time
        gameEndPosition = position
        aimPoint = nil
        launchDirection = nil
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
                endGame(.won(gameTime), at: player.position)
            }
        }

        // De nouvelles petites planètes arrivent par les bords quand il en reste peu.
        let others = planets.count - (playerID == nil ? 0 : 1)
        if time >= nextSpawnTime, others < max(5, settings.planetCount / 2) {
            planets.append(edgePlanet())
            nextSpawnTime = time + 0.5
        }

        // Un trou noir piège apparaît de temps en temps, loin du joueur : minuscule, il grandit
        // pendant 2 s (le temps de s'éloigner), puis attire très fort tout ce qui passe près.
        if blackHoles.isEmpty, time >= nextBlackHoleTime {
            let spot = randomPoint(awayFrom: player?.position, distance: Double(min(bounds.width, bounds.height)) / 3)
            addBlackHole(at: spot, trap: true)
            nextBlackHoleTime = time + (blackHoles.last?.lifetime ?? 0) + Double.random(in: 6...12)
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

    /// Défaite : décalage de l'espace (planètes et fond étoilé), qui tremble pendant une
    /// demi-seconde, de moins en moins fort.
    func defeatShake() -> CGSize {
        guard case .lost = gameState, let end = gameEndTime else { return .zero }
        let t = time - end
        guard t >= 0, t < Self.shakeDuration else { return .zero }
        let amplitude = 9 * (1 - t / Self.shakeDuration)
        return CGSize(width: amplitude * sin(t * 71), height: amplitude * cos(t * 53))
    }

    private static let shakeDuration = 0.5

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
        updateShip(h)
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
            // Piège formé du mode jeu : attraction bien plus forte à courte distance.
            let reach = hole.isTrap && hole.isFormed(at: time) ? hole.size * hole.scale(at: time) * Self.trapReach : 0
            for i in 0..<n {
                let d = hole.position - positions[i]
                let r2 = d.lengthSquared + eps * eps
                var pull = Self.baseG * mass / (r2 * r2.squareRoot())
                if reach > 0 {
                    pull *= 1 + Self.trapPull * max(0, 1 - d.length / reach)
                }
                acceleration[i] += d * pull
            }
        }

        // Mode jeu : après un lancer, la planète du joueur prend peu à peu sa nouvelle direction
        // (une planète a de l'inertie), puis elle va tout droit, soumise à la gravité comme les autres.
        // Comme pour toutes les planètes, la vitesse est en points/s et la grosse planète avance
        // moins vite à l'écran (mobilité) : le temps de réaction est le même quelle que soit sa taille.
        var playerIndex: Int?
        if let playerID, gameState == .playing {
            playerIndex = planets.firstIndex { $0.id == playerID }
        }
        if let index = playerIndex, let direction = launchDirection {
            let wanted = direction * launchSpeed
            if time < launchUntil {
                acceleration[index] += (wanted - planets[index].velocity) * Self.playerResponse
            } else {
                // Fin du virage : la planète part exactement dans la direction visée.
                planets[index].velocity = wanted
                launchDirection = nil
            }
        }

        let width = Double(bounds.width)
        let height = Double(bounds.height)
        for i in 0..<n {
            var p = planets[i]
            let limit = p.isImmune(at: time) ? Self.maxFragmentSpeed : Self.maxSpeed
            p.velocity = (p.velocity + acceleration[i] * h).clamped(maxLength: limit)
            // Les éclats encore immunisés filent à pleine vitesse quelle que soit leur taille,
            // sinon les plus gros, ralentis, restent pris dans la gravité des autres.
            let mobility = i == playerIndex ? playerMobility(p)
                : p.isImmune(at: time) ? 1 : p.mobility(reference: settings.maxSize)
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
            endGame(.lost("Percuté par une planète plus grosse"), at: b.position)
        } else if a.id == playerID, gameState == .playing {
            playerAbsorptions += 1
            lastAbsorbedRatio = b.mass / a.mass
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
                        endGame(.lost("Avalé par un trou noir"), at: hole.position)
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
                // Les éclats partent du bord du trou noir gonflé (environ 0,9 × sa taille).
                spread: hole.size * 0.9,
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
            let distance = spread * Double.random(in: 0.7...1)
            return Planet(
                id: makeID(),
                position: center + direction * distance,
                velocity: velocity + direction * ejectionSpeed(speed, mass: mass, distance: distance),
                size: size,
                immuneUntil: time + Self.fragmentImmunity
            )
        }
    }

    // MARK: - Explosions

    /// Vitesse d'un éclat : la puissance des explosions (préférences), mais jamais moins que la
    /// vitesse de libération de toute la masse éjectée. Sinon, surtout dans une grande fenêtre
    /// où les planètes sont plus lourdes, la gravité des éclats les fait retomber les uns sur les
    /// autres et tout se regroupe au lieu de s'éparpiller.
    private func ejectionSpeed(_ power: Double, mass: Double, distance: Double) -> Double {
        let escape = (2 * Self.baseG * settings.gravity * mass / max(distance, Self.softening)).squareRoot()
        return max(power * Double.random(in: 0.6...1.4), escape * Double.random(in: 1.05...1.3))
    }

    private func explodeOversizedPlanets() {
        var fragments: [Planet] = []
        for i in planets.indices where planets[i].alive && planets[i].size > settings.criticalSize {
            planets[i].alive = false
            if planets[i].id == playerID {
                playerID = nil
                endGame(.lost("Trop gros : tu as dépassé la taille critique et explosé"), at: planets[i].position)
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
            let speed = ejectionSpeed(settings.explosionSpeed, mass: parent.mass, distance: parent.radius)
            return Planet(
                id: makeID(),
                position: parent.position + direction * parent.radius,
                velocity: parent.velocity * parent.mobility(reference: settings.maxSize) + direction * speed,
                size: (parent.mass * weight / totalWeight).squareRoot(),
                immuneUntil: time + Self.fragmentImmunity
            )
        }
    }

    // MARK: - Vaisseau (contemplation)

    /// Fait apparaître, avancer et tirer le vaisseau, et le retire quand il a quitté l'écran,
    /// s'est évanoui ou a été avalé par un trou noir.
    private func updateShip(_ h: Double) {
        lasers.removeAll { $0.progress(at: time) >= 1 }
        guard !isGame else { return }
        guard var current = ship else {
            if settings.shipPlanetCount > 0, planets.count <= settings.shipPlanetCount, time >= nextShipTime {
                ship = launchShip()
            }
            return
        }

        if current.isGone(at: time) {
            removeShip()
            return
        }
        // Aspiré par un trou noir : il tourne autour en s'en rapprochant, sans tirer.
        if let progress = current.fallProgress(at: time) {
            current.position = current.fallPosition(progress: progress) ?? current.position
            ship = current
            return
        }
        // Ses moteurs gardent sa vitesse : la gravité ne fait que tourner sa trajectoire, et
        // sans à-coup. Sinon, en frôlant une grosse planète, il fait demi-tour comme s'il rebondissait.
        let speed = current.velocity.length
        if speed > 0 {
            let heading = current.velocity / speed
            let pull = shipAcceleration(at: current.position)
            let sideways = heading.x * pull.y - heading.y * pull.x
            let turn = max(-Ship.maxTurnRate, min(Ship.maxTurnRate, sideways / speed)) * h
            let angle = atan2(heading.y, heading.x) + turn
            current.velocity = Vec2(angle: angle, length: speed)
        }
        current.position += current.velocity * h

        for hole in blackHoles {
            let horizon = hole.size / 2 * hole.scale(at: time)
            let reach = horizon + current.width * 0.15
            let offset = current.position - hole.position
            if offset.lengthSquared < reach * reach {
                // Il continue de tourner dans le sens où il arrivait autour du trou noir.
                let cross = offset.x * current.velocity.y - offset.y * current.velocity.x
                current.fall = (time, hole.position, current.position, cross < 0 ? -1.0 : 1.0)
                ship = current
                return
            }
        }

        // Sorti de l'écran (il part d'un peu en dehors, d'où la marge).
        let margin = current.width
        if current.position.x < -margin || current.position.x > Double(bounds.width) + margin
            || current.position.y < -margin || current.position.y > Double(bounds.height) + margin {
            removeShip()
            return
        }

        if time >= current.nextShot, let target = shipTarget(current) {
            fireLaser(from: current.position, at: target)
            current.nextShot = time + Double.random(in: Ship.reloadTime)
        }
        ship = current
    }

    private func removeShip() {
        ship = nil
        shipDebris.removeAll()
        nextShipTime = time + Double.random(in: 6...12)
    }

    /// Le vaisseau entre par le bord gauche ou droit, à mi-hauteur environ, et part lentement
    /// vers l'autre côté.
    private func launchShip() -> Ship {
        let width = Ship.baseWidth * min(1.4, max(0.6, SimulationSettings.sizeScale(for: bounds)))
        let fromLeft = Bool.random()
        let x = fromLeft ? -width / 2 : Double(bounds.width) + width / 2
        let y = Double(bounds.height) * Double.random(in: 0.2...0.8)
        // Légèrement en biais, vers le haut ou vers le bas.
        let angle = Double.random(in: -0.25...0.25) + (fromLeft ? 0 : .pi)
        return Ship(
            position: Vec2(x: x, y: y),
            velocity: Vec2(angle: angle, length: Double.random(in: Ship.launchSpeed)),
            birth: time,
            width: width,
            nextShot: time + 1
        )
    }

    /// Gravité subie par le vaisseau (il n'en exerce aucune) : c'est la seule chose qui change son orientation.
    /// Il ne touche jamais les planètes et passe au-dessus d'elles ; l'adoucissement vaut au moins
    /// leur rayon, pour qu'en les survolant il ne soit pas projeté à toute vitesse.
    private func shipAcceleration(at position: Vec2) -> Vec2 {
        let g = Self.baseG * settings.gravity
        var acceleration = Vec2.zero
        for planet in planets where planet.alive {
            let d = planet.position - position
            let eps = max(Self.softening, planet.radius)
            let r2 = d.lengthSquared + eps * eps
            acceleration += d * (g * planet.mass / (r2 * r2.squareRoot()))
        }
        for hole in blackHoles {
            let mass = hole.size * hole.size * Self.blackHoleDensity * settings.blackHoleStrength * hole.intensity(at: time)
            let eps = hole.size / 2
            let d = hole.position - position
            let r2 = d.lengthSquared + eps * eps
            acceleration += d * (Self.baseG * mass / (r2 * r2.squareRoot()))
        }
        return acceleration
    }

    /// La planète la plus proche devant le vaisseau (dans son cône de tir et à portée), en
    /// épargnant un moment les débris de ses tirs, et les éclats d'explosion encore immunisés.
    private func shipTarget(_ ship: Ship) -> Int? {
        let speed = ship.velocity.length
        guard speed > 1 else { return nil }
        let heading = ship.velocity / speed
        let range = Ship.laserRange * Double(min(bounds.width, bounds.height))
        var best: (index: Int, gap: Double)?
        for i in planets.indices where planets[i].alive && !planets[i].isImmune(at: time)
            && time >= shipDebris[planets[i].id, default: 0] {
            let d = planets[i].position - ship.position
            let distance = d.length
            let radius = planets[i].radius
            guard distance > 1, distance < range + radius else { continue }
            // Une grosse planète est visée dès qu'une partie de son disque est dans le cône,
            // même si son centre n'y est pas.
            let angle = acos(min(1, max(-1, (d.x * heading.x + d.y * heading.y) / distance)))
            guard angle - asin(min(1, radius / distance)) <= Ship.laserCone else { continue }
            // La plus proche en comptant jusqu'à sa surface : les grosses ne sont pas désavantagées.
            let gap = distance - radius
            if gap < best?.gap ?? .infinity {
                best = (i, gap)
            }
        }
        return best?.index
    }

    /// Le laser fait éclater la planète en quelques débris (la masse est conservée) ;
    /// une toute petite planète est simplement pulvérisée.
    private func fireLaser(from origin: Vec2, at index: Int) {
        let target = planets.remove(at: index)
        lasers.append(Laser(from: origin, to: target.position, birth: time))
        laserShots += 1
        let pieces = min(5, max(2, Int(target.size / 6)))
        guard target.mass / Double(pieces) >= 4 else { return }
        let debris = scatter(
            mass: target.mass,
            around: target.position,
            spread: target.radius,
            velocity: target.velocity * target.mobility(reference: settings.maxSize),
            count: pieces,
            speed: settings.explosionSpeed * 0.5
        )
        shipDebris = shipDebris.filter { $0.value > time }
        for piece in debris {
            shipDebris[piece.id] = time + Ship.debrisRespite
        }
        planets += debris
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
