import SwiftUI
import UIKit

/// A numeric text field that **clears when you tap it** so you can type a fresh value
/// (reverts to the previous value if you leave it blank). Right-aligned, number pad,
/// with a Done button on the keyboard.
struct NumberField: UIViewRepresentable {
    @Binding var value: Int

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .right
        tf.text = "\(value)"
        tf.delegate = context.coordinator
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)

        let bar = UIToolbar()
        bar.sizeToFit()
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator,
                            action: #selector(Coordinator.done))
        ]
        tf.inputAccessoryView = bar
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if !uiView.isFirstResponder { uiView.text = "\(value)" }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: NumberField
        init(_ p: NumberField) { parent = p }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            tf.text = ""                       // start blank
        }
        @objc func changed(_ tf: UITextField) {
            if let t = tf.text, let v = Int(t) { parent.value = v }
        }
        func textFieldDidEndEditing(_ tf: UITextField) {
            if (tf.text ?? "").isEmpty { tf.text = "\(parent.value)" }   // revert if left blank
        }
        @objc func done() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }
}
