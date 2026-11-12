import FideSDK
import SwiftUI

/// One line of a player list: title, name, federation and the three ratings.
struct PlayerRow: View {
  let player: FidePlayer
  var trailingNote: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          if let title = player.title {
            TitleBadge(title: title)
          }
          Text(player.displayName)
            .font(.headline)
            .lineLimit(1)
          if player.isInactive {
            Image(systemName: "moon.zzz")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel("Inactivo")
          }
        }
        HStack(spacing: 6) {
          Text(federationFlag(player.federation) + " " + player.federation)
          Text("·")
          Text(verbatim: "ID \(player.id)")
          if let year = player.birthYear {
            Text("·")
            Text(verbatim: "\(year)")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if let trailingNote {
          Text(trailingNote)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      Spacer(minLength: 8)
      RatingsColumn(player: player)
    }
    .padding(.vertical, 2)
  }
}

struct RatingsColumn: View {
  let player: FidePlayer

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(player.standard.map { String($0.rating) } ?? "—")
        .font(.title3.monospacedDigit().weight(.semibold))
        .foregroundStyle(player.standard == nil ? .tertiary : .primary)
      HStack(spacing: 6) {
        Label(player.rapid.map { String($0.rating) } ?? "—", systemImage: "hare")
        Label(player.blitz.map { String($0.rating) } ?? "—", systemImage: "bolt")
      }
      .labelStyle(CompactLabelStyle())
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }
}

struct CompactLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 2) {
      configuration.icon.imageScale(.small)
      configuration.title
    }
  }
}

struct TitleBadge: View {
  let title: FideTitle

  var body: some View {
    Text(title.rawValue)
      .font(.caption2.weight(.bold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(color.opacity(0.18), in: .capsule)
      .foregroundStyle(color)
  }

  private var color: Color {
    switch title.rank {
    case 0, 4: .orange
    case 1, 5: .purple
    case 2, 6: .blue
    default: .teal
    }
  }
}

/// Regional-indicator flag for FIDE federations that share an ISO code prefix.
/// FIDE uses IOC-like codes, so only the common ones are mapped.
func federationFlag(_ code: String) -> String {
  let map = [
    "ESP": "ES", "NOR": "NO", "USA": "US", "FRA": "FR", "GER": "DE", "ITA": "IT", "IND": "IN",
    "CHN": "CN", "RUS": "RU", "NED": "NL", "ENG": "GB", "ARG": "AR", "MEX": "MX", "POR": "PT",
    "UKR": "UA", "POL": "PL", "HUN": "HU", "CZE": "CZ", "SWE": "SE", "DEN": "DK", "BRA": "BR",
    "IRI": "IR", "UZB": "UZ", "ARM": "AM", "AZE": "AZ", "TUR": "TR", "ISR": "IL", "CUB": "CU",
    "PER": "PE", "COL": "CO", "CHI": "CL", "VEN": "VE", "EGY": "EG", "GRE": "GR", "SUI": "CH",
    "AUT": "AT", "BEL": "BE", "CAN": "CA", "AUS": "AU", "JPN": "JP", "VIE": "VN", "PHI": "PH",
    "SRB": "RS", "CRO": "HR", "ROU": "RO", "BUL": "BG", "GEO": "GE", "KAZ": "KZ", "FIN": "FI",
  ]
  guard let iso = map[code] else { return "🏳️" }
  return iso.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
    .map(String.init).joined()
}

extension RatingKind {
  var label: String {
    switch self {
    case .standard: "Clásico"
    case .rapid: "Rápido"
    case .blitz: "Blitz"
    }
  }
}
