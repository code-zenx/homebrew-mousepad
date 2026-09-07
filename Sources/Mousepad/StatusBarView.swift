import AppKit

/// 24 pt bar: FILETYPE  ENCODING  EOL  TAB n            LN n  COL n  SEL n   INS/OVR
final class StatusBarView: NSView {
    enum Segment { case filetype, encoding, eol, tab, position, mode }

    var theme = Theme.terminal {
        didSet { restyle() }
    }
    var onClick: ((Segment, NSView) -> Void)?

    private var labels: [Segment: NSTextField] = [:]
    private var values: [Segment: String] = [:]
    private var overwrite = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let left = NSStackView()
        let right = NSStackView()
        for v in [left, right] {
            v.orientation = .horizontal
            v.spacing = 16
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for seg in [Segment.filetype, .encoding, .eol, .tab, .position, .mode] {
            let l = NSTextField(labelWithString: "")
            l.font = Theme.uiFont
            l.isSelectable = false
            l.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
            labels[seg] = l
            (seg == .position || seg == .mode ? right : left).addArrangedSubview(l)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 24) }

    @objc private func clicked(_ g: NSClickGestureRecognizer) {
        guard let v = g.view, let seg = labels.first(where: { $0.value === v })?.key else { return }
        onClick?(seg, v)
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.panel.setFill()
        bounds.fill()
        theme.border.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    func update(filetype: String, encoding: String, eol: String, tab: Int, line: Int, column: Int, selection: Int, overwrite: Bool) {
        values[.filetype] = filetype.uppercased()
        values[.encoding] = encoding.uppercased()
        values[.eol] = eol
        values[.tab] = "TAB \(tab)"
        values[.position] = "LN \(line)  COL \(column)" + (selection > 0 ? "  SEL \(selection)" : "")
        values[.mode] = overwrite ? "OVR" : "INS"
        self.overwrite = overwrite
        restyle()
    }

    private func restyle() {
        for (seg, l) in labels {
            let color = (seg == .mode && overwrite) ? theme.accent : theme.muted
            l.attributedStringValue = NSAttributedString(string: values[seg] ?? "", attributes: [
                .font: Theme.uiFont, .foregroundColor: color, .kern: 0.8,
            ])
        }
        needsDisplay = true
    }
}
