import Cocoa
import AVFoundation

final class PlayerViewController: NSViewController, NSWindowDelegate {
    private let waveform = WaveformView()
    private let titleLabel = NSTextField(labelWithString: Lang.t("No file", "Aucun fichier"))
    private let infoLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "0:00.0 / 0:00.0")
    private let headerStack = NSStackView()            // titre + infos, dans la barre d'outils
    private let playButton = NSButton()
    private let loopButton = NSButton()
    private let fullButton = NSButton()

    private let volSlider = NSSlider()
    private let pitchSlider = NSSlider()
    private let volValue = ValueField()
    private let pitchValue = ValueField()

    // Tempo (remplace la vitesse %)
    private let srcBPMField = ValueField()      // BPM détecté / source (éditable)
    private let tgtSlider = NSSlider()           // BPM cible
    private let tgtField = ValueField()
    private var sourceBPM: Double = 120
    private var targetBPM: Double = 120
    private var sourceDuration: Double = 0

    // Grille
    private let gridToggle = NSSwitch()
    private let gridSegment = NSSegmentedControl()
    private let midiDot = NSView()                   // pastille d'état du MIDI (pied de fenêtre)
    private let beatsField = ValueField()

    // Opacité
    private let opSlider = NSSlider()
    private let opValue = NSTextField(labelWithString: "100 %")

    private let bypassToggle = NSSwitch()

    // Clavier MIDI → sampler (mode varispeed : la note de base joue l'échantillon tel quel)
    private let midiToggle = NSSwitch()
    private let rootField = ValueField()
    private var rootNote = 60
    private let midiModePopup = NSPopUpButton()
    private let midiStatus = NSTextField(labelWithString: "")
    private let midiIn = MidiInput()
    private var midiNoteClear: DispatchWorkItem?
    private let midiEnabledKey = "midiInEnabled", midiRootKey = "midiRootNote", midiLoopKey = "midiLoopMode"

    private let player = LoopPlayer()
    private let midi = MidiPlayer()
    private var isMidi = false
    private var active: PlaybackEngine { isMidi ? midi : player }
    private let analyzer = WaveformAnalyzer()
    private var timer: Timer?
    private var reprocessTimer: Timer?
    private var currentURL: URL?
    private var siblings: [URL] = []
    private var index = 0
    private var keyMonitor: Any?

    private let gridDivs: [Double] = [0.03125, 0.0625, 0.125, 0.25, 0.5, 1.0, 4.0]   // 1/128 … 1/4, mesure

    private func sym(_ n: String) -> NSImage { NSImage(systemSymbolName: n, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 1, height: 1)) }

    override func loadView() {
        // Fond translucide (matériau système) : la fenêtre prend la couleur du bureau, en clair comme en sombre.
        let root = GlassView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold); titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right

        // Transport (dans la barre d'outils) : lecture = pastille ronde à la couleur d'accent
        configure(playButton, "play.fill", #selector(togglePlay))
        playButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        playButton.contentTintColor = .white
        playButton.wantsLayer = true; playButton.layer?.cornerRadius = 15
        playButton.toolTip = Lang.t("Play / pause (space)", "Lecture / pause (espace)")
        configure(loopButton, "repeat", #selector(toggleLoop)); loopButton.setButtonType(.toggle); loopButton.state = .on
        loopButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        loopButton.wantsLayer = true; loopButton.layer?.cornerRadius = 7
        loopButton.toolTip = Lang.t("Loop (L)", "Boucle (L)")
        // « Boucle entière » : pastille discrète, sans bordure (comme la maquette)
        fullButton.title = Lang.t("Whole loop", "Boucle entière"); fullButton.isBordered = false
        fullButton.bezelStyle = .regularSquare; fullButton.font = .systemFont(ofSize: 11, weight: .medium)
        fullButton.contentTintColor = .labelColor
        fullButton.target = self; fullButton.action = #selector(resetLoop)
        fullButton.wantsLayer = true; fullButton.layer?.cornerRadius = 11
        fullButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        fullButton.widthAnchor.constraint(equalToConstant: fullButton.intrinsicContentSize.width + 22).isActive = true
        timeLabel.widthAnchor.constraint(equalToConstant: 112).isActive = true

        waveform.onSeek = { [weak self] f in self?.active.seek(toGlobal: f); self?.refresh() }
        waveform.onLoopChange = { [weak self] a, b in self?.active.setLoopRegion(a: a, b: b); self?.refresh() }
        waveform.provideURL = { [weak self] in self?.exportURL() }   // glisser la forme d'onde = exporter
        waveform.onSpace = { [weak self] in self?.togglePlay() }      // barre d'espace → lecture / pause

        headerStack.orientation = .vertical; headerStack.alignment = .leading; headerStack.spacing = 1
        headerStack.setViews([titleLabel, infoLabel], in: .leading)
        headerStack.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        headerStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        // Curseurs : ils prennent la largeur disponible de leur carte
        volSlider.minValue = 0; volSlider.maxValue = 1; volSlider.doubleValue = 1; volSlider.target = self; volSlider.action = #selector(volChanged)
        pitchSlider.minValue = -24; pitchSlider.maxValue = 24; pitchSlider.doubleValue = 0; pitchSlider.target = self; pitchSlider.action = #selector(pitchChanged)
        tgtSlider.minValue = 40; tgtSlider.maxValue = 220; tgtSlider.doubleValue = 120; tgtSlider.target = self; tgtSlider.action = #selector(tgtSliderChanged)
        for sl in [volSlider, pitchSlider, tgtSlider] {
            sl.controlSize = .small
            sl.setContentHuggingPriority(.defaultLow, for: .horizontal)
            sl.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        }

        volValue.target = self; volValue.action = #selector(volFieldEdited)
        pitchValue.target = self; pitchValue.action = #selector(pitchFieldEdited)
        srcBPMField.target = self; srcBPMField.action = #selector(srcBPMEdited)
        tgtField.target = self; tgtField.action = #selector(tgtFieldEdited)
        beatsField.target = self; beatsField.action = #selector(beatsEdited)
        for v in [volValue, pitchValue, srcBPMField, tgtField, beatsField] {
            v.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold); v.alignment = .right
            v.setContentHuggingPriority(.required, for: .horizontal)
        }
        for v in [volValue, pitchValue, tgtField] { v.widthAnchor.constraint(equalToConstant: 56).isActive = true }
        srcBPMField.widthAnchor.constraint(equalToConstant: 46).isActive = true
        beatsField.widthAnchor.constraint(equalToConstant: 40).isActive = true
        srcBPMField.toolTip = Lang.t("Detected (source) tempo", "Tempo détecté (d'origine)")
        tgtField.toolTip = Lang.t("Target tempo", "Tempo cible")
        beatsField.toolTip = Lang.t("Number of beats in the loop (adjusts the source BPM)", "Nombre de temps de la boucle (ajuste le BPM d'origine)")

        // Grille
        gridToggle.target = self; gridToggle.action = #selector(gridChanged); gridToggle.controlSize = .mini
        gridToggle.setAccessibilityLabel(Lang.t("Snap", "Aimanter"))
        let gridTitles = ["1/16", "1/8", "1/4", Lang.t("Bar", "Mesure")]
        gridSegment.segmentCount = gridTitles.count
        for (i, t) in gridTitles.enumerated() { gridSegment.setLabel(t, forSegment: i) }
        gridSegment.trackingMode = .selectOne; gridSegment.selectedSegment = 2
        gridSegment.segmentStyle = .automatic; gridSegment.controlSize = .small; gridSegment.font = .systemFont(ofSize: 11)
        gridSegment.target = self; gridSegment.action = #selector(gridChanged)

        // Clavier MIDI → sampler : activer · note de base · mode (une fois / boucle A/B)
        let d = UserDefaults.standard
        midiToggle.state = (d.object(forKey: midiEnabledKey) as? Bool ?? true) ? .on : .off
        midiToggle.target = self; midiToggle.action = #selector(midiToggleChanged); midiToggle.controlSize = .mini
        midiToggle.setAccessibilityLabel(Lang.t("MIDI keyboard", "Clavier MIDI"))
        midiToggle.toolTip = Lang.t("Play the A/B region from a MIDI keyboard, or from a DAW track sent to the “AudioLook” MIDI port",
                                    "Jouer la région A/B au clavier MIDI, ou depuis une piste de DAW envoyée vers le port MIDI « AudioLook »")
        // note de base : un champ où l'on tape la note (« C3 », « f#2 », « 60 »…)
        // (en démonstration, la note de base est toujours C3 : les réglages réels ne sont ni lus ni modifiés)
        rootNote = DemoData.isEnabled ? 60 : max(0, min(127, d.object(forKey: midiRootKey) as? Int ?? 60))
        rootField.stringValue = Self.noteName(rootNote)
        rootField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold); rootField.alignment = .center
        rootField.setContentHuggingPriority(.required, for: .horizontal)
        rootField.widthAnchor.constraint(equalToConstant: 40).isActive = true
        rootField.target = self; rootField.action = #selector(rootFieldEdited)
        rootField.toolTip = Lang.t("Root note: plays the sample as you hear it (current pitch and tempo). Type a note (C3, F#2, Bb1) or a MIDI number (60), or click here and play a key.",
                                   "Note de base : joue l'échantillon tel que vous l'entendez (pitch et tempo actuels). Tapez une note (C3, F#2, Bb1) ou un numéro MIDI (60), ou cliquez ici et jouez une touche.")
        midiModePopup.addItems(withTitles: [Lang.t("Play once", "Jouer une fois"), Lang.t("Loop A/B while held", "Boucler A/B tant que tenu")])
        midiModePopup.selectItem(at: d.bool(forKey: midiLoopKey) ? 1 : 0)
        midiModePopup.controlSize = .small; midiModePopup.font = .systemFont(ofSize: 11)
        midiModePopup.target = self; midiModePopup.action = #selector(midiSettingsChanged)
        midiModePopup.toolTip = Lang.t("Releasing the key stops the sound in both modes", "Relâcher la touche coupe le son dans les deux modes")
        midiModePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        midiModePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        midiStatus.font = .systemFont(ofSize: 11); midiStatus.textColor = .secondaryLabelColor
        midiStatus.lineBreakMode = .byTruncatingTail
        midiStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // tempo cible ← tempo d'origine (détecté, modifiable)
        let arrowLabel = unitLabel("←")
        srcBPMField.textColor = .secondaryLabelColor
        srcBPMField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        // Carte « son » : Tempo · Pitch · Volume (icône · libellé · curseur · valeur · ↺)
        let soundCard = CardView(rows: [
            row([icon("metronome.fill"), rowLabel(Lang.t("Tempo", "Tempo")), tgtSlider, tgtField, arrowLabel, srcBPMField, resetBtn(#selector(resetTempo))]),
            row([icon("tuningfork"), rowLabel(Lang.t("Pitch", "Pitch")), pitchSlider, pitchValue, resetBtn(#selector(resetPitch))]),
            row([icon("speaker.wave.2.fill"), rowLabel(Lang.t("Volume", "Volume")), volSlider, volValue, resetBtn(#selector(resetVol))]),
        ])
        // Carte « grille et MIDI » : Aimanter · tempo d'origine et nombre de temps · clavier MIDI
        let gridCard = CardView(rows: [
            row([icon("grid"), rowLabel(Lang.t("Snap", "Aimanter"), 74), gridSegment, gridSpacer(), gridToggle]),
            row([icon("metronome"), rowLabel(Lang.t("Length", "Durée"), 74), NSView(), beatsField, unitLabel(Lang.t("beats", "temps"))]),
            row([icon("pianokeys"), rowLabel(Lang.t("MIDI keyboard", "Clavier MIDI"), 74), rootField, midiModePopup, gridSpacer(), midiToggle]),
        ])
        soundCard.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gridCard.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let cards = hstack([soundCard, gridCard], 12)
        cards.alignment = .top; cards.distribution = .fill
        soundCard.widthAnchor.constraint(greaterThanOrEqualTo: gridCard.widthAnchor, multiplier: 0.9).isActive = true

        // Pied : état MIDI · bypass · transparence de la fenêtre
        bypassToggle.target = self; bypassToggle.action = #selector(toggleBypass); bypassToggle.controlSize = .mini
        bypassToggle.setAccessibilityLabel(Lang.t("Bypass processing", "Désactiver le traitement"))
        let bypassLabel = label(Lang.t("Bypass", "Sans traitement"))
        bypassLabel.toolTip = Lang.t("Hear the original file, without pitch or tempo changes", "Écouter le fichier d'origine, sans pitch ni tempo")
        opSlider.minValue = 0.35; opSlider.maxValue = 1; opSlider.doubleValue = 1
        opSlider.controlSize = .mini; opSlider.target = self; opSlider.action = #selector(opChanged)
        opSlider.setContentHuggingPriority(.required, for: .horizontal)
        opSlider.widthAnchor.constraint(equalToConstant: 56).isActive = true
        opValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium); opValue.textColor = .secondaryLabelColor
        opValue.setContentHuggingPriority(.required, for: .horizontal)
        opValue.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let opIcon = icon("circle.lefthalf.filled"); opIcon.toolTip = Lang.t("Window transparency", "Transparence de la fenêtre")
        midiDot.wantsLayer = true; midiDot.layer?.cornerRadius = 3
        midiDot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        midiDot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let dragIcon = icon("square.and.arrow.up")
        let dragShort = label(Lang.t("Drag the waveform to a DAW", "Glissez l'onde vers un DAW"))
        for v in [dragIcon, dragShort] as [NSView] {
            v.toolTip = Lang.t("Drag the waveform to a DAW / Finder · click to seek · scroll to zoom (⇧ to pan)",
                               "Glissez la forme d'onde vers un DAW / Finder · clic pour vous positionner · molette : zoom (⇧ : défiler)")
        }
        let footer = hstack([midiDot, midiStatus, NSView(), bypassToggle, bypassLabel, spacer(8), opIcon, opSlider, opValue, spacer(8), dragIcon, dragShort], 6)

        let stack = NSStackView(views: [waveform, cards, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.setCustomSpacing(14, after: waveform)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            // sous la barre d'outils (la fenêtre a un contenu pleine hauteur)
            stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            waveform.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cards.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            waveform.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        waveform.setContentHuggingPriority(.defaultLow, for: .vertical)
        view = root
    }

    // Helpers UI
    private func icon(_ s: String) -> NSImageView {
        let v = NSImageView(image: sym(s)); v.contentTintColor = .secondaryLabelColor
        v.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        v.widthAnchor.constraint(equalToConstant: 16).isActive = true; return v
    }
    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; return l
    }
    /// Libellé d'une rangée de carte (largeur fixe : les contrôles s'alignent d'une rangée à l'autre).
    private func rowLabel(_ s: String, _ w: CGFloat = 58) -> NSTextField {
        let l = NSTextField(labelWithString: s); l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        l.widthAnchor.constraint(equalToConstant: w).isActive = true; return l
    }
    /// Petite unité grise à côté d'une valeur (« temps », « BPM »).
    private func unitLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s); l.font = .systemFont(ofSize: 11); l.textColor = .tertiaryLabelColor; return l
    }
    private func row(_ v: [NSView]) -> NSStackView {
        let s = hstack(v, 8); s.alignment = .centerY; return s
    }
    private func spacer(_ w: CGFloat) -> NSView {
        let v = NSView(); v.widthAnchor.constraint(equalToConstant: w).isActive = true; return v
    }
    private func gridSpacer() -> NSView {
        let v = NSView(); v.widthAnchor.constraint(greaterThanOrEqualToConstant: 2).isActive = true; return v
    }
    private func resetBtn(_ action: Selector) -> NSButton {
        let r = NSButton(title: "", image: sym("arrow.counterclockwise"), target: self, action: action)
        r.isBordered = false; r.imagePosition = .imageOnly; r.contentTintColor = .tertiaryLabelColor
        r.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        r.toolTip = Lang.t("Reset", "Réinitialiser")
        r.widthAnchor.constraint(equalToConstant: 18).isActive = true; return r
    }
    private func hstack(_ v: [NSView], _ sp: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: v); s.orientation = .horizontal; s.spacing = sp; return s
    }
    private func vstack(_ v: [NSView], _ sp: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: v); s.orientation = .vertical; s.spacing = sp; s.alignment = .leading; return s
    }
    private func configure(_ b: NSButton, _ symbol: String, _ action: Selector) {
        b.bezelStyle = .regularSquare; b.isBordered = false; b.imagePosition = .imageOnly; b.image = sym(symbol)
        b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold); b.contentTintColor = .controlAccentColor
        b.target = self; b.action = action
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true; b.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    /// Couleurs du transport : pastille d'accent pour lecture, fond discret pour la boucle active.
    private func styleTransport() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            playButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            fullButton.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
            midiDot.layer?.backgroundColor = (midiToggle.state == .on ? NSColor.systemGreen : NSColor.tertiaryLabelColor).cgColor
            loopButton.layer?.backgroundColor = active.loopEnabled ? NSColor.labelColor.withAlphaComponent(0.1).cgColor : NSColor.clear.cgColor
        }
    }

    // MARK: Chargement
    func open(url: URL) {
        let exts: Set<String> = ["wav","aif","aiff","aifc","caf","mp3","m4a","aac","flac","ogg","opus","mid","midi"]
        let dir = url.deletingLastPathComponent()
        siblings = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? [url]
        // compare les chemins résolus : /var et /private/var désignent le même fichier
        let wanted = url.resolvingSymlinksInPath().path
        index = siblings.firstIndex { $0.resolvingSymlinksInPath().path == wanted } ?? 0
        load(siblings[index])
    }

    private func load(_ url: URL) {
        analyzer.cancel(); player.stop(); midi.stop()
        player.sampler.setArmed(false)
        waveform.maxv = []; waveform.minv = []; waveform.rms = []; waveform.notes = []
        waveform.progress = 0; waveform.loopA = 0; waveform.loopB = 1
        currentURL = url
        let ext = url.pathExtension.lowercased()
        isMidi = (ext == "mid" || ext == "midi")
        titleLabel.stringValue = Lang.t("Loading…", "Chargement…"); infoLabel.stringValue = ""
        if isMidi { loadMidi(url) } else { loadAudio(url) }
        applyDemoSettings()
    }

    private func loadAudio(_ url: URL) {
        volSlider.isEnabled = true; volValue.isEnabled = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let src = SampleProcessor.read(url: url) else {
                DispatchQueue.main.async { self?.titleLabel.stringValue = Lang.t("Can't play this file", "Lecture impossible") }; return
            }
            let bpm = BPMDetector.detect(src)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sourceDuration = Double(src.frameCount) / src.sampleRate
                self.sourceBPM = bpm
                self.targetBPM = bpm                 // chaque sample repart à son tempo natif
                self.tgtSlider.doubleValue = bpm
                // applique les traitements courants AVANT le rendu
                self.player.bypass = (self.bypassToggle.state == .on)
                self.player.setRate(Float(self.rateFromBPM()))
                self.player.setTranspose(Float(self.pitchSlider.doubleValue.rounded()))
                self.player.load(source: src)
                self.player.volume = Float(self.volSlider.doubleValue)
                self.player.onReprocessed = { [weak self] in self?.refresh() }
                self.player.onStateChange = { [weak self] in self?.refresh() }
                self.titleLabel.stringValue = url.lastPathComponent
                self.infoLabel.stringValue = self.describe(url, src)
                self.analyzer.analyze(url: url) { [weak self] r in self?.waveform.maxv = r.maxv; self?.waveform.minv = r.minv; self?.waveform.rms = r.rms }
                self.updateGrid(); self.startTimer(); self.refresh()
                self.updateSamplerArming()
            }
        }
    }

    // MIDI : lecture via la banque General MIDI d'Apple, affichage piano-roll.
    // (Le volume maître ne s'applique pas à l'AVMIDIPlayer → champ désactivé.)
    private func loadMidi(_ url: URL) {
        volSlider.isEnabled = true; volValue.isEnabled = true
        midi.volume = Float(volSlider.doubleValue)
        midi.bypass = (bypassToggle.state == .on)
        midi.setTranspose(Float(pitchSlider.doubleValue.rounded()))
        midi.onStateChange = { [weak self] in self?.refresh() }
        guard midi.load(url: url) else {
            titleLabel.stringValue = Lang.t("Can't play this file", "Lecture impossible"); return
        }
        sourceBPM = midi.sourceBPM.rounded()
        targetBPM = sourceBPM
        tgtSlider.doubleValue = sourceBPM
        midi.setRate(Float(rateFromBPM()))
        sourceDuration = midi.duration
        let tb = max(midi.totalBeats, 0.0001)
        waveform.notes = midi.rawNotes.map { PRNote(start: $0.start / tb, dur: max($0.dur / tb, 0.0015), pitch: $0.pitch) }
        titleLabel.stringValue = url.lastPathComponent
        infoLabel.stringValue = describeMidi(url, notes: midi.rawNotes.count)
        updateGrid(); startTimer(); refresh()
        updateSamplerArming()
    }

    /// Mode démonstration : règle la boucle, le tempo et la transposition demandés au lancement.
    private func applyDemoSettings() {
        guard DemoData.isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if let a = DemoData.number("demoLoopA"), let b = DemoData.number("demoLoopB") {
                self.loopButton.state = .on
                self.active.setLoop(true)
                self.active.setLoopRegion(a: a, b: b)
                self.waveform.loopA = a; self.waveform.loopB = b
            }
            if let bpm = DemoData.number("demoTargetBPM") {
                self.targetBPM = bpm; self.tgtSlider.doubleValue = bpm; self.applyTempo()
            }
            if let semis = DemoData.number("demoTranspose") {
                self.pitchSlider.doubleValue = semis; self.pitchChanged()
            }
            self.refresh()
            // -demoStage keyboard : une note tenue, comme jouée au clavier (après la pose de la région A/B)
            if DemoData.wantsKeyboard && !self.isMidi {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.demoPlayNote() }
            }
        }
    }

    /// Mode démonstration : joue et tient une note sur le sampler, sans appareil MIDI (et sans son).
    private func demoPlayNote() {
        updateSamplerArming()
        let e = MidiEvent.noteOn(UInt8(max(0, min(127, DemoData.number("demoNote") ?? 60))), 100)
        midiEventReceived(e, started: player.sampler.handle(e))
        midiNoteClear?.cancel()          // le nom de la note reste affiché pour la capture
    }

    private func navigate(_ d: Int) { guard !siblings.isEmpty else { return }; index = (index + d + siblings.count) % siblings.count; load(siblings[index]) }
    func suspend() { active.pause(); player.sampler.setArmed(false); refresh() }

    // MARK: Tempo
    private func rateFromBPM() -> Double {
        guard sourceBPM > 1 else { return 1 }
        return targetBPM / sourceBPM
    }
    private func applyTempo() {
        active.setRate(Float(rateFromBPM()))
        updateGrid(); updateValues(); scheduleReprocess()
    }
    @objc private func tgtSliderChanged() { targetBPM = tgtSlider.doubleValue.rounded(); applyTempo() }
    @objc private func tgtFieldEdited() {
        if let n = intIn(tgtField.stringValue) { targetBPM = Double(min(max(n, 40), 220)); tgtSlider.doubleValue = targetBPM; applyTempo() } else { updateValues() }
        focusWave()
    }
    @objc private func srcBPMEdited() {
        if let n = intIn(srcBPMField.stringValue), n > 20 { sourceBPM = Double(min(max(n, 30), 300)); applyTempo() } else { updateValues() }
        focusWave()
    }
    @objc private func beatsEdited() {
        if let n = intIn(beatsField.stringValue), n > 0, sourceDuration > 0 {
            sourceBPM = (Double(n) * 60.0 / sourceDuration).rounded()
            applyTempo()
        } else { updateValues() }
        focusWave()
    }
    @objc private func resetTempo() { targetBPM = sourceBPM; tgtSlider.doubleValue = targetBPM; applyTempo() }

    // MARK: Grille
    @objc private func gridChanged() { updateGrid() }
    private func updateGrid() {
        // segments 1/16 · 1/8 · 1/4 · mesure = les 4 dernières divisions de gridDivs
        let i = max(0, min(gridSegment.selectedSegment + 3, gridDivs.count - 1))
        let beatSec = sourceBPM > 1 ? 60.0 / sourceBPM : 0
        waveform.gridSpacing = sourceDuration > 0 ? (beatSec * gridDivs[i]) / sourceDuration : 0
        waveform.gridEnabled = gridToggle.state == .on
    }

    // MARK: Transport / divers
    @objc private func togglePlay() { active.togglePlay(); refresh() }
    @objc private func toggleLoop() { active.setLoop(loopButton.state == .on); refresh() }
    @objc private func resetLoop() { active.setLoopRegion(a: 0, b: 1); waveform.loopA = 0; waveform.loopB = 1; refresh() }
    @objc private func toggleBypass() {
        let on = bypassToggle.state == .on
        active.bypass = on
        for v in [srcBPMField, tgtField, beatsField] { v.isEnabled = !on }
        tgtSlider.isEnabled = !on; pitchSlider.isEnabled = !on; pitchValue.isEnabled = !on
        active.reprocess(); updateValues()
    }

    @objc private func volChanged() { active.volume = Float(volSlider.doubleValue); updateValues() }
    @objc private func pitchChanged() { pitchSlider.doubleValue = pitchSlider.doubleValue.rounded(); active.setTranspose(Float(pitchSlider.doubleValue.rounded())); updateValues(); scheduleReprocess() }
    @objc private func resetVol() { volSlider.doubleValue = 1; volChanged() }
    @objc private func resetPitch() { pitchSlider.doubleValue = 0; pitchChanged() }

    private func intIn(_ s: String) -> Int? { Int(s.filter { "0123456789+-".contains($0) }) }
    private func focusWave() { view.window?.makeFirstResponder(waveform) }
    @objc private func volFieldEdited() {
        if let n = intIn(volValue.stringValue) { volSlider.doubleValue = min(max(Double(n)/100, 0), 1); volChanged() } else { updateValues() }; focusWave()
    }
    @objc private func pitchFieldEdited() {
        if let n = intIn(pitchValue.stringValue) { pitchSlider.doubleValue = Double(min(max(n, -24), 24)); pitchChanged() } else { updateValues() }; focusWave()
    }
    @objc private func opChanged() {
        let a = opSlider.doubleValue; view.window?.alphaValue = CGFloat(a); opValue.stringValue = "\(Int((a*100).rounded())) %"
    }

    private func scheduleReprocess() {
        reprocessTimer?.invalidate()
        reprocessTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in self?.active.reprocess() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMidiInput()
        // Espace = lecture/pause tant que la fenêtre AudioLook est active
        // (on laisse passer l'espace quand on édite un champ texte).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.view.window?.isKeyWindow == true else { return e }
            if self.view.window?.firstResponder is NSText { return e }   // édition d'un champ
            if e.keyCode == 49 { self.togglePlay(); return nil }         // 49 = barre d'espace
            return e
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Donne le focus clavier à la forme d'onde (pas à un champ texte) → la barre
        // d'espace lecture/pause fonctionne dès l'ouverture.
        view.window?.makeFirstResponder(waveform)
    }

    // Arrête la lecture quand on ferme la fenêtre (bouton rouge ou Échap).
    func windowWillClose(_ notification: Notification) { active.pause(); player.sampler.setArmed(false); refresh() }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 49: togglePlay()
        case 123: navigate(-1)
        case 124: navigate(1)
        case 53: view.window?.close()
        default:
            if e.charactersIgnoringModifiers?.lowercased() == "l" { loopButton.state = loopButton.state == .on ? .off : .on; toggleLoop() }
            else { super.keyDown(with: e) }
        }
    }

    // MARK: Clavier MIDI (sampler)

    /// Nom de note, convention Logic (do central = C3 = note 60).
    static func noteName(_ n: Int) -> String { NoteName.name(n) }

    private func setupMidiInput() {
        player.sampler.setRoot(rootNote)
        player.sampler.setLoopMode(midiModePopup.indexOfSelectedItem == 1)
        // Les notes partent directement vers le sampler depuis le thread MIDI (latence minimale) ;
        // l'interface est mise à jour ensuite sur le thread principal.
        let sampler = player.sampler
        midiIn.onEvent = { [weak self] e in
            let started = sampler.handle(e)
            DispatchQueue.main.async { self?.midiEventReceived(e, started: started) }
        }
        midiIn.onSourcesChanged = { [weak self] in self?.updateMidiStatus() }
        // en démonstration (captures d'écran), l'app ne se connecte à aucun appareil
        if midiToggle.state == .on && !DemoData.isEnabled { midiIn.start() }
        updateMidiStatus()
    }

    @objc private func midiToggleChanged() {
        let on = midiToggle.state == .on
        UserDefaults.standard.set(on, forKey: midiEnabledKey)
        if on { midiIn.start() } else { midiIn.stop() }
        updateSamplerArming(); updateMidiStatus()
    }

    @objc private func midiSettingsChanged() {
        let loop = midiModePopup.indexOfSelectedItem == 1
        UserDefaults.standard.set(loop, forKey: midiLoopKey)
        player.sampler.setLoopMode(loop)
        focusWave()
    }

    /// Note de base tapée au clavier : nom de note (« C3 », « f#2 », « Bb1 ») ou numéro MIDI (« 60 »).
    /// Une saisie illisible remet la note en cours.
    @objc private func rootFieldEdited() {
        if let n = NoteName.parse(rootField.stringValue) { setRoot(n) } else { rootField.stringValue = Self.noteName(rootNote) }
        focusWave()
    }

    private func setRoot(_ n: Int) {
        rootNote = max(0, min(127, n))
        rootField.stringValue = Self.noteName(rootNote)
        if !DemoData.isEnabled { UserDefaults.standard.set(rootNote, forKey: midiRootKey) }
        player.sampler.setRoot(rootNote)
    }

    /// Le champ de la note de base est en cours de saisie (il a le curseur).
    private var isEditingRoot: Bool { rootField.currentEditor() != nil }

    /// Le sampler ne répond que pour un fichier audio chargé, fenêtre visible, MIDI activé.
    private func updateSamplerArming() {
        let armed = midiToggle.state == .on && !isMidi && player.source != nil && (view.window?.isVisible ?? false)
        player.sampler.setArmed(armed)
        for c in [rootField, midiModePopup] as [NSControl] { c.isEnabled = midiToggle.state == .on && !isMidi }
        updateMidiStatus()
    }

    private func midiEventReceived(_ e: MidiEvent, started: Bool) {
        guard case let .noteOn(note, _) = e else { return }
        // curseur dans le champ « base » : la touche jouée devient la note de base
        if isEditingRoot {
            player.sampler.allNotesOff()
            setRoot(Int(note)); focusWave()
            return
        }
        if !started {
            // fenêtre fermée puis rouverte, ou moteur pas encore armé : on réarme pour la note suivante
            updateSamplerArming()
            return
        }
        player.ensureEngineRunning()
        // une note jouée prend la main sur la lecture en boucle du transport
        if player.isPlaying { player.pause(); refresh() }
        midiStatus.textColor = .controlAccentColor
        midiStatus.stringValue = "♪ " + Self.noteName(Int(note))
        midiNoteClear?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.updateMidiStatus() }
        midiNoteClear = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }

    private func updateMidiStatus() {
        styleTransport()
        midiStatus.textColor = .secondaryLabelColor
        if midiToggle.state != .on { midiStatus.stringValue = ""; return }
        if isMidi { midiStatus.stringValue = Lang.t("audio files only", "fichiers audio uniquement"); return }
        let n = midiIn.sourceCount
        midiStatus.stringValue = n == 0
            ? Lang.t("no device · port “AudioLook”", "aucun appareil · port « AudioLook »")
            : Lang.t("\(n) device\(n > 1 ? "s" : "") · port “AudioLook”", "\(n) appareil\(n > 1 ? "s" : "") · port « AudioLook »")
    }

    // MARK: Export / Logic
    private func exportURL() -> URL? {
        // On se base sur les marqueurs A/B visibles (source de vérité de l'UI) :
        // si la boucle n'est pas entière, on n'exporte que le morceau entre A et B.
        let a = waveform.loopA, b = waveform.loopB
        let full = a <= 0.0005 && b >= 0.9995
        guard let base = currentURL?.deletingPathExtension().lastPathComponent else { return nil }
        var name = base
        if bypassToggle.state == .off {
            if Int(targetBPM) != Int(sourceBPM) { name += "_\(Int(targetBPM))bpm" }
            let st = Int(pitchSlider.doubleValue.rounded()); if st != 0 { name += String(format: "_%+dst", st) }
        }
        if !full { name += "_loop" }
        if isMidi {
            // On glisse un .mid (région A/B, transposition appliquée) : prêt à reposer dans le DAW.
            return midi.exportRegion(a: a, b: b, targetBPM: targetBPM, name: name)
        }
        guard let buf = player.renderRegionForExport(a: a, b: b) else { return nil }
        return LogicImporter.exportTemp(buf, name: name)
    }

    // MARK: UI refresh
    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    private func tick() { waveform.progress = active.progress; timeLabel.stringValue = timeText() }
    private func refresh() {
        waveform.progress = active.progress; waveform.loopA = active.loopA; waveform.loopB = active.loopB
        timeLabel.stringValue = timeText()
        playButton.image = sym(active.isPlaying ? "pause.fill" : "play.fill")
        loopButton.contentTintColor = active.loopEnabled ? .controlAccentColor : .secondaryLabelColor
        styleTransport()
        updateValues()
    }
    private func updateValues() {
        volValue.stringValue = "\(Int((volSlider.doubleValue*100).rounded())) %"
        let st = Int(pitchSlider.doubleValue.rounded()); pitchValue.stringValue = st > 0 ? "+\(st) st" : "\(st) st"
        srcBPMField.stringValue = "\(Int(sourceBPM))"
        tgtField.stringValue = "\(Int(targetBPM))"
        if sourceDuration > 0 { beatsField.stringValue = "\(Int((sourceBPM * sourceDuration / 60).rounded()))" }
    }
    private func timeText() -> String { "\(fmt(active.currentTime)) / \(fmt(active.regionDuration))" }
    private func fmt(_ t: TimeInterval) -> String { guard t.isFinite else { return "0:00.0" }; let d = Int((t*10).rounded(.down)); return String(format: "%d:%02d.%d", d/600, (d/10)%60, d%10) }
    private func describe(_ url: URL, _ src: AudioSource?) -> String {
        let r = (src?.sampleRate ?? 44100)/1000
        let rate = r == r.rounded() ? String(format: "%.0f kHz", r) : String(format: "%.1f kHz", r)
        let ch = (src?.channels ?? 2) == 1 ? "Mono" : Lang.t("Stereo", "Stéréo")
        var parts = [url.pathExtension.uppercased(), rate, ch, fmt(player.duration), "≈\(Int(sourceBPM)) BPM"]
        if siblings.count > 1 { parts.append("\(index+1)/\(siblings.count)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private func describeMidi(_ url: URL, notes: Int) -> String {
        var parts = ["MIDI", "\(notes) " + Lang.t("notes", "notes"), fmt(midi.duration), "≈\(Int(sourceBPM)) BPM"]
        if siblings.count > 1 { parts.append("\(index+1)/\(siblings.count)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    deinit {
        timer?.invalidate(); reprocessTimer?.invalidate(); analyzer.cancel(); player.stop(); midi.stop()
        midiIn.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

// MARK: Barre d'outils (titre du fichier à gauche, transport à droite)
extension PlayerViewController: NSToolbarDelegate {
    private static let tbTitle = NSToolbarItem.Identifier("AudioLook.title")
    private static let tbWhole = NSToolbarItem.Identifier("AudioLook.wholeLoop")
    private static let tbLoop = NSToolbarItem.Identifier("AudioLook.loop")
    private static let tbPlay = NSToolbarItem.Identifier("AudioLook.play")
    private static let tbTime = NSToolbarItem.Identifier("AudioLook.time")

    func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "AudioLookToolbar")
        t.delegate = self; t.displayMode = .iconOnly; t.allowsUserCustomization = false
        return t
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.tbTitle, .flexibleSpace, Self.tbWhole, Self.tbLoop, Self.tbPlay, Self.tbTime]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.tbTitle:
            item.view = headerStack; item.label = Lang.t("File", "Fichier"); item.visibilityPriority = .high
        case Self.tbWhole:
            item.view = fullButton; item.label = fullButton.title
        case Self.tbLoop:
            item.view = loopButton; item.label = Lang.t("Loop", "Boucle")
        case Self.tbPlay:
            item.view = playButton; item.label = Lang.t("Play", "Lecture"); item.visibilityPriority = .user
        case Self.tbTime:
            item.view = timeLabel; item.label = Lang.t("Time", "Temps")
        default:
            return nil
        }
        return item
    }
}
