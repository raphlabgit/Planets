//
//  GameSounds.swift
//  Planets
//
//  Jingles du mode jeu (victoire et défaite) et tir de laser du vaisseau, préchargés pour
//  partir sans délai.
//

import AVFoundation

final class GameSounds {
    static let shared = GameSounds()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        #if os(iOS)
        // Son « ambiant » : se mélange à la musique en cours et respecte le bouton silencieux.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        for name in ["win", "lose", "blaster"] {
            let url = Bundle.main.url(forResource: name, withExtension: "m4a")
                ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Sounds")
            if let url, let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[name] = player
            }
        }
    }

    func playWin() { play("win") }

    func playLose() { play("lose") }

    func playBlaster() { play("blaster") }

    private func play(_ name: String) {
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }
}
