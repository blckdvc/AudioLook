import Cocoa

/// Couleurs propres à l'interface (suivent le mode clair / sombre).
enum UIStyle {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    /// Fond des cartes de réglages et de la forme d'onde.
    static let cardFill = dynamic(light: NSColor.black.withAlphaComponent(0.035), dark: NSColor.white.withAlphaComponent(0.06))
    static let cardBorder = dynamic(light: NSColor.black.withAlphaComponent(0.07), dark: NSColor.white.withAlphaComponent(0.08))
    static let waveFill = dynamic(light: NSColor.black.withAlphaComponent(0.05), dark: NSColor.black.withAlphaComponent(0.26))
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
    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        isEditable = true; isSelectable = true
        isBordered = false; isBezeled = false; focusRingType = .none
        drawsBackground = true; backgroundColor = UIStyle.fieldFill
        wantsLayer = true; layer?.cornerRadius = 5; layer?.masksToBounds = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        (cell as? NSTextFieldCell)?.usesSingleLineMode = true
        cell?.isScrollable = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
