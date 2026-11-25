import CoreMIDI
import Foundation

/// Entrée MIDI : écoute toutes les sources MIDI branchées (claviers, contrôleurs, IAC…)
/// et publie une destination virtuelle « AudioLook » qu'un DAW (Logic, DP…) peut viser
/// comme sortie MIDI d'une piste. Tous les canaux sont acceptés (omni).
///
/// `onEvent` est appelé sur le thread MIDI (pas le thread principal) : le gestionnaire doit
/// être thread-safe et renvoyer vers le main thread ce qui touche à l'interface.
final class MidiInput: @unchecked Sendable {
    var onEvent: (@Sendable (MidiEvent) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var destination = MIDIEndpointRef()
    private var connected: [MIDIEndpointRef] = []
    private(set) var isRunning = false

    /// Nombre de sources physiques/logicielles actuellement écoutées.
    var sourceCount: Int { connected.count }
    var onSourcesChanged: (() -> Void)?

    func start() {
        guard !isRunning else { return }
        let st = MIDIClientCreateWithBlock("AudioLook" as CFString, &client) { [weak self] note in
            // branchement / débranchement d'un appareil → on se reconnecte à toutes les sources
            if note.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.connectSources() }
            }
        }
        guard st == noErr else { return }
        let receive: MIDIReceiveBlock = { [weak self] list, _ in self?.receive(list) }
        guard MIDIInputPortCreateWithProtocol(client, "AudioLook In" as CFString, ._1_0, &port, receive) == noErr else {
            MIDIClientDispose(client); client = 0; return
        }
        // destination virtuelle : visible dans les DAW comme sortie MIDI « AudioLook »
        _ = MIDIDestinationCreateWithProtocol(client, "AudioLook" as CFString, ._1_0, &destination, receive)
        isRunning = true
        connectSources()
    }

    func stop() {
        guard isRunning else { return }
        for src in connected { MIDIPortDisconnectSource(port, src) }
        connected = []
        if destination != 0 { MIDIEndpointDispose(destination); destination = 0 }
        MIDIPortDispose(port); port = 0
        MIDIClientDispose(client); client = 0
        isRunning = false
        onEvent?(.allNotesOff)
        onSourcesChanged?()
    }

    private func connectSources() {
        guard isRunning else { return }
        for src in connected { MIDIPortDisconnectSource(port, src) }
        connected = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            if MIDIPortConnectSource(port, src, nil) == noErr { connected.append(src) }
        }
        onSourcesChanged?()
    }

    // MARK: Décodage (Universal MIDI Packets, protocole MIDI 1.0)

    /// Taille (en mots de 32 bits) de chaque type de message UMP.
    private static let umpWords: [Int] = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        guard let handler = onEvent else { return }
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            var payload = packet.pointee.words
            withUnsafeBytes(of: &payload) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var i = 0
                while i < min(count, words.count) {
                    let w = words[i]
                    let type = Int(w >> 28)
                    if type == 0x2, let e = MidiInput.decode(w) { handler(e) }   // voix de canal MIDI 1.0
                    i += MidiInput.umpWords[type]
                }
            }
        }
    }

    static func decode(_ w: UInt32) -> MidiEvent? {
        let status = UInt8((w >> 16) & 0xF0)
        let d1 = UInt8((w >> 8) & 0x7F)
        let d2 = UInt8(w & 0x7F)
        switch status {
        case 0x90: return d2 > 0 ? .noteOn(d1, d2) : .noteOff(d1)
        case 0x80: return .noteOff(d1)
        case 0xE0:
            let v = Int(d1) | (Int(d2) << 7)          // 0 … 16383, centre 8192
            return .pitchBend(max(-1, min(1, Double(v - 8192) / 8192)))
        case 0xB0:
            switch d1 {
            case 64: return .sustain(d2 >= 64)        // pédale de sustain
            case 120, 123: return .allNotesOff        // All Sound Off / All Notes Off
            default: return nil
            }
        default: return nil
        }
    }

    deinit { stop() }
}
