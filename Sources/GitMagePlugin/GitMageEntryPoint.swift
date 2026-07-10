import Foundation
import AinkradAppKit
import GitMageFeature

@objc(GitMageEntryPoint)
final class GitMageEntryPoint: NSObject, AinkradPluginEntryPoint {
    static func app() -> any AinkradApp.Type {
        GitMageApp.self
    }
}

