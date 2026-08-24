import Foundation

enum PlaceNameFormatter {
    static func string(
        locality: String?,
        subAdministrativeArea: String?,
        administrativeArea: String?,
        country: String?
    ) -> String? {
        [locality, subAdministrativeArea, administrativeArea, country]
            .compactMap(normalized)
            .first
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(40))
    }
}
