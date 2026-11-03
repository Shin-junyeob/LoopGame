import SwiftUI
import UIKit

/// A pad that reports UITouch.timestamp (seconds, systemUptime base) on touch-down, bypassing SwiftUI gestures.
/// Must not sit inside a ScrollView (delaysContentTouches adds ~150 ms, S1).
struct TouchPadView: UIViewRepresentable {
    let title: String
    var color: UIColor = .systemIndigo
    var textColor: UIColor = .white
    var flashColor: UIColor = .white
    var accessibilityName: String? = nil
    /// Label near the bottom edge (piano white keys, whose middle is under the black keys).
    var labelAtBottom = false
    let onTouch: (TimeInterval) -> Void

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.isMultipleTouchEnabled = true
        view.layer.cornerRadius = 14
        view.clipsToBounds = true
        view.isAccessibilityElement = true
        view.accessibilityTraits = [.button, .allowsDirectInteraction]
        view.flash.alpha = 0
        view.flash.isUserInteractionEnabled = false
        view.flash.frame = view.bounds
        view.flash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(view.flash)
        let label = view.label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            labelAtBottom ? label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
                : label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -4),
        ])
        return view
    }

    func updateUIView(_ view: PadView, context: Context) {
        view.onTouch = onTouch
        view.backgroundColor = color
        view.flash.backgroundColor = flashColor
        view.label.text = title
        view.label.textColor = textColor
        view.accessibilityLabel = accessibilityName ?? title.replacingOccurrences(of: "\n", with: " ")
    }

    final class PadView: UIView {
        var onTouch: ((TimeInterval) -> Void)?
        let label = UILabel()
        let flash = UIView()

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { onTouch?(touch.timestamp) }
            flash.alpha = 0.55
            UIView.animate(withDuration: 0.25, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.flash.alpha = 0
            }
        }

        /// VoiceOver double-tap: same clock base as UITouch.timestamp.
        override func accessibilityActivate() -> Bool {
            onTouch?(ProcessInfo.processInfo.systemUptime)
            return true
        }
    }
}
