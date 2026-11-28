import Foundation

/// Mode démonstration, pour les captures d'écran du README : lancer l'app avec
/// `-demoData YES` lui fait ouvrir des boucles synthétisées au lieu de suivre la sélection
/// du Finder. Aucun fichier de l'utilisateur n'est lu ; rien n'est joué tant qu'on n'appuie
/// pas sur lecture.
///   -demoStage midi          ouvre le fichier MIDI plutôt que la boucle audio
///   -demoStage update        montre la fenêtre de mise à jour (vérification réelle, sans installation)
///   -demoStage keyboard      tient une note sur le sampler, comme jouée au clavier MIDI
///                            (`-demoNote 67` choisit la note, 60 = note de base par défaut)
///   -demoLoopA 0.25 -demoLoopB 0.5   pose la région de boucle A/B (fractions de la durée)
///   -demoTargetBPM 140       règle le tempo cible
///   -demoTranspose 3         transpose de n demi-tons
///   -demoAppearance dark     force le mode sombre (ou light pour le mode clair)
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demoData") }
    static var wantsMidi: Bool { UserDefaults.standard.string(forKey: "demoStage") == "midi" }
    static var wantsKeyboard: Bool { UserDefaults.standard.string(forKey: "demoStage") == "keyboard" }
    /// `-demoStage update` : interroge réellement GitHub pour montrer la fenêtre de mise à jour,
    /// sans jamais rien télécharger ni installer.
    static var wantsUpdateCheck: Bool { UserDefaults.standard.string(forKey: "demoStage") == "update" }
    /// `-demoAllowInstall YES`, avec `-demoStage update` : installe réellement la mise à jour trouvée,
    /// sans demander. Sert à prouver le mécanisme de bout en bout sur une copie de test.
    static var allowsInstall: Bool { UserDefaults.standard.bool(forKey: "demoAllowInstall") }

    static func number(_ key: String) -> Double? {
        UserDefaults.standard.object(forKey: key) == nil ? nil : UserDefaults.standard.double(forKey: key)
    }

    /// Écrit les fichiers de démonstration dans un dossier temporaire et rend celui à ouvrir.
    static func prepare() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioLook-demo")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let drums = dir.appendingPathComponent("Wrenfield Drums 120.wav")
        let bass = dir.appendingPathComponent("Wrenfield Bass 120.wav")
        let pad = dir.appendingPathComponent("Wrenfield Pad 120.wav")
        let riff = dir.appendingPathComponent("Wrenfield Riff.mid")
        writeWAV(drumLoop(), to: drums)
        writeWAV(bassLoop(), to: bass)
        writeWAV(padLoop(), to: pad)
        try? riffMIDI().write(to: riff)
        return wantsMidi ? riff : drums
    }

    // MARK: - Synthèse (2 mesures à 120 BPM, 44,1 kHz)

    private static let rate = 44_100.0
    private static let beat = 0.5                      // secondes par temps à 120 BPM
    private static var frames: Int { Int(rate * beat * 8) }

    /// Générateur pseudo-aléatoire fixe : les captures sont identiques d'une fois à l'autre.
    private struct Noise {
        var state: UInt64 = 0x9E3779B97F4A7C15
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: state >> 11) % 2_000_001) / 1_000_000 - 1
        }
    }

    private static func drumLoop() -> [Double] {
        var out = [Double](repeating: 0, count: frames)
        var noise = Noise()
        func add(at time: Double, length: Double, _ voice: (Double) -> Double) {
            let start = Int(time * rate), n = Int(length * rate)
            for i in 0..<n where start + i < out.count { out[start + i] += voice(Double(i) / rate) }
        }
        for step in 0..<16 {                            // croches
            let t = Double(step) * beat / 2
            if step % 4 == 0 || step == 7 || step == 14 {   // grosse caisse
                add(at: t, length: 0.28) { x in sin(2 * .pi * (48 + 90 * exp(-x * 28)) * x) * exp(-x * 9) * 0.95 }
            }
            if step % 8 == 4 {                          // caisse claire
                add(at: t, length: 0.2) { x in (noise.next() * 0.6 + sin(2 * .pi * 190 * x) * 0.35) * exp(-x * 16) * 0.8 }
            }
            add(at: t, length: 0.05) { x in noise.next() * exp(-x * 90) * (step % 2 == 0 ? 0.28 : 0.16) }   // charleston
        }
        return out
    }

    private static func bassLoop() -> [Double] {
        var out = [Double](repeating: 0, count: frames)
        let notes: [Double] = [55, 55, 65.4, 55, 49, 49, 73.4, 65.4]
        for (i, f) in notes.enumerated() {
            let start = Int(Double(i) * beat * rate), n = Int(beat * 0.9 * rate)
            for k in 0..<n where start + k < out.count {
                let x = Double(k) / rate
                out[start + k] += (sin(2 * .pi * f * x) + 0.4 * sin(4 * .pi * f * x)) * min(1, x * 200) * exp(-x * 2.2) * 0.6
            }
        }
        return out
    }

    private static func padLoop() -> [Double] {
        (0..<frames).map { i in
            let x = Double(i) / rate
            let chord = [220.0, 261.6, 329.6].reduce(0) { $0 + sin(2 * .pi * $1 * x) }
            return chord / 3 * (0.45 + 0.35 * sin(2 * .pi * x / 4)) * 0.7
        }
    }

    private static func writeWAV(_ samples: [Double], to url: URL) {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 4)           // stéréo 16 bits
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(2)
        u32(UInt32(rate)); u32(UInt32(rate) * 4); u16(4); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples {
            let v = UInt16(bitPattern: Int16(max(-1, min(1, s)) * 30_000))
            u16(v); u16(v)
        }
        try? data.write(to: url)
    }

    // MARK: - Fichier MIDI (format 0, 480 ticks par noire, 120 BPM, 4 mesures)

    private static func riffMIDI() -> Data {
        // (temps de départ en croches, durée en croches, hauteur)
        let melody: [(Int, Int, UInt8)] = [
            (0, 2, 57), (2, 1, 60), (3, 1, 64), (4, 2, 69), (6, 1, 67), (7, 1, 64),
            (8, 2, 55), (10, 1, 59), (11, 1, 62), (12, 2, 67), (14, 1, 66), (15, 1, 62),
            (16, 2, 53), (18, 1, 57), (19, 1, 60), (20, 2, 65), (22, 1, 64), (23, 1, 60),
            (24, 2, 52), (26, 1, 56), (27, 1, 59), (28, 3, 64), (31, 1, 62),
        ]
        let bass: [(Int, Int, UInt8)] = [(0, 8, 45), (8, 8, 43), (16, 8, 41), (24, 8, 40)]
        var events: [(tick: Int, bytes: [UInt8])] = []
        for (start, dur, pitch) in melody + bass {
            events.append((start * 240, [0x90, pitch, 96]))
            events.append(((start + dur) * 240 - 10, [0x80, pitch, 0]))
        }
        events.sort { $0.tick < $1.tick }

        func varLen(_ value: Int) -> [UInt8] {
            var v = value, out = [UInt8(v & 0x7F)]
            while v > 0x7F { v >>= 7; out.insert(UInt8(v & 0x7F) | 0x80, at: 0) }
            return out
        }
        var track: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]      // tempo : 500 000 µs par noire
        var last = 0
        for e in events { track += varLen(e.tick - last) + e.bytes; last = e.tick }
        track += [0x00, 0xFF, 0x2F, 0x00]

        var data = Data(Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0])
        data.append(contentsOf: Array("MTrk".utf8))
        withUnsafeBytes(of: UInt32(track.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: track)
        return data
    }
}
