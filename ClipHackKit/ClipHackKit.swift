import Foundation

/// Shared logic for the ClipHack app, extracted into a framework so the unit
/// tests can run as a plain host-less bundle instead of launching the GUI app
/// as an XCTest host (which hangs under Xcode 26 on CI's headless runner).
public enum ClipHackKit {
    public static let moduleName = "ClipHackKit"
}
