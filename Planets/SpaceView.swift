//
//  SpaceView.swift
//  Planets
//
//  Dessin de l'espace (ancienne NSView Espace) : planètes, vecteurs vitesse et trous noirs.
//  La vue fait avancer la simulation à chaque image de l'écran.
//

import SwiftUI

struct SpaceView: View {
    let simulation: Simulation

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                simulation.update(date: timeline.date, size: size)
                let settings = simulation.settings
                drawPlanets(in: &context, settings: settings)
                drawAim(in: &context)
                drawImpacts(in: &context)
                drawBlackHoles(in: &context)
            }
        }
    }

    // MARK: - Planètes

    private func drawPlanets(in context: inout GraphicsContext, settings: SimulationSettings) {
        // Mode jeu : la planète du joueur est entourée de bleu, celles qui peuvent la manger de rouge.
        let player = simulation.isGame ? simulation.player : nil
        for planet in simulation.planets {
            let r = planet.radius
            let x = planet.position.x
            let y = planet.position.y
            let center = planet.position.cgPoint
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let (hue, saturation) = settings.colorBySize
                ? Self.tint(size: planet.size, critical: settings.criticalSize)
                : (hue: 0.0, saturation: 0.0)
            // Petit dégradé décentré : éclairage façon sphère, comme sur l'icône d'origine.
            let shading = Gradient(colors: [
                .white,
                Color(hue: hue, saturation: saturation, brightness: 1),
                Color(hue: hue, saturation: saturation, brightness: 0.45),
            ])
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    shading,
                    center: CGPoint(x: x - r * 0.35, y: y - r * 0.35),
                    startRadius: 0,
                    endRadius: r * 1.6
                )
            )

            let sunness = Self.sunness(size: planet.size, critical: settings.criticalSize)
            if sunness > 0 {
                drawSun(planet, sunness: sunness, in: &context)
            }

            if let player {
                if planet.id == player.id {
                    let ring = r + 4
                    context.stroke(
                        Path(ellipseIn: CGRect(x: x - ring, y: y - ring, width: 2 * ring, height: 2 * ring)),
                        with: .color(Color(red: 0.4, green: 0.8, blue: 1)),
                        lineWidth: 2
                    )
                } else if planet.mass > player.mass {
                    context.stroke(
                        Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                        with: .color(.red.opacity(0.75)),
                        lineWidth: 1.5
                    )
                }
            }

            if settings.showVectors {
                var line = Path()
                line.move(to: center)
                let speed = planet.velocity * planet.mobility(reference: settings.maxSize)
                line.addLine(to: (planet.position + speed * 0.5).cgPoint)
                context.stroke(line, with: .color(.red.opacity(0.6)), lineWidth: 1)
            }
        }
    }

    // MARK: - Visée (mode jeu)

    /// Pendant que le doigt est appuyé : ligne pointillée de la planète du joueur vers le doigt.
    private func drawAim(in context: inout GraphicsContext) {
        guard let target = simulation.aimPoint, let player = simulation.player else { return }
        let start = player.position
        let toward = target - start
        let distance = toward.length
        let gap = player.radius + Simulation.aimDeadZone
        guard distance > gap else { return }
        var line = Path()
        line.move(to: (start + toward * (gap / distance)).cgPoint)
        line.addLine(to: target.cgPoint)
        let color = Color(red: 0.4, green: 0.8, blue: 1)
        context.stroke(line, with: .color(color.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6]))
        context.fill(Path(ellipseIn: CGRect(x: target.x - 4, y: target.y - 4, width: 8, height: 8)),
                     with: .color(color.opacity(0.7)))
    }

    // MARK: - Impacts

    /// Choc sur une grosse planète : éclair au point d'impact et onde de choc qui s'élargit,
    /// le tout en 0,35 s. Deux remplissages par impact, seulement pendant l'animation.
    private func drawImpacts(in context: inout GraphicsContext) {
        guard !simulation.impacts.isEmpty else { return }
        let planetsByID = Dictionary(uniqueKeysWithValues: simulation.planets.map { ($0.id, $0) })
        var layer = context
        layer.blendMode = .plusLighter

        for impact in simulation.impacts {
            guard let planet = planetsByID[impact.planetID] else { continue }
            let t = min(1, max(0, impact.progress(at: simulation.time)))
            let fade = 1 - t
            let r = planet.radius
            let center = planet.position.cgPoint

            // Onde de choc autour de la planète.
            let ring = r * (1 + 0.5 * t)
            layer.stroke(
                Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: 2 * ring, height: 2 * ring)),
                with: .color(Color(red: 1, green: 0.85, blue: 0.6).opacity(0.6 * fade)),
                lineWidth: max(1, r * 0.12 * fade)
            )

            // Éclair au point d'impact.
            let hit = (planet.position + impact.direction * r).cgPoint
            let flash = r * (0.3 + 0.7 * t)
            layer.fill(
                Path(ellipseIn: CGRect(x: hit.x - flash, y: hit.y - flash, width: 2 * flash, height: 2 * flash)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(fade),
                        Color(red: 1, green: 0.7, blue: 0.3).opacity(0.6 * fade),
                        Color(red: 1, green: 0.4, blue: 0).opacity(0),
                    ]),
                    center: hit, startRadius: 0, endRadius: flash
                )
            )
        }
    }

    // MARK: - Soleils

    /// 0 pour une planète ordinaire, puis 0 → 1 entre 50 % et 80 % de la taille critique :
    /// les plus grosses planètes se transforment progressivement en soleils.
    static func sunness(size: Double, critical: Double) -> Double {
        min(1, max(0, (size / max(critical, 1) - 0.5) / 0.3))
    }

    /// Soleil : halo qui pulse, surface incandescente et granulation qui tourne lentement.
    /// Quatre remplissages par soleil seulement, et seules les plus grosses planètes sont concernées.
    private func drawSun(_ planet: Planet, sunness: Double, in context: inout GraphicsContext) {
        let r = planet.radius
        let center = planet.position.cgPoint
        // Le numéro de la planète décale l'animation : les soleils ne pulsent pas tous ensemble.
        let phase = simulation.time + Double(planet.id % 97)
        let pulse = 1 + 0.1 * sin(phase * 2.3) + 0.05 * sin(phase * 5.1)

        func disk(_ radius: Double) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }

        var layer = context
        layer.opacity = sunness

        // Halo lumineux additif autour du soleil.
        let halo = r * 2.4 * pulse
        layer.blendMode = .plusLighter
        layer.fill(disk(halo), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 1, green: 0.8, blue: 0.35).opacity(0.7), location: 0.3),
                .init(color: Color(red: 1, green: 0.45, blue: 0.1).opacity(0.3), location: 0.55),
                .init(color: Color(red: 1, green: 0.3, blue: 0).opacity(0), location: 1),
            ]),
            center: center, startRadius: 0, endRadius: halo
        ))

        // Surface : cœur blanc-jaune, bord orange-rouge.
        layer.blendMode = .normal
        layer.fill(disk(r), with: .radialGradient(
            Gradient(colors: [
                Color(red: 1, green: 1, blue: 0.85),
                Color(red: 1, green: 0.82, blue: 0.3),
                Color(red: 0.95, green: 0.4, blue: 0.05),
            ]),
            center: center, startRadius: 0, endRadius: r
        ))

        // Granulation : deux dégradés coniques qui tournent en sens inverse donnent une surface qui bouillonne.
        layer.opacity = sunness * 0.3
        layer.fill(disk(r * 0.97), with: .conicGradient(
            Gradient(colors: [.yellow, .orange, .red, .orange, .yellow, .orange, .red, .yellow]),
            center: center, angle: .radians(phase * 0.5)
        ))
        layer.opacity = sunness * 0.2
        layer.fill(disk(r * 0.9), with: .conicGradient(
            Gradient(colors: [.white, .orange, .yellow, .red, .white]),
            center: center, angle: .radians(-phase * 0.8)
        ))
    }

    /// Bleu pâle pour les petites planètes, puis jaune, orange et rouge à l'approche de la taille critique.
    static func tint(size: Double, critical: Double) -> (hue: Double, saturation: Double) {
        let t = min(1, max(0, size / max(critical, 1)))
        let hue = t < 0.5 ? 0.6 - (0.6 - 0.14) * (t / 0.5) : 0.14 * (1 - (t - 0.5) / 0.5)
        return (hue, 0.15 + 0.7 * t)
    }

    // MARK: - Trous noirs

    private func drawBlackHoles(in context: inout GraphicsContext) {
        guard !simulation.blackHoles.isEmpty else { return }
        let image = context.resolve(Image("BlackHole"))
        let time = simulation.time

        for hole in simulation.blackHoles {
            let scale = hole.scale(at: time)
            // L'anneau orange de l'image occupe environ 30 % de sa largeur : il entoure l'horizon.
            let diameter = hole.size * 3.3 * scale
            let rect = CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter)
            let horizon = hole.size * scale

            var layer = context
            layer.opacity = hole.opacity(at: time)
            layer.translateBy(x: hole.position.x, y: hole.position.y)
            // Ombre noire sous l'image : le centre semi-transparent de l'image reste sombre sur le fond étoilé.
            layer.fill(
                Path(ellipseIn: CGRect(x: -horizon, y: -horizon, width: 2 * horizon, height: 2 * horizon)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.4),
                        .init(color: .black.opacity(0), location: 1),
                    ]),
                    center: .zero,
                    startRadius: 0,
                    endRadius: horizon
                )
            )
            layer.rotate(by: .radians(hole.rotation(at: time)))
            layer.draw(image, in: rect)
        }
    }
}
