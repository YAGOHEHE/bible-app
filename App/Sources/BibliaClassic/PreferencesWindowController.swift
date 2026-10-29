import AppKit
import BibliaCore
import ClassicKit

/// S08: ajustes (⌘,). Todo se aplica en vivo.
final class PreferencesWindowController: NSWindowController {
    private let settings: ClassicSettings
    private let model: ReaderModel
    private let translationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let slider = NSSlider(value: 1, minValue: FontScale.min, maxValue: FontScale.max, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "100 %")
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let layoutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let headingsCheck = NSButton(checkboxWithTitle: "Mostrar títulos de sección", target: nil, action: nil)

    init(settings: ClassicSettings, model: ReaderModel) {
        self.settings = settings; self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Ajustes"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(sync), name: .classicSettingsChanged, object: settings)
        sync()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func build() {
        guard let content = window?.contentView else { return }
        for t in model.translations { translationPopup.addItem(withTitle: ReaderModel.menuTitle(t)) }
        for t in ThemeChoice.allCases { themePopup.addItem(withTitle: t.label) }
        for l in VerseLayout.allCases { layoutPopup.addItem(withTitle: l.label) }
        slider.numberOfTickMarks = 13
        slider.allowsTickMarkValuesOnly = true
        slider.setAccessibilityLabel("Tamaño de lectura")
        translationPopup.setAccessibilityLabel("Versión predeterminada")
        themePopup.setAccessibilityLabel("Tema")
        layoutPopup.setAccessibilityLabel("Diseño")
        for c in [translationPopup, themePopup, layoutPopup] as [NSPopUpButton] { c.target = self; c.action = #selector(changed(_:)) }
        slider.target = self; slider.action = #selector(changed(_:))
        headingsCheck.target = self; headingsCheck.action = #selector(changed(_:))
        sizeLabel.alignment = .right

        let sliderRow = NSStackView(views: [slider, sizeLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        sizeLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let rows: [(String, NSView)] = [
            ("Versión predeterminada:", translationPopup), ("Tamaño de texto:", sliderRow),
            ("Tema:", themePopup), ("Diseño:", layoutPopup), ("", headingsCheck)]
        let grid = NSGridViewCompat.make(rows: rows.map { (label($0.0), $0.1) })
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
    }

    @objc private func changed(_ sender: Any?) {
        if sender as AnyObject === translationPopup {
            if let t = model.translations[safe: translationPopup.indexOfSelectedItem] {
                settings.defaultTranslation = t.id
                model.setTranslation(t.id)
            }
        } else if sender as AnyObject === slider {
            settings.fontScale = slider.doubleValue
        } else if sender as AnyObject === themePopup {
            settings.theme = ThemeChoice.allCases[themePopup.indexOfSelectedItem]
        } else if sender as AnyObject === layoutPopup {
            settings.layout = VerseLayout.allCases[layoutPopup.indexOfSelectedItem]
        } else if sender as AnyObject === headingsCheck {
            settings.showHeadings = headingsCheck.state == .on
        }
    }

    @objc private func sync() {
        if let w = window { MainWindowController.apply(theme: settings.theme, to: w) }
        if let i = model.translations.firstIndex(where: { $0.id == settings.defaultTranslation }) { translationPopup.selectItem(at: i) }
        slider.doubleValue = settings.fontScale
        sizeLabel.stringValue = "\(FontScale.percent(settings.fontScale)) %"
        themePopup.selectItem(at: ThemeChoice.allCases.firstIndex(of: settings.theme) ?? 0)
        layoutPopup.selectItem(at: VerseLayout.allCases.firstIndex(of: settings.layout) ?? 0)
        headingsCheck.state = settings.showHeadings ? .on : .off
    }

    func show() {
        sync()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// NSGridView es 10.12+: la ventana de ajustes es de 10.13, se puede usar directamente.
enum NSGridViewCompat {
    static func make(rows: [(NSView, NSView)]) -> NSGridView {
        let g = NSGridView(views: rows.map { [$0.0, $0.1] })
        g.columnSpacing = 10
        g.rowSpacing = 12
        g.column(at: 0).xPlacement = .trailing
        g.column(at: 1).xPlacement = .leading
        g.rowAlignment = .firstBaseline
        return g
    }
}
