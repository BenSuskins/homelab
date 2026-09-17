import Foundation

/// Percent-encoding for query values that a Go server will read back unchanged.
///
/// `URLComponents.queryItems` encodes with `CharacterSet.urlQueryAllowed`,
/// which leaves `+` alone — and `net/url.ParseQuery`, which is how both Loki
/// and Prometheus read a request, decodes a bare `+` as a space.
///
/// That is not a theoretical problem: the logs screen's unfiltered selector is
/// `{container=~".+"}`, so what actually reached Loki was `{container=~". "}` —
/// a perfectly valid query that matches nothing. Picking a single container
/// worked because that selector has no `+` in it.
enum QueryEncoding {
    /// `urlQueryAllowed` minus the characters that are either ambiguous in a
    /// value (`+`) or structural in a query string (`&`, `=`, `?`, `#`, `;`).
    private static let valueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#;")
        return allowed
    }()

    /// Items ready for `URLComponents.percentEncodedQueryItems`, which — unlike
    /// `queryItems` — does not re-encode what it is given.
    static func encoded(_ items: [URLQueryItem]) -> [URLQueryItem] {
        items.map { item in
            URLQueryItem(
                name: escape(item.name),
                value: item.value.map(escape)
            )
        }
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? value
    }
}
