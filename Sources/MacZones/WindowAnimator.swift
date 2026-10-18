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
        let from: CGRect
        let to: CGRect
        let start = CACurrentMediaTime()
        let duration: CFTimeInterval
        let completion: () -> Void
        let resumeEnhancedUserInterface: () -> Void
        var timer: Timer?

        init(window: AXWindow, from: CGRect, to: CGRect, duration: CFTimeInterval, completion: @escaping () -> Void) {
            self.window = window
            self.from = from
            self.to = to
            self.duration = duration
            self.completion = completion
            resumeEnhancedUserInterface = window.suspendEnhancedUserInterface()
        }
    }

    private var animations: [Animation] = []

    /// Animates `window` to `target`, then lands it exactly with `setFrame` and
    /// calls `completion`. Replaces any animation already running on the window.
    func animate(_ window: AXWindow, to target: CGRect, duration: TimeInterval, completion: @escaping () -> Void) {
        cancel(window)
        guard let origin = window.position, let size = window.size else {
            window.setFrame(target)
            completion()
            return
        }
        let animation = Animation(window: window, from: CGRect(origin: origin, size: size), to: target,
                                  duration: duration, completion: completion)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak animation] _ in
            MainActor.assumeIsolated {
                guard let self, let animation else { return }
                self.step(animation)
            }
        }
        // .common keeps the timer firing while the user holds the mouse elsewhere.
        RunLoop.main.add(timer, forMode: .common)
        animation.timer = timer
        animations.append(animation)
        step(animation)
    }

    /// Stops any animation on `window` where it is, without calling its completion.
    func cancel(_ window: AXWindow) {
        for animation in animations where animation.window.isSame(window) {
            finish(animation, land: false)
        }
    }

    private func step(_ animation: Animation) {
        let progress = min((CACurrentMediaTime() - animation.start) / animation.duration, 1)
        guard progress < 1 else {
            finish(animation, land: true)
            return
        }
        let eased = 1 - pow(1 - progress, 3)
        animation.window.setAnimationFrame(interpolate(animation.from, animation.to, eased))
    }

    private func finish(_ animation: Animation, land: Bool) {
        animation.timer?.invalidate()
        animation.timer = nil
        animations.removeAll { $0 === animation }
        animation.resumeEnhancedUserInterface()
        if land {
            animation.window.setFrame(animation.to)
            animation.completion()
        }
    }

    private func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { (x + (y - x) * t).rounded() }
        return CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY),
                      width: mix(a.width, b.width), height: mix(a.height, b.height))
    }
}
