import CoreText
import Foundation

/// Registers the bundled Geist / Geist Mono faces with CoreText so `Font.custom`
/// can resolve them. Call once at app launch.
public enum EmberFonts {
    private static var didRegister = false

    private static let faces = [
        "Geist-Light", "Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold",
        "GeistMono-Regular", "GeistMono-Medium"
    ]

    public static func register() {
        guard !didRegister else { return }
        didRegister = true
        for name in faces {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
