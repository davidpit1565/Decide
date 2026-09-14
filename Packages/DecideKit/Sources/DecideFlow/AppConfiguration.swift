import Foundation

/// Everything environment-specific, read from the bundle at launch.
///
/// There is deliberately no API key here: the app talks only to DECIDE's own
/// endpoint, which holds the provider credentials server-side.
/// Anything that can answer "what is configured under this key?".
/// Lets the configuration be tested without building a bundle.
public protocol InfoValueProviding {
    func infoValue(forKey key: String) -> String?
}

extension Bundle: InfoValueProviding {
    public func infoValue(forKey key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}

public struct AppConfiguration: Sendable {
    public let apiBaseURL: URL?
    public let privacyPolicyURL: URL?
    public let termsURL: URL?
    public let supportURL: URL?
    public let isAnalyticsEnabledByDefault: Bool

    public static let shared = AppConfiguration(bundle: .main)

    public init(bundle: Bundle) {
        self.init(info: bundle)
    }

    public init(info: InfoValueProviding) {
        func url(_ key: String) -> URL? {
            guard let value = info.infoValue(forKey: key),
                  !value.trimmingCharacters(in: .whitespaces).isEmpty,
                  let url = URL(string: value.trimmingCharacters(in: .whitespaces)),
                  url.scheme?.lowercased() == "https"
            else { return nil }
            return url
        }

        apiBaseURL = url("DecideAPIBaseURL")
        privacyPolicyURL = url("DecidePrivacyPolicyURL")
        termsURL = url("DecideTermsURL")
        supportURL = url("DecideSupportURL")
        isAnalyticsEnabledByDefault = false
    }

    /// True when the app has somewhere to send analysis requests.
    public var isBackendConfigured: Bool { apiBaseURL != nil }
}
