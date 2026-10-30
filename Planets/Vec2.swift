//
//  Vec2.swift
//  Planets
//
//  Vecteur 2D utilisé pour les positions, vitesses et accélérations (en points).
//  Remplace les fonctions sommeVecteur / multiplieVecteur / diviseVecteur de l'ancien AppController.
//

import CoreGraphics
import Foundation

struct Vec2: Equatable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    /// Vecteur de longueur `length` orienté selon `angle` (radians).
    init(angle: Double, length: Double) {
        self.init(x: cos(angle) * length, y: sin(angle) * length)
    }

    var lengthSquared: Double { x * x + y * y }
    var length: Double { lengthSquared.squareRoot() }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    /// Le même vecteur, raccourci si sa norme dépasse `maxLength`.
    func clamped(maxLength: Double) -> Vec2 {
        let l2 = lengthSquared
        guard l2 > maxLength * maxLength else { return self }
        return self * (maxLength / l2.squareRoot())
    }

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Vec2, k: Double) -> Vec2 { Vec2(x: a.x * k, y: a.y * k) }
    static func / (a: Vec2, k: Double) -> Vec2 { Vec2(x: a.x / k, y: a.y / k) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }
}
