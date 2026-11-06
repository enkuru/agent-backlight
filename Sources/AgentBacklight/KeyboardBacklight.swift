import Foundation
import ObjectiveC

/// The built-in keyboard backlight, driven through CoreBrightness's private `KeyboardBrightnessClient`.
/// Each method is checked against the type encoding this code was written for, so a macOS update that
/// changes one stops the bridge at launch instead of crashing mid-signal.
@MainActor
final class KeyboardBacklight {
    struct Unavailable: Error, CustomStringConvertible {
        let description: String
    }

    private typealias GetLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetLevel = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private typealias GetFlag = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias SetFlag = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool

    private struct Call<Function> {
        let selector: Selector
        let function: Function
    }

    private let client: NSObject
    private let keyboard: UInt64
    private let getLevel: Call<GetLevel>
    private let setLevel: Call<SetLevel>
    private let suspendIdleDimming: Call<SetFlag>

    init() throws(Unavailable) {
        guard let framework = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"), framework.load(),
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            throw Unavailable(description: "CoreBrightness has no KeyboardBrightnessClient")
        }

        func method(_ name: String, _ encoding: String) throws(Unavailable) -> Method {
            guard let method = class_getInstanceMethod(type, NSSelectorFromString(name)),
                  let types = method_getTypeEncoding(method), String(cString: types) == encoding else {
                throw Unavailable(description: "KeyboardBrightnessClient.\(name) changed in this macOS version")
            }
            return method
        }
        func call<Function>(_ name: String, _ encoding: String, as _: Function.Type) throws(Unavailable) -> Call<Function> {
            let found = try method(name, encoding)
            return Call(selector: method_getName(found), function: unsafeBitCast(method_getImplementation(found), to: Function.self))
        }

        getLevel = try call("brightnessForKeyboard:", "f24@0:8Q16", as: GetLevel.self)
        setLevel = try call("setBrightness:fadeSpeed:commit:forKeyboard:", "B36@0:8f16i20B24Q28", as: SetLevel.self)
        suspendIdleDimming = try call("suspendIdleDimming:forKeyboard:", "B28@0:8B16Q20", as: SetFlag.self)
        let isBuiltIn = try call("isKeyboardBuiltIn:", "B24@0:8Q16", as: GetFlag.self)
        let copyIDs = method_getName(try method("copyKeyboardBacklightIDs", "@16@0:8"))

        let client = type.init()
        let ids = (client.perform(copyIDs)?.takeRetainedValue() as? [NSNumber] ?? []).map(\.uint64Value)
        guard let builtIn = ids.first(where: { isBuiltIn.function(client, isBuiltIn.selector, $0) }) else {
            throw Unavailable(description: "This Mac has no built-in keyboard backlight")
        }
        self.client = client
        keyboard = builtIn
    }

    /// Sets the level at once, without saving it as the user's level.
    func set(_ level: Double) {
        write(level, commit: false)
    }

    /// Stops macOS from dimming the light while a signal runs. Returns the user's level, from 0 to 1.
    func takeOver() -> Double {
        // While the keys are idle-dimmed the level reads 0, so idle dimming is suspended before the read.
        _ = suspendIdleDimming.function(client, suspendIdleDimming.selector, true, keyboard)
        return Double(getLevel.function(client, getLevel.selector, keyboard))
    }

    /// Puts back the user's level and lets macOS manage the light again.
    ///
    /// The level is committed, as the brightness slider does: any uncommitted write makes macOS's brightness
    /// daemon suspend auto-brightness, and while that lasts the keys stay dark when the user types.
    /// Only a committed change ends it.
    func handBack(level: Double) {
        write(level, commit: true)
        _ = suspendIdleDimming.function(client, suspendIdleDimming.selector, false, keyboard)
    }

    private func write(_ level: Double, commit: Bool) {
        _ = setLevel.function(client, setLevel.selector, Float(min(1, max(0, level))), 0, commit, keyboard)
    }
}
