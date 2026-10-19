import AppKit
import QuartzCore

/// Glides windows to a target frame by stepping their Accessibility position
/// and size at display rate. There is no public API to animate another app's
/// window, so each step makes the app re-lay itself out; heavy apps may stutter.
@MainActor
final class WindowAnimator {
    @MainActor
    private final class Animation {
        let window: AXWindow
        let start = CACurrentMediaTime()
        let duration: CFTimeInterval
        /// The frame at eased progress 0...1.
        let frame: (Double) -> CGRect
        let completion: () -> Void
        let resumeEnhancedUserInterface: () -> Void
        var timer: Timer?

        init(window: AXWindow, duration: CFTimeInterval, frame: @escaping (Double) -> CGRect, completion: @escaping () -> Void) {
            self.window = window
            self.duration = duration
            self.frame = frame
            self.completion = completion
            resumeEnhancedUserInterface = window.suspendEnhancedUserInterface()
        }
    }

    private var animations: [Animation] = []

    /// Animates `window` to `target`, then lands it exactly with `setFrame` and
    /// calls `completion`. Replaces any animation already running on the window.
    func animate(_ window: AXWindow, to target: CGRect, duration: TimeInterval, completion: @escaping () -> Void = {}) {
        guard let origin = window.position, let size = window.size else {
            cancel(window)
            window.setFrame(target)
            completion()
            return
        }
        let from = CGRect(origin: origin, size: size)
        run(window, duration: duration, frame: { Self.interpolate(from, target, $0) }, completion: completion)
    }

    /// Animates `window`'s size from `from` to `to`, placing it each frame at
    /// `origin(size)`. Use while the user is dragging the window, with an
    /// origin that follows the cursor, so the window stays under the mouse.
    func animateResize(_ window: AXWindow, from: CGSize, to: CGSize, duration: TimeInterval,
                       origin: @escaping (CGSize) -> CGPoint, completion: @escaping () -> Void = {}) {
        run(window, duration: duration, frame: { progress in
            let size = CGSize(width: Self.mix(from.width, to.width, progress),
                              height: Self.mix(from.height, to.height, progress))
            return CGRect(origin: origin(size), size: size)
        }, completion: completion)
    }

    func isAnimating(_ window: AXWindow) -> Bool {
        animations.contains { $0.window.isSame(window) }
    }

    /// Stops any animation on `window` where it is, without calling its completion.
    func cancel(_ window: AXWindow) {
        for animation in animations where animation.window.isSame(window) {
            finish(animation, land: false)
        }
    }

    private func run(_ window: AXWindow, duration: TimeInterval, frame: @escaping (Double) -> CGRect,
                     completion: @escaping () -> Void) {
        cancel(window)
        let animation = Animation(window: window, duration: duration, frame: frame, completion: completion)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak animation] _ in
            MainActor.assumeIsolated {
                guard let self, let animation else { return }
                self.step(animation)
            }
        }
        // .common keeps the timer firing during mouse tracking.
        RunLoop.main.add(timer, forMode: .common)
        animation.timer = timer
        animations.append(animation)
        step(animation)
    }

    private func step(_ animation: Animation) {
        let progress = min((CACurrentMediaTime() - animation.start) / animation.duration, 1)
        guard progress < 1 else {
            finish(animation, land: true)
            return
        }
        animation.window.setAnimationFrame(animation.frame(1 - pow(1 - progress, 3)))
    }

    private func finish(_ animation: Animation, land: Bool) {
        animation.timer?.invalidate()
        animation.timer = nil
        animations.removeAll { $0 === animation }
        animation.resumeEnhancedUserInterface()
        if land {
            animation.window.setFrame(animation.frame(1))
            animation.completion()
        }
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        (a + (b - a) * t).rounded()
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t),
               width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
    }
}
