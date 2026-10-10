import Foundation

struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    static func validVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && Int($0) != nil }
    }
    func isNewer(than current: String) -> Bool {
        !draft && !prerelease && Self.validVersion(version) && Self.validVersion(current)
            && version.compare(current, options: .numeric) == .orderedDescending
    }
    var downloadURL: URL? {
        guard !draft, !prerelease, Self.validVersion(version) else { return nil }
        let filename = "FlowCat-\(version)-arm64.zip"
        return assets.first {
            $0.name == filename && $0.browser_download_url.scheme == "https"
                && $0.browser_download_url.host == "github.com"
                && $0.browser_download_url.path == "/tab16360/flowcat/releases/download/\(tag_name)/\(filename)"
        }?.browser_download_url
    }
}
