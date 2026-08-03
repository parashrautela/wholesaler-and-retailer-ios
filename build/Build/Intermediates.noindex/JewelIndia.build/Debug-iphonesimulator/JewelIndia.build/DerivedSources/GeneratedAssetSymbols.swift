import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "LaunchBackground" asset catalog color resource.
    static let launchBackground = DeveloperToolsSupport.ColorResource(name: "LaunchBackground", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "JewelLogo" asset catalog image resource.
    static let jewelLogo = DeveloperToolsSupport.ImageResource(name: "JewelLogo", bundle: resourceBundle)

    /// The "NavAddRetailer" asset catalog image resource.
    static let navAddRetailer = DeveloperToolsSupport.ImageResource(name: "NavAddRetailer", bundle: resourceBundle)

    /// The "NavCatalogue" asset catalog image resource.
    static let navCatalogue = DeveloperToolsSupport.ImageResource(name: "NavCatalogue", bundle: resourceBundle)

    /// The "NavChat" asset catalog image resource.
    static let navChat = DeveloperToolsSupport.ImageResource(name: "NavChat", bundle: resourceBundle)

    /// The "NavHome" asset catalog image resource.
    static let navHome = DeveloperToolsSupport.ImageResource(name: "NavHome", bundle: resourceBundle)

    /// The "NavOrders" asset catalog image resource.
    static let navOrders = DeveloperToolsSupport.ImageResource(name: "NavOrders", bundle: resourceBundle)

    /// The "NavUpload" asset catalog image resource.
    static let navUpload = DeveloperToolsSupport.ImageResource(name: "NavUpload", bundle: resourceBundle)

}

