import Cocoa

/// Couleurs propres à l'interface (suivent le mode clair / sombre).
enum UIStyle {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    /// Fond des cartes de réglages et de la forme d'onde.
    static let cardFill = dynamic(light: NSColor.black.withAlphaComponent(0.035), dark: NSColor.white.withAlphaComponent(0.06))
    static let cardBorder = dynamic(light: NSColor.black.withAlphaComponent(0.05), dark: NSColor.white.withAlphaComponent(0.07))
    static let waveFill = dynamic(light: NSColor.black.withAlphaComponent(0.05), dark: NSColor.black.withAlphaComponent(0.26))
    /// Voile sur la forme d'onde hors de la région A/B (plus léger en mode clair).
    static let outsideLoop = dynamic(light: NSColor.black.withAlphaComponent(0.10), dark: NSColor.black.withAlphaComponent(0.28))
    /// Fond des champs de valeur (BPM, %, demi-tons, note).
    static let fieldFill = dynamic(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.black.withAlphaComponent(0.25))
}

/// Carte arrondie qui empile des rangées séparées par un filet, comme dans Réglages Système.
final class CardView: NSView {
    init(rows: [NSView], rowHeight: CGFloat = 34) {
        super.init(frame: .zero)
        wantsLayer = true
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, r) in rows.enumerated() {
            if i > 0 {
                let sep = NSBox(); sep.boxType = .separator
                stack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            r.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 11; layer.cornerCurve = .continuous; layer.borderWidth = 0.5
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = UIStyle.cardFill.cgColor
            layer.borderColor = UIStyle.cardBorder.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Champ de valeur éditable au clavier : texte en gras sur une petite pastille, sans bordure.
final class ValueField: NSTextField {
    override class var cellClass: AnyClass? { get { CenteredTextFieldCell.self } set {} }
    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        isEditable = true; isSelectable = true
        isBordered = false; isBezeled = false; focusRingType = .none
        // pas de cadre ni de fond : la valeur se lit comme un texte, et devient éditable au clic
        // (une pastille discrète apparaît seulement pendant la saisie)
        drawsBackground = false; backgroundColor = UIStyle.fieldFill
        wantsLayer = true; layer?.cornerRadius = 5; layer?.masksToBounds = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        (cell as? NSTextFieldCell)?.usesSingleLineMode = true
        cell?.isScrollable = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { drawsBackground = true }
        return ok
    }
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification); drawsBackground = false
    }
    // curseur texte au survol : on comprend que la valeur se modifie au clavier
    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }
}

/// Cellule qui centre le texte verticalement (et le décolle un peu des bords de la pastille).
final class CenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let h = min(rect.height, cellSize(forBounds: rect).height)
        return NSRect(x: rect.minX + 2, y: rect.minY + (rect.height - h) / 2, width: max(rect.width - 4, 0), height: h)
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// Fond de fenêtre translucide : le bureau transparaît derrière (matériau le plus léger de chaque mode).
final class GlassView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        blendingMode = .behindWindow; state = .active
        applyMaterial()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); applyMaterial() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyMaterial() }
    private func applyMaterial() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        material = dark ? .hudWindow : .popover
    }
}
