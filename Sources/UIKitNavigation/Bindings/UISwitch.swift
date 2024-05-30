#if canImport(UIKit)
  import UIKit

  @available(iOS 14, *)
  extension UISwitch {
    /// Creates a new switch with the specified frame and registers the binding against whether or
    /// not the switch is on.
    ///
    /// - Parameters:
    ///   - frame: The frame rectangle for the view, measured in points.
    ///   - value: The binding to read from for the current state, and write to when the state
    ///     changes.
    public convenience init(frame: CGRect = .zero, isOn: UIBinding<Bool>) {
      self.init(frame: frame)
      bind(isOn: isOn)
    }

    /// Establishes a two-way connection between a binding and the switch's current state.
    ///
    /// - Parameter value: The binding to read from for the current state, and write to when the
    ///   state changes.
    public func bind(isOn: UIBinding<Bool>) {
      bind(isOn, to: \.isOn, for: .valueChanged) { [weak self] isOn, transaction in
        // TODO: Is it possible to disable a `Switch` animation in SwiftUI?
        // TODO: If not, should we match SwiftUI's behavior and always pass `true` to animated?
        self?.setOn(isOn, animated: !transaction.disablesAnimations)
      }
      addAction(
        UIAction { [weak self] _ in
          guard let self else { return }
          isOn.wrappedValue = self.isOn
        },
        for: .valueChanged
      )
    }
  }
#endif