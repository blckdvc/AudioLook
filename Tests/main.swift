import AVFoundation

// Tests du sampler MIDI, rendus hors-ligne (aucune carte son ni clavier nécessaires) :
// swiftc … Tests/main.swift Src/SamplerVoices.swift Src/MidiInput.swift -framework AVFoundation -framework CoreMIDI

var failures = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "✓ " : "✗ ") + msg)
    if !ok { failures += 1 }
}

// Zone de test : sinus 440 Hz, 1 s, stéréo, amplitude 0,5
func sine(_ freq: Double, seconds: Double, rate: Double = 44_100) -> AVAudioPCMBuffer {
    let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let n = Int(seconds * rate)
    let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
    b.frameLength = AVAudioFrameCount(n)
    for c in 0..<2 { for i in 0..<n { b.floatChannelData![c][i] = Float(0.5 * sin(2 * .pi * freq * Double(i) / rate)) } }
    return b
}

let sampler = SamplerVoices()
let engine = AVAudioEngine()
let fmt = sampler.format
try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
engine.attach(sampler.node)
engine.connect(sampler.node, to: engine.mainMixerNode, format: fmt)
try! engine.start()
let outRate = engine.manualRenderingFormat.sampleRate
let block = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!

func render(_ seconds: Double) -> [Float] {
    let total = Int(seconds * outRate)
    var out: [Float] = []
    while out.count < total {
        let n = min(4096, total - out.count)
        guard (try? engine.renderOffline(AVAudioFrameCount(n), to: block)) == .success else { break }
        out += Array(UnsafeBufferPointer(start: block.floatChannelData![0], count: Int(block.frameLength)))
    }
    return out
}
func rms(_ a: ArraySlice<Float>) -> Float {
    guard !a.isEmpty else { return 0 }
    return sqrt(a.reduce(0) { $0 + $1 * $1 } / Float(a.count))
}
func rms(_ a: [Float]) -> Float { rms(a[...]) }
func freq(_ a: [Float]) -> Double {
    var ups = 0
    for i in 1..<a.count where a[i - 1] < 0 && a[i] >= 0 { ups += 1 }
    return Double(ups) / (Double(a.count) / outRate)
}
func near(_ x: Double, _ y: Double, _ tol: Double = 0.03) -> Bool { abs(x - y) / y < tol }

// --- non armé : aucune note
let zone = SamplerZone(sine(440, seconds: 1))
sampler.setZones(oneShot: zone, loop: zone)
sampler.setRoot(60)
check(!sampler.handle(.noteOn(60, 127)), "non armé : la note est ignorée")
check(rms(render(0.1)) < 1e-6, "non armé : silence")

sampler.setArmed(true)

// --- note de base : l'échantillon tel quel
check(sampler.handle(.noteOn(60, 127)), "note de base déclenchée")
var a = render(0.3)
check(near(freq(a), 440), "note de base → 440 Hz (mesuré \(Int(freq(a))) Hz)")
let loud = rms(a)
check(loud > 0.3, "note de base audible (rms \(loud))")
sampler.handle(.noteOff(60))
_ = render(0.03)
check(rms(render(0.1)) < 1e-4, "relâcher la touche coupe le son")

// --- tête de lecture : suit la note tenue, à la vitesse de la note
check(sampler.playheadFrame == nil, "tête de lecture : aucune quand rien ne sonne")
sampler.handle(.noteOn(60, 127))
_ = render(0.25)
var head = (sampler.playheadFrame ?? -1) / 44_100
check(near(head, 0.25, 0.05), "tête de lecture : 0,25 s après 0,25 s à la note de base (mesuré \(head))")
sampler.handle(.noteOff(60)); _ = render(0.05)
check(sampler.playheadFrame == nil, "tête de lecture : disparaît au relâchement")

// --- une octave au-dessus : deux fois plus aigu et deux fois plus court
sampler.handle(.noteOn(72, 127))
_ = render(0.2)
head = (sampler.playheadFrame ?? -1) / 44_100
check(near(head, 0.4, 0.05), "tête de lecture : deux fois plus vite à l'octave (mesuré \(head))")
sampler.handle(.noteOff(72)); _ = render(0.05)
sampler.handle(.noteOn(72, 127))
a = render(0.4)
check(near(freq(a), 880), "C4 → 880 Hz (mesuré \(Int(freq(a))) Hz)")
a = render(0.3)
check(rms(a[(a.count / 2)...]) < 1e-4, "mode « une fois » : s'arrête à la fin de la région (0,5 s à l'octave)")
sampler.handle(.noteOff(72))

// --- une quinte en dessous
sampler.handle(.noteOn(53, 127))
a = render(0.3)
check(near(freq(a), 440 * pow(2, -7.0 / 12)), "F2 → \(Int(440 * pow(2, -7.0 / 12))) Hz (mesuré \(Int(freq(a))) Hz)")
sampler.handle(.noteOff(53)); _ = render(0.05)

// --- vélocité
sampler.handle(.noteOn(60, 64))
let soft = rms(render(0.2))
sampler.handle(.noteOff(60)); _ = render(0.05)
check(soft < loud * 0.5 && soft > loud * 0.2, "vélocité 64 plus douce (rms \(soft) vs \(loud))")

// --- mode boucle : continue au-delà de la région tant que la touche est tenue
sampler.setLoopMode(true)
sampler.handle(.noteOn(72, 127))
a = render(1.5)
check(rms(a[(a.count - Int(0.2 * outRate))...]) > 0.3, "mode boucle : joue encore après 1,5 s (région de 0,5 s à l'octave)")
sampler.handle(.noteOff(72))
_ = render(0.03)
check(rms(render(0.1)) < 1e-4, "mode boucle : relâcher coupe le son")
sampler.setLoopMode(false)

// --- pédale de sustain
sampler.handle(.noteOn(60, 127))
sampler.handle(.sustain(true))
sampler.handle(.noteOff(60))
check(rms(render(0.2)) > 0.3, "sustain : la note tient après relâchement")
sampler.handle(.sustain(false))
_ = render(0.03)
check(rms(render(0.1)) < 1e-4, "sustain relâché : silence")

// --- pitch bend (+2 demi-tons au maximum)
sampler.handle(.pitchBend(1))
sampler.handle(.noteOn(60, 127))
a = render(0.3)
check(near(freq(a), 440 * pow(2, 2.0 / 12)), "pitch bend +2 st → \(Int(440 * pow(2, 2.0 / 12))) Hz (mesuré \(Int(freq(a))) Hz)")
sampler.handle(.noteOff(60)); sampler.handle(.pitchBend(0)); _ = render(0.05)

// --- polyphonie : plus de notes que de voix, puis tout couper
for n in 40..<70 { sampler.handle(.noteOn(UInt8(n), 100)) }
check(rms(render(0.1)) > 0.01, "30 notes simultanées (16 voix) sans plantage")
sampler.handle(.allNotesOff)
_ = render(0.03)
check(rms(render(0.1)) < 1e-4, "All Notes Off : silence")

// --- désarmer coupe tout
sampler.handle(.noteOn(60, 127))
sampler.setArmed(false)
_ = render(0.03)
check(rms(render(0.1)) < 1e-4, "désarmer (fenêtre fermée) coupe le son")
sampler.setArmed(true)

// --- zone mono et autre fréquence d'échantillonnage
let monoFmt = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
let mono = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: 22_050)!
mono.frameLength = 22_050
for i in 0..<22_050 { mono.floatChannelData![0][i] = Float(0.5 * sin(2 * .pi * 440 * Double(i) / 22_050)) }
let mz = SamplerZone(mono)
sampler.setZones(oneShot: mz, loop: mz)
sampler.handle(.noteOn(60, 127))
a = render(0.3)
check(near(freq(a), 440), "zone mono 22,05 kHz → 440 Hz (mesuré \(Int(freq(a))) Hz)")
sampler.handle(.noteOff(60)); _ = render(0.05)

// --- décodage MIDI (UMP, MIDI 1.0)
func ev(_ w: UInt32) -> String { MidiInput.decode(w).map { String(describing: $0) } ?? "nil" }
check(ev(0x2090_3C64) == "noteOn(60, 100)", "décodage note on (\(ev(0x2090_3C64)))")
check(ev(0x2093_3C64) == "noteOn(60, 100)", "décodage note on, canal 4 (omni)")
check(ev(0x2090_3C00) == "noteOff(60)", "décodage note on vélocité 0 = note off")
check(ev(0x2080_3C40) == "noteOff(60)", "décodage note off")
check(ev(0x20E0_0040) == "pitchBend(0.0)", "décodage pitch bend centré (\(ev(0x20E0_0040)))")
check(ev(0x20E0_7F7F).hasPrefix("pitchBend(0.99"), "décodage pitch bend max (\(ev(0x20E0_7F7F)))")
check(ev(0x20B0_4050) == "sustain(true)", "décodage sustain")
check(ev(0x20B0_7B00) == "allNotesOff", "décodage All Notes Off")
check(ev(0x20B0_0740) == "nil", "CC7 ignoré")

// --- note de base tapée au clavier
check(NoteName.parse("C3") == 60, "saisie « C3 » → 60")
check(NoteName.parse("60") == 60, "saisie « 60 » → 60")
check(NoteName.parse(" f#2 ") == 54, "saisie « f#2 » → 54")
check(NoteName.parse("Bb1") == 46 && NoteName.parse("bb1") == 46, "saisie « Bb1 » → 46")
check(NoteName.parse("b3") == 71, "saisie « b3 » → 71 (si, pas bémol)")
check(NoteName.parse("a-1") == 21 && NoteName.parse("C-2") == 0 && NoteName.parse("G8") == 127, "saisie : octaves −2 à 8")
check(NoteName.parse("D") == 62, "saisie sans octave → octave 3")
check(NoteName.parse("H2") == nil && NoteName.parse("") == nil && NoteName.parse("A9") == nil && NoteName.parse("128") == nil, "saisie illisible ou hors limites refusée")
check((0...127).allSatisfy { NoteName.parse(NoteName.name($0)) == $0 }, "saisie : chaque nom affiché se relit")

// --- CoreMIDI : création du client, du port et du port virtuel « AudioLook »
let input = MidiInput()
input.start()
check(input.isRunning, "CoreMIDI : entrée démarrée (\(input.sourceCount) source(s))")
input.stop()

print(failures == 0 ? "\nTous les tests passent." : "\n\(failures) test(s) en échec.")
exit(failures == 0 ? 0 : 1)
