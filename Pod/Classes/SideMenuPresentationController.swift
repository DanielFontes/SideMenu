//
//  BasePresentationController.swift
//  SideMenu
//
//  Created by Jon Kent on 10/20/18.
//

import UIKit

internal protocol PresentationModel {
    /// Draws `presentStyle.backgroundColor` behind the status bar. Default is 1.
    var statusBarEndAlpha: CGFloat { get }
    /// Enable or disable interaction with the presenting view controller while the menu is displayed. Enabling may make it difficult to dismiss the menu or cause exceptions if the user tries to present and already presented menu. `presentingViewControllerUseSnapshot` must also set to false. Default is false.
    var presentingViewControllerUserInteractionEnabled: Bool { get }
    /// Use a snapshot for the presenting vierw controller while the menu is displayed. Useful when layout changes occur during transitions. Not recommended for apps that support rotation. Default is false.
    var presentingViewControllerUseSnapshot: Bool { get }
    /// The presentation style of the menu.
    var presentationStyle: SideMenuPresentationStyle { get }
    /// Width of the menu when presented on screen, showing the existing view controller in the remaining space. Default is zero.
    var menuWidth: CGFloat { get }
}

internal protocol SideMenuPresentationControllerDelegate: class {
    func sideMenuPresentationControllerDidTap(_ presentationController: SideMenuPresentationController)
    func sideMenuPresentationController(_ presentationController: SideMenuPresentationController, didPanWith gesture: UIPanGestureRecognizer)
}

internal final class SideMenuPresentationController {

    private let config: PresentationModel
    private weak var containerView: UIView?
    private var interactivePopGestureRecognizerEnabled: Bool?
    private var clipsToBounds: Bool?
    private let leftSide: Bool
    private weak var presentedViewController: UIViewController?
    private weak var presentingViewController: UIViewController?

    private lazy var snapshotView: UIView? = {
        guard
            config.presentingViewControllerUseSnapshot,
            let presentingVC = self.presentingViewController,
            let view = presentingVC.view.snapshotView(afterScreenUpdates: true)
        else { return nil }

        view.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        return view
    }()

    private lazy var statusBarView: UIView? = {
        guard config.statusBarEndAlpha > .leastNonzeroMagnitude else { return nil }

        return UIView {
            $0.backgroundColor = config.presentationStyle.backgroundColor
            $0.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            $0.isUserInteractionEnabled = false
        }
    }()

    required init(config: PresentationModel, leftSide: Bool, presentedViewController: UIViewController, presentingViewController: UIViewController, containerView: UIView) {
        self.config = config
        self.containerView = containerView
        self.leftSide = leftSide
        self.presentedViewController = presentedViewController
        self.presentingViewController = presentingViewController
    }

    deinit {
        guard
            let presentedVC = self.presentedViewController,
            !presentedVC.isHidden
        else { return }

        // Presentations must be reversed to preserve user experience
        dismissalTransitionWillBegin()
        dismissalTransition()
        dismissalTransitionDidEnd(true)
    }
    
    func containerViewWillLayoutSubviews() {
        guard let containerView = containerView else { return }

        if let presentedVC = self.presentedViewController {
            presentedVC.view.untransform {
                presentedVC.view.frame = frameOfPresentedViewInContainerView
            }
        }

        if let presentingVC = self.presentingViewController {
            presentingVC.view.untransform {
                presentingVC.view.frame = frameOfPresentingViewInContainerView
                snapshotView?.frame = presentingVC.view.bounds
            }
        }

        guard let statusBarView = statusBarView else { return }

        var statusBarFrame: CGRect = self.statusBarFrame
        statusBarFrame.size.height -= containerView.frame.minY
        statusBarView.frame = statusBarFrame
    }
    
    func presentationTransitionWillBegin() {
    	guard let containerView = containerView else { return }

        if  let snapshotView = snapshotView,
            let presentingVC = self.presentingViewController
        {
            presentingVC.view.addSubview(snapshotView)
        }

        presentingViewController?.view.isUserInteractionEnabled = config.presentingViewControllerUserInteractionEnabled
        containerView.backgroundColor = config.presentationStyle.backgroundColor
        
        layerViews()

        if let statusBarView = statusBarView {
            containerView.addSubview(statusBarView)
        }
        
        dismissalTransition()
        if  let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        {
            config.presentationStyle.presentationTransitionWillBegin(to: presentedVC, from: presentingVC)
        }
    }

    func presentationTransition() {
        
        guard
            let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        else { return }

        transition(
            to: presentedVC,
            from: presentingVC,
            alpha: config.presentationStyle.presentingEndAlpha,
            statusBarAlpha: config.statusBarEndAlpha,
            scale: config.presentationStyle.presentingScaleFactor,
            translate: config.presentationStyle.presentingTranslateFactor
        )

        if  let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        {
            config.presentationStyle.presentationTransition(to: presentedVC, from: presentingVC)
        }
    }
    
    func presentationTransitionDidEnd(_ completed: Bool) {
        guard completed else {
            snapshotView?.removeFromSuperview()
            dismissalTransitionDidEnd(!completed)
            return
        }
        
        guard
            let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        else { return }

        addParallax(to: presentingVC.view)
        
        if let topNavigationController = presentingVC as? UINavigationController {
            interactivePopGestureRecognizerEnabled = topNavigationController.interactivePopGestureRecognizer?.isEnabled
            topNavigationController.interactivePopGestureRecognizer?.isEnabled = false
        }

        containerViewWillLayoutSubviews()
        config.presentationStyle.presentationTransitionDidEnd(to: presentedVC, from: presentingVC, completed)
    }

    func dismissalTransitionWillBegin() {
        snapshotView?.removeFromSuperview()
        presentationTransition()

        if  let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        {
            config.presentationStyle.dismissalTransitionWillBegin(to: presentedVC, from: presentingVC)
        }
    }

    func dismissalTransition() {
        guard
            let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        else { return }
        
        transition(
            to: presentingVC,
            from: presentedVC,
            alpha: config.presentationStyle.menuStartAlpha,
            statusBarAlpha: 0,
            scale: config.presentationStyle.menuScaleFactor,
            translate: config.presentationStyle.menuTranslateFactor
        )

        config.presentationStyle.dismissalTransition(to: presentedVC, from: presentingVC)
    }

    func dismissalTransitionDidEnd(_ completed: Bool) {
        guard
            let presentedVC = self.presentedViewController,
            let presentingVC = self.presentingViewController
        else { return }
        
        guard completed else {
            if let snapshotView = snapshotView {
                presentingVC.view.addSubview(snapshotView)
            }
            presentationTransitionDidEnd(!completed)
            return
        }

        guard let presentedViewController = presentedViewController,
            let presentingViewController = presentingViewController
            else { return }

        statusBarView?.removeFromSuperview()
        removeStyles(from: presentingVC.containerViewController.view)
        
        if let interactivePopGestureRecognizerEnabled = interactivePopGestureRecognizerEnabled,
            let topNavigationController = presentingViewController as? UINavigationController {
            topNavigationController.interactivePopGestureRecognizer?.isEnabled = interactivePopGestureRecognizerEnabled
        }

        presentingVC.view.isUserInteractionEnabled = true
        config.presentationStyle.dismissalTransitionDidEnd(to: presentedVC, from: presentingVC, completed)
    }
}

private extension SideMenuPresentationController {

    var statusBarFrame: CGRect {
        if #available(iOS 13.0, *) {
            return containerView?.window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero
        } else {
            return UIApplication.shared.statusBarFrame
        }
    }

    var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView else { return .zero }
        var rect = containerView.bounds
        rect.origin.x = leftSide ? 0 : rect.width - config.menuWidth
        rect.size.width = config.menuWidth
        return rect
    }

    var frameOfPresentingViewInContainerView: CGRect {
        guard let containerView = containerView else { return .zero }
        var rect = containerView.frame
        if containerView.superview != nil, containerView.frame.minY > .ulpOfOne {
            let statusBarOffset = statusBarFrame.height - rect.minY
            rect.origin.y = statusBarOffset
            rect.size.height -= statusBarOffset
        }
        return rect
    }

    func transition(to: UIViewController, from: UIViewController, alpha: CGFloat, statusBarAlpha: CGFloat, scale: CGFloat, translate: CGFloat) {
        containerViewWillLayoutSubviews()
        
        to.view.transform = .identity
        to.view.alpha = 1

        let x = (leftSide ? 1 : -1) * config.menuWidth * translate
        from.view.alpha = alpha
        from.view.transform = CGAffineTransform
            .identity
            .translatedBy(x: x, y: 0)
            .scaledBy(x: scale, y: scale)

        statusBarView?.alpha = statusBarAlpha
    }

    func layerViews() {
        guard let presentedVC = presentedViewController else { return }

        statusBarView?.layer.zPosition = 2

        if  config.presentationStyle.menuOnTop,
            let presentedVC = self.presentedViewController
        {
            addShadow(to: presentedVC.view)
            presentedVC.view.layer.zPosition = 1
        }
        else if let presentingVC = self.presentingViewController
        {
            addShadow(to: presentingVC.view)
            presentedVC.view.layer.zPosition = -1
        }
    }

    func addShadow(to view: UIView) {
        view.layer.shadowColor = config.presentationStyle.onTopShadowColor.cgColor
        view.layer.shadowRadius = config.presentationStyle.onTopShadowRadius
        view.layer.shadowOpacity = config.presentationStyle.onTopShadowOpacity
        view.layer.shadowOffset = config.presentationStyle.onTopShadowOffset
        clipsToBounds = clipsToBounds ?? view.clipsToBounds
        view.clipsToBounds = false
    }

    func addParallax(to view: UIView) {
        var effects: [UIInterpolatingMotionEffect] = []

        let x = config.presentationStyle.presentingParallaxStrength.width
        if x > 0 {
            let horizontal = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
            horizontal.minimumRelativeValue = -x
            horizontal.maximumRelativeValue = x
            effects.append(horizontal)
        }

        let y = config.presentationStyle.presentingParallaxStrength.height
        if y > 0 {
            let vertical = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
            vertical.minimumRelativeValue = -y
            vertical.maximumRelativeValue = y
            effects.append(vertical)
        }

        if effects.count > 0 {
            let group = UIMotionEffectGroup()
            group.motionEffects = effects
            view.motionEffects.removeAll()
            view.addMotionEffect(group)
        }
    }

    func removeStyles(from view: UIView) {
        view.motionEffects.removeAll()
        view.layer.shadowOpacity = 0
        view.layer.shadowOpacity = 0
        view.clipsToBounds = clipsToBounds ?? true
        clipsToBounds = false
    }
}
