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
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            Canvas { context, size in
                simulation.update(date: timeline.date, size: size)
                let settings = simulation.settings
                drawPlanets(in: &context, settings: settings)
                drawBlackHoles(in: &context)
            }
        }
    }

    // MARK: - Planètes

    private func drawPlanets(in context: inout GraphicsContext, settings: SimulationSettings) {
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

            if settings.showVectors {
                var line = Path()
                line.move(to: center)
                line.addLine(to: (planet.position + planet.velocity * 0.5).cgPoint)
                context.stroke(line, with: .color(.red.opacity(0.6)), lineWidth: 1)
            }
        }
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
            let intensity = hole.intensity(at: time)
            let diameter = hole.size * 2.4 * (0.6 + 0.4 * intensity)
            let rect = CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter)

            var layer = context
            layer.opacity = intensity
            layer.translateBy(x: hole.position.x, y: hole.position.y)
            layer.rotate(by: .radians(hole.rotation(at: time)))
            layer.drawLayer { inner in
                inner.draw(image, in: rect)
                // Masque circulaire au bord adouci : l'image carrée devient un disque tourbillonnant.
                inner.blendMode = .destinationIn
                inner.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.7),
                            .init(color: .white.opacity(0), location: 1),
                        ]),
                        center: .zero,
                        startRadius: 0,
                        endRadius: diameter / 2
                    )
                )
            }
        }
    }
}
