import AVFoundation
import os

/// Sampler polyphonique joué au clavier MIDI (mode « sampler » classique, varispeed) :
/// la note de base rejoue l'échantillon tel qu'on l'entend ; chaque demi-ton au-dessus
/// accélère la lecture (×2^(1/12)), en dessous la ralentit — la hauteur et la durée
/// changent ensemble, comme sur un MPC.
///
/// - La zone jouée est la région A/B, avec les traitements courants (pitch / tempo).
/// - Deux modes : « une fois » (la région est jouée jusqu'au bout au plus) ou « boucle A/B »
///   (la région tourne tant que la touche est tenue). Dans les deux cas, relâcher la touche
///   coupe le son (fondu court, sans clic) — sauf pédale de sustain enfoncée.
/// - Vélocité → volume, pitch bend ±2 demi-tons, 16 voix.
///
/// Les notes arrivent sur le thread MIDI, le rendu se fait sur le thread audio :
/// l'état partagé est protégé par un verrou très court (os_unfair_lock).
final class SamplerVoices: @unchecked Sendable {
    static let polyphony = 16
    static let bendRange = 2.0   // demi-tons

    let format: AVAudioFormat
    let node: AVAudioSourceNode
    private let core: SamplerCore

    init(sampleRate: Double = 48_000) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let core = SamplerCore(outRate: sampleRate)
        self.core = core
        // le bloc de rendu ne capture que `core` (pas de cycle avec ce sampler)
        node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, abl in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard list.count > 0, let l = list[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = list.count > 1 ? list[1].mData?.assumingMemoryBound(to: Float.self) : nil
            if !core.render(frames: Int(frameCount), left: l, right: r) { isSilence.pointee = true }
            return noErr
        }
    }

    /// Région « une fois » et corps de boucle (sans clic au raccord). `nil` = rien à jouer.
    func setZones(oneShot: SamplerZone?, loop: SamplerZone?) { core.withState { $0.oneShot = oneShot; $0.loopZone = loop } }

    /// Le sampler ne répond aux notes que lorsqu'il est armé (fichier audio chargé, fenêtre ouverte…).
    func setArmed(_ armed: Bool) {
        core.withState { s in
            s.armed = armed
            if !armed { s.releaseAll() }
        }
    }

    func setRoot(_ note: Int) { core.withState { $0.root = max(0, min(127, note)) } }
    func setLoopMode(_ loop: Bool) { core.withState { $0.loopMode = loop } }

    /// Traite un évènement MIDI (thread-safe). Rend `true` si une note a été déclenchée.
    @discardableResult
    func handle(_ e: MidiEvent) -> Bool {
        core.withState { s in
            switch e {
            case let .noteOn(note, vel): return s.noteOn(note, vel)
            case let .noteOff(note): s.noteOff(note)
            case let .pitchBend(v): s.bend = v * SamplerVoices.bendRange
            case let .sustain(on): s.setSustain(on)
            case .allNotesOff: s.releaseAll()
            }
            return false
        }
    }

    func allNotesOff() { core.withState { $0.releaseAll() } }

    /// Position de lecture (en frames dans la zone) de la dernière note encore tenue,
    /// pour faire suivre la tête de lecture à l'écran. `nil` si aucune note ne sonne.
    var playheadFrame: Double? {
        core.withState { s in
            var best: SamplerVoice?
            for v in s.voices where v.active && !v.releasing && v.age > (best?.age ?? 0) { best = v }
            guard let v = best, let z = v.loop ? s.loopZone : s.oneShot else { return nil }
            return min(max(0, v.pos), Double(z.length - 1))
        }
    }
}

// MARK: - Zone (mémoire stable lue par le thread audio)

/// Copie non entrelacée d'un buffer, lue directement par le thread audio.
final class SamplerZone: @unchecked Sendable {
    let length: Int
    let rate: Double
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>   // = left si mono
    private let stereo: Bool

    init?(_ buf: AVAudioPCMBuffer) {
        let n = Int(buf.frameLength)
        guard n > 1, let src = buf.floatChannelData else { return nil }
        let ch = Int(buf.format.channelCount)
        length = n
        rate = buf.format.sampleRate
        stereo = ch > 1
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        l.update(from: src[0], count: n)
        left = l
        if ch > 1 {
            let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
            r.update(from: src[1], count: n)
            right = r
        } else {
            right = l
        }
    }

    deinit {
        left.deallocate()
        if stereo { right.deallocate() }
    }
}

// MARK: - Noms de notes

/// Noms de notes, convention Logic (do central = C3 = note 60).
enum NoteName {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func name(_ n: Int) -> String { names[n % 12] + String(n / 12 - 2) }

    /// Lit une note tapée au clavier : « C3 », « f#2 », « Bb1 », « a-1 », ou un numéro MIDI « 60 ».
    /// Sans octave (« F# »), l'octave 3. Rend `nil` si la saisie est illisible ou hors de 0…127.
    static func parse(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if let n = Int(t) { return (0...127).contains(n) ? n : nil }
        guard let first = t.first, let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(first).uppercased()]
        else { return nil }
        var rest = t.dropFirst()
        var semis = base
        if let a = rest.first {
            if a == "#" || a == "♯" { semis += 1; rest = rest.dropFirst() }
            else if a == "b" || a == "B" || a == "♭" { semis -= 1; rest = rest.dropFirst() }
        }
        let octave: Int
        if rest.isEmpty { octave = 3 } else if let o = Int(rest) { octave = o } else { return nil }
        let n = (octave + 2) * 12 + semis
        return (0...127).contains(n) ? n : nil
    }
}

// MARK: - Évènements MIDI

enum MidiEvent: Sendable {
    case noteOn(UInt8, UInt8)     // note, vélocité (> 0)
    case noteOff(UInt8)
    case pitchBend(Double)        // −1 … +1
    case sustain(Bool)
    case allNotesOff
}

// MARK: - État et rendu

private struct SamplerVoice {
    var active = false
    var note: UInt8 = 0
    var pos: Double = 0          // position dans la zone (frames)
    var ratio: Double = 1        // 2^((note − base)/12)
    var gain: Float = 1          // vélocité
    var env: Float = 0           // enveloppe (attaque très courte, release au note-off)
    var releasing = false
    var sustained = false        // touche relâchée pendant que la pédale est enfoncée
    var loop = false             // mode figé au déclenchement de la note
    var age: UInt64 = 0
}

private struct SamplerState {
    var armed = false
    var oneShot: SamplerZone?
    var loopZone: SamplerZone?
    var root = 60                // C3 (convention Logic)
    var loopMode = false
    var bend: Double = 0         // demi-tons
    var sustain = false
    var voices = [SamplerVoice](repeating: SamplerVoice(), count: SamplerVoices.polyphony)
    var clock: UInt64 = 0

    mutating func noteOn(_ note: UInt8, _ vel: UInt8) -> Bool {
        guard armed, (loopMode ? loopZone : oneShot) != nil else { return false }
        // une même note rejouée : l'ancienne s'éteint (fondu) et la nouvelle repart du début
        for i in voices.indices where voices[i].active && voices[i].note == note && !voices[i].releasing {
            voices[i].releasing = true
        }
        // voix libre, sinon la plus ancienne parmi celles qui s'éteignent, sinon la plus ancienne
        var idx = voices.firstIndex { !$0.active }
        if idx == nil {
            idx = voices.indices.filter { voices[$0].releasing }.min { voices[$0].age < voices[$1].age }
        }
        if idx == nil { idx = voices.indices.min { voices[$0].age < voices[$1].age } }
        guard let i = idx else { return false }
        clock += 1
        voices[i] = SamplerVoice(active: true, note: note, pos: 0,
                                 ratio: pow(2, Double(Int(note) - root) / 12),
                                 gain: Float(pow(Double(vel) / 127, 1.5)),
                                 env: 0, releasing: false, sustained: false,
                                 loop: loopMode, age: clock)
        return true
    }

    mutating func noteOff(_ note: UInt8) {
        for i in voices.indices where voices[i].active && voices[i].note == note && !voices[i].releasing {
            if sustain { voices[i].sustained = true } else { voices[i].releasing = true }
        }
    }

    mutating func setSustain(_ on: Bool) {
        sustain = on
        guard !on else { return }
        for i in voices.indices where voices[i].active && voices[i].sustained { voices[i].releasing = true }
    }

    mutating func releaseAll() {
        for i in voices.indices where voices[i].active { voices[i].releasing = true }
    }
}

private final class SamplerCore: @unchecked Sendable {
    // verrou alloué sur le tas : adresse stable, comme l'exige os_unfair_lock
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()
    private var s = SamplerState()
    private let outRate: Double
    private let atkStep: Float   // ~0,5 ms : évite le clic sans émousser l'attaque
    private let relStep: Float   // ~12 ms de release au note-off

    init(outRate: Double) {
        self.outRate = outRate
        atkStep = Float(1 / max(1, 0.0005 * outRate))
        relStep = Float(1 / max(1, 0.012 * outRate))
    }

    deinit { lock.deinitialize(count: 1); lock.deallocate() }

    func withState<R>(_ body: (inout SamplerState) -> R) -> R {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(&s)
    }

    /// Thread audio : mixe les voix actives. Rend `false` si rien ne joue (silence).
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) -> Bool {
        left.update(repeating: 0, count: frames)
        right?.update(repeating: 0, count: frames)
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard s.voices.contains(where: { $0.active }) else { return false }
        let bendMul = pow(2.0, s.bend / 12)
        for vi in 0..<s.voices.count where s.voices[vi].active {
            var v = s.voices[vi]
            guard let z = v.loop ? s.loopZone : s.oneShot else { s.voices[vi].active = false; continue }
            let n = z.length
            let L = z.left, R = z.right
            let step = v.ratio * bendMul * z.rate / outRate
            for f in 0..<frames {
                if v.releasing {
                    v.env -= relStep
                    if v.env <= 0 { v.active = false; break }
                } else if v.env < 1 {
                    v.env = min(1, v.env + atkStep)
                }
                if v.loop {
                    if v.pos >= Double(n) { v.pos = v.pos.truncatingRemainder(dividingBy: Double(n)) }
                } else if v.pos >= Double(n - 1) {
                    v.active = false; break          // fin de la région (déjà fondue en sortie)
                }
                let i0 = Int(v.pos)
                let i1 = i0 + 1 < n ? i0 + 1 : (v.loop ? 0 : i0)
                let fr = Float(v.pos - Double(i0))
                let g = v.gain * v.env
                let l = L[i0] + (L[i1] - L[i0]) * fr
                left[f] += l * g
                if let right {
                    let r = R[i0] + (R[i1] - R[i0]) * fr
                    right[f] += r * g
                }
                v.pos += step
            }
            s.voices[vi] = v
        }
        return true
    }
}
