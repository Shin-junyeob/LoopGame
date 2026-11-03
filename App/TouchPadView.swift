import SwiftUI
import UIKit

/// A pad that reports UITouch.timestamp (seconds, systemUptime base) on touch-down, bypassing SwiftUI gestures.
struct TouchPadView: UIViewRepresentable {
    let title: String
    let onTouch: (TimeInterval) -> Void

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .systemIndigo
        view.layer.cornerRadius = 12
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        return view
    }

    func updateUIView(_ view: PadView, context: Context) {
        view.onTouch = onTouch
    }

    final class PadView: UIView {
        var onTouch: ((TimeInterval) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { onTouch?(touch.timestamp) }
        }
    }
}
