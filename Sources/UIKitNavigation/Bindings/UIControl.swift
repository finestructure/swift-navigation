#if canImport(UIKit) && !os(watchOS)
  import ConcurrencyExtras
  @_spi(Internals) import SwiftNavigation
  import UIKit

  /// A protocol used to extend `UIControl`.
  @MainActor
  public protocol UIControlProtocol: UIControl {}

  extension UIControl: UIControlProtocol {}

  @available(iOS 14, tvOS 14, *)
  extension UIControlProtocol {
    /// Establishes a two-way connection between a source of truth and a property of this control.
    ///
    /// - Parameters:
    ///   - binding: A source of truth for the control's value.
    ///   - keyPath: A key path to the control's value.
    ///   - event: The control-specific events for which the binding is updated.
    /// - Returns: A cancel token.
    @discardableResult
    public func bind<Value>(
      _ binding: UIBinding<Value>,
      to keyPath: ReferenceWritableKeyPath<Self, Value>,
      for event: UIControl.Event
    ) -> ObservationToken {
      bind(binding, to: keyPath, for: event) { control, newValue, _ in
        control[keyPath: keyPath] = newValue
      }
    }

    /// Establishes a two-way connection between a source of truth and a property of this control.
    ///
    /// - Parameters:
    ///   - binding: A source of truth for the control's value.
    ///   - keyPath: A key path to the control's value.
    ///   - event: The control-specific events for which the binding is updated.
    ///   - set: A closure that is called when the binding's value changes with a weakly-captured
    ///     control, a new value that can be used to configure the control, and a transaction, which
    ///     can be used to determine how and if the change should be animated.
    /// - Returns: A cancel token.
    @discardableResult
    public func bind<Value>(
      _ binding: UIBinding<Value>,
      to keyPath: KeyPath<Self, Value>,
      for event: UIControl.Event,
      set: @escaping (_ control: Self, _ newValue: Value, _ transaction: UITransaction) -> Void
    ) -> ObservationToken {
      unbind(keyPath)
      let action = UIAction { [weak self] _ in
        guard let self else { return }
        binding.wrappedValue = self[keyPath: keyPath]
      }
      addAction(action, for: event)
      let isSetting = LockIsolated(false)
      let token = observe { [weak self] transaction in
        guard let self else { return }
        isSetting.withValue { $0 = true }
        defer { isSetting.withValue { $0 = false } }
        set(
          self,
          binding.wrappedValue,
          transaction.uiKit.animation == nil && !transaction.uiKit.disablesAnimations
            ? binding.transaction
            : transaction
        )
      }
      // NB: This key path must only be accessed on the main actor
      @UncheckedSendable var uncheckedKeyPath = keyPath
      let observation = observe(keyPath) { [$uncheckedKeyPath] control, _ in
        guard isSetting.withValue({ !$0 }) else { return }
        MainActor.assumeIsolated {
          binding.wrappedValue = control[keyPath: $uncheckedKeyPath.wrappedValue]
        }
      }
      let observationToken = ObservationToken { [weak self] in
        MainActor.assumeIsolated {
          self?.removeAction(action, for: .allEvents)
        }
        token.cancel()
        observation.invalidate()
      }
      observationTokens[keyPath] = observationToken
      return observationToken
    }

    public func unbind<Value>(_ keyPath: KeyPath<Self, Value>) {
      observationTokens[keyPath]?.cancel()
      observationTokens[keyPath] = nil
    }

    var observationTokens: [AnyKeyPath: ObservationToken] {
      get {
        objc_getAssociatedObject(self, observationTokensKey) as? [AnyKeyPath: ObservationToken]
          ?? [:]
      }
      set {
        objc_setAssociatedObject(
          self, observationTokensKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
      }
    }
  }

  @MainActor
  private let observationTokensKey = malloc(1)!
#endif
