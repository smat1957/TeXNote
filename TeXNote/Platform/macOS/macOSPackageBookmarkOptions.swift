import Foundation

enum PlatformPackageBookmarkOptions {
    static let creation: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolution: URL.BookmarkResolutionOptions = [.withSecurityScope]
}
