#if canImport(UIKit)
  import UIKit
  @_spi(Internals) import SwiftNavigation
  import SwiftUINavigationCore

  open class NavigationStackController: UINavigationController {
    fileprivate var destinations:
      [DestinationType: (UINavigationPath.Element) -> UIViewController?] =
        [:]
    @UIBinding fileprivate var path: [UINavigationPath.Element] = []
    private let pathDelegate = PathDelegate()
    private var root: UIViewController?

    public override weak var delegate: (any UINavigationControllerDelegate)? {
      get { pathDelegate.base }
      set { pathDelegate.base = newValue }
    }

    public convenience init<Data: RandomAccessCollection & RangeReplaceableCollection>(
      navigationBarClass: AnyClass? = nil,
      toolbarClass: AnyClass? = nil,
      path: UIBinding<Data>,
      root: () -> UIViewController
    ) where Data.Element: Hashable {
      self.init(navigationBarClass: navigationBarClass, toolbarClass: toolbarClass)
      self._path = path.path
      let root = root()
      self.root = root
      self.viewControllers = [root]
    }

    public convenience init(
      navigationBarClass: AnyClass? = nil,
      toolbarClass: AnyClass? = nil,
      path: UIBinding<UINavigationPath>,
      root: () -> UIViewController
    ) {
      self.init(navigationBarClass: navigationBarClass, toolbarClass: toolbarClass)
      self._path = path.elements
      let root = root()
      self.root = root
      self.viewControllers = [root]
    }

    open override func viewDidLoad() {
      super.viewDidLoad()

      super.delegate = pathDelegate

      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        traitOverrides.push = UIPushAction { [weak self] value in
          self?._push(value: value)
        }
      }

      observe { [weak self] transaction in
        guard let self else { return }

        let newPath = path

        let difference = newPath.difference(from: viewControllers.compactMap(\.navigationID))

        guard !difference.isEmpty else {
          if viewControllers.isEmpty, let root {
            setViewControllers([root], animated: true)
          }
          return
        }

        if difference.count == 1,
          case let .insert(newPath.count - 1, navigationID, nil) = difference.first,
          let viewController = viewController(for: navigationID)
        {
          pushViewController(viewController, animated: !transaction.uiKit.disablesAnimations)
        } else if difference.count == 1,
          case .remove(newPath.count, _, nil) = difference.first
        {
          popViewController(animated: transaction.uiKit.disablesAnimations)
        } else if difference.insertions.isEmpty, newPath.isEmpty {
          popToRootViewController(animated: transaction.uiKit.disablesAnimations)
        } else if difference.insertions.isEmpty,
          case let offsets = difference.removals.map(\.offset),
          let first = offsets.first,
          let last = offsets.last,
          offsets.elementsEqual(first...last),
          first == newPath.count
        {
          popToViewController(
            viewControllers[first], animated: !transaction.uiKit.disablesAnimations
          )
        } else {
          var newPath = newPath
          let oldViewControllers =
            viewControllers.isEmpty
            ? root.map { [$0] } ?? []
            : viewControllers
          var newViewControllers: [UIViewController] = []
          newViewControllers.reserveCapacity(max(viewControllers.count, newPath.count))

          loop: for viewController in oldViewControllers {
            if let navigationID = viewController.navigationID {
              guard navigationID == newPath.first
              else {
                break loop
              }
              newViewControllers.append(viewController)
              newPath.removeFirst()
            } else {
              newViewControllers.append(viewController)
            }
          }
          var invalidIndices = IndexSet()
          for (index, navigationID) in newPath.enumerated() {
            if let viewController = viewControllers.first(where: { $0.navigationID == navigationID }
            ) {
              newViewControllers.append(viewController)
            } else if let viewController = viewController(for: navigationID) {
              newViewControllers.append(viewController)
            } else if navigationID.element != nil, let elementType = navigationID.elementType {
              runtimeWarn(
                """
                No "navigationDestination(for: \(String(customDumping: elementType))) { … }" was \
                found among the view controllers on the path.
                """
              )
              invalidIndices.insert(index)
            }
          }
          path.remove(atOffsets: invalidIndices)
          setViewControllers(newViewControllers, animated: !transaction.uiKit.disablesAnimations)
        }
      }
    }

    fileprivate func viewController(
      for navigationID: UINavigationPath.Element
    ) -> UIViewController? {
      guard
        let destinationType = navigationID.elementType,
        let destination = destinations[DestinationType(destinationType)],
        let viewController = destination(navigationID),
        let element = navigationID.element
      else {
        return nil
      }
      viewController.navigationID = .eager(element)
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        viewController.traitOverrides
          .dismiss = UIDismissAction { [weak self, weak viewController] transaction in
            guard let self, let viewController else { return }
            popFromViewController(viewController, animated: !transaction.uiKit.disablesAnimations)
          }
      }
      
      return viewController
    }

    fileprivate struct DestinationType: Hashable {
      let rawValue: Any.Type
      init(_ rawValue: Any.Type) {
        self.rawValue = rawValue
      }
      static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
      }
      func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(rawValue))
      }
    }

    private final class PathDelegate: NSObject, UINavigationControllerDelegate {
      let viewController = UIViewController()
      weak var base: (any UINavigationControllerDelegate)?

      override func responds(to aSelector: Selector!) -> Bool {
        aSelector == #selector(navigationController(_:didShow:animated:))
          || base?.responds(to: aSelector) ?? false
      }

      func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
      ) {
        base?.navigationController?(
          navigationController, willShow: viewController, animated: animated
        )
      }

      func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
      ) {
        defer {
          base?.navigationController?(
            navigationController, didShow: viewController, animated: animated
          )
        }
        let navigationController = navigationController as! NavigationStackController
        if let nextIndex = navigationController.path.firstIndex(where: {
          guard case .lazy = $0 else { return false }
          return true
        }) {
          let nextElement = navigationController.path[nextIndex]
          let canPushElement =
            nextElement.elementType
            .map { navigationController.destinations.keys.contains(DestinationType($0)) }
            ?? false
          if !canPushElement {
            runtimeWarn(
              """
              Failed to decode item in navigation path at index \(nextIndex). Perhaps the \
              "navigationDestination" declarations have changed since the path was encoded?
              """
            )
            if let elementType = nextElement.elementType {
              runtimeWarn(
                """
                Missing navigation destination while decoding a "UINavigationPath". No \
                "navigationDestination(for: \(String(customDumping: elementType))) { … }" was \
                found among the view controllers on the path.
                """
              )
            }
            navigationController.path.removeSubrange(nextIndex...)
          }
          return
        }
        DispatchQueue.main.async {
          let oldPath = navigationController.path.filter {
            guard case .eager = $0 else { return false }
            return true
          }
          let newPath = navigationController.viewControllers.compactMap(\.navigationID)
          if oldPath.count > newPath.count {
            navigationController.path = newPath
          }
        }
      }

      #if !os(tvOS) && !os(watchOS)
        func navigationControllerSupportedInterfaceOrientations(
          _ navigationController: UINavigationController
        ) -> UIInterfaceOrientationMask {
          base?.navigationControllerSupportedInterfaceOrientations?(navigationController)
            ?? viewController.supportedInterfaceOrientations
        }

        func navigationControllerPreferredInterfaceOrientationForPresentation(
          _ navigationController: UINavigationController
        ) -> UIInterfaceOrientation {
          base?.navigationControllerPreferredInterfaceOrientationForPresentation?(
            navigationController
          )
            ?? viewController.preferredInterfaceOrientationForPresentation
        }
      #endif

      func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning
      ) -> (any UIViewControllerInteractiveTransitioning)? {
        base?.navigationController?(
          navigationController, interactionControllerFor: animationController
        )
      }

      func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
      ) -> (any UIViewControllerAnimatedTransitioning)? {
        base?.navigationController?(
          navigationController, animationControllerFor: operation, from: fromVC, to: toVC
        )
      }
    }
  }

  extension UIViewController {
    @available(iOS, deprecated: 17, message: "Use 'traitCollection.push(value:)', instead.")
    @available(macOS, deprecated: 14, message: "Use 'traitCollection.push(value:)', instead.")
    @available(tvOS, deprecated: 17, message: "Use 'traitCollection.push(value:)', instead.")
    @available(watchOS, deprecated: 10, message: "Use 'traitCollection.push(value:)', instead.")
    public func push<Element: Hashable>(value: Element) {
      _push(value: value)
    }

    fileprivate func _push<Element: Hashable>(value: Element) {
      // TODO: Is it possible for these two guards to fail? Only a NavigationStackController can
      //       set up the `push` trait, so it seems we are always guaranteed to have a
      //       stack controller.
      guard let navigationController = navigationController ?? self as? UINavigationController
      else {
        runtimeWarn(
          """
          Can't push value: "navigationController" is "nil".
          """
        )
        return
      }
      guard let stackController = navigationController as? NavigationStackController
      else {
        runtimeWarn(
          """
          Tried to push a value to a non-"NavigationStackController".
          """
        )
        return
      }
      stackController.path.append(.lazy(.element(value)))
    }

    public func navigationDestination<D: Hashable>(
      for data: D.Type,
      destination: @escaping (D) -> UIViewController
    ) {
      guard let navigationController = navigationController ?? self as? UINavigationController
      else {
        // TODO: Should `UIViewController` be able to lazily register?
        runtimeWarn(
          """
          Can't register navigation destination: "navigationController" is "nil".
          """
        )
        return
      }
      guard let stackController = navigationController as? NavigationStackController
      else {
        runtimeWarn(
          """
          Tried to apply a "navigationDestination" to a non-"NavigationStackController".
          """
        )
        return
      }

      stackController.destinations[NavigationStackController.DestinationType(data)] = {
        [weak stackController] element in
        guard let stackController else { fatalError() }

        switch element {
        case let .eager(value):
          return destination(value as! D)
        case let .lazy(.codable(value)):
          let index = stackController.path.firstIndex(of: element)!
          guard let value = value.decode()
          else {
            runtimeWarn(
              """
              Failed to decode item in navigation path at index \(index). Perhaps the \
              "navigationDestination" declarations have changed since the path was encoded?
              """
            )
            stackController.path.remove(at: index)
            return nil
          }
          stackController.path[index] = .eager(value)
          return destination(value as! D)
        case let .lazy(.element(value)):
          let index = stackController.path.firstIndex(of: element)!
          stackController.path[index] = .eager(value)
          return destination(value as! D)
        }
      }
      if stackController.path.contains(where: {
        guard case .lazy = $0, $0.elementType == D.self else { return false }
        return true
      }) {
        stackController.path = stackController.path
      }
    }

    fileprivate var navigationID: UINavigationPath.Element? {
      get {
        objc_getAssociatedObject(self, Self.navigationIDKey) as? UINavigationPath.Element
      }
      set {
        objc_setAssociatedObject(
          self, Self.navigationIDKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
      }
    }

    private static let navigationIDKey = malloc(1)!
  }

  extension CollectionDifference.Change {
    fileprivate var offset: Int {
      switch self {
      case let .insert(offset, _, _):
        return offset
      case let .remove(offset, _, _):
        return offset
      }
    }
  }

  extension RangeReplaceableCollection
  where
    Self: RandomAccessCollection,
    Element: Hashable
  {
    fileprivate var path: [UINavigationPath.Element] {
      get { map { .eager($0) } }
      set {
        replaceSubrange(
          startIndex..<endIndex,
          with: newValue.map {
            switch $0 {
            case let .eager(element), let .lazy(.element(element)):
              return element.base as! Element
            case .lazy(.codable):
              fatalError()
            }
          }
        )
      }
    }
  }
#endif
