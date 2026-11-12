import FideSDK
import SQLiteData
import SwiftUI

struct TrackedView: View {
  @Environment(ShowcaseModel.self) private var model
  @FetchAll(TrackedPlayerRecord.order { $0.columns.name }) private var tracked

  var body: some View {
    List {
      if let report = model.lastReport, let date = model.lastReportDate {
        Section("Última actualización") {
          UpdateReportView(report: report, date: date)
        }
      }
      if let error = model.updateError {
        Section {
          Label(error.message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }
      Section {
        ForEach(tracked) { record in
          NavigationLink(value: record.player) {
            PlayerRow(player: record.player, trailingNote: subtitle(for: record))
          }
        }
        .onDelete { offsets in
          let ids = offsets.map { tracked[$0].id }
          Task {
            for id in ids { try? await model.client.untrack(id: id) }
          }
        }
      } footer: {
        if !tracked.isEmpty {
          Text("Datos guardados en local: se muestran al instante y sin conexión.")
        }
      }
    }
    .overlay {
      if tracked.isEmpty {
        ContentUnavailableView(
          "Sin jugadores seguidos", systemImage: "star",
          description: Text("Busca un jugador y pulsa «Seguir jugador»."))
      }
    }
    .navigationTitle("Seguidos")
    .navigationDestination(for: FidePlayer.self) { PlayerDetailView(player: $0) }
    .refreshable { await model.runScheduledUpdate(force: true) }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if model.isUpdating {
          ProgressView()
        } else {
          Button("Actualizar", systemImage: "arrow.clockwise") {
            Task { await model.runScheduledUpdate(force: true) }
          }
        }
      }
    }
  }

  private func subtitle(for record: TrackedPlayerRecord) -> String {
    var parts = ["Lista \(record.dataListMonth ?? "—")"]
    if let refreshed = record.lastRefreshedAt {
      parts.append("actualizado " + refreshed.formatted(.relative(presentation: .named)))
    }
    if let note = record.note, !note.isEmpty { parts.append("«\(note)»") }
    return parts.joined(separator: " · ")
  }
}

struct UpdateReportView: View {
  let report: UpdateReport
  let date: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(actionText, systemImage: actionSymbol)
        .font(.subheadline.weight(.semibold))
      Text(checkText)
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(report.changes, id: \.playerID) { change in
        HStack {
          Text(PlayerName(change.name).displayName).font(.caption)
          Spacer()
          ForEach(change.ratings, id: \.kind) { delta in
            DeltaBadge(delta: delta)
          }
        }
      }
      ForEach(Array(report.errors.enumerated()), id: \.offset) { _, error in
        Text(error.message).font(.caption).foregroundStyle(.orange)
      }
      Text(date, format: .relative(presentation: .named))
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
  }

  private var actionText: String {
    switch report.action {
    case .none:
      report.ttlRefreshed > 0
        ? "Refrescados \(report.ttlRefreshed) por antigüedad (TTL)" : "Nada que hacer"
    case .markedApplied: "Lista nueva registrada"
    case .reimportedList: "Lista offline reimportada"
    case .refreshedFromLocalList: "Actualizados desde la lista local"
    case .refreshedFromFIDE: "Actualizados desde ratings.fide.com"
    case .refreshedFromLichess: "Actualizados \(report.refreshed) desde Lichess"
    case .verifiedWithLichess: "Verificación con Lichess"
    case .pending(let until):
      "Esperando a Lichess hasta las \(until.formatted(date: .omitted, time: .shortened))"
    }
  }

  private var actionSymbol: String {
    switch report.action {
    case .pending: "hourglass"
    case .none: "checkmark.circle"
    default: "arrow.triangle.2.circlepath"
    }
  }

  private var checkText: String {
    switch report.check {
    case .newRelease(let release):
      "FIDE: lista nueva \(release.listMonth?.description ?? "")"
    case .upToDate: "FIDE: sin cambios (304)"
    case .skipped(let last):
      "FIDE: comprobado " + last.formatted(.relative(presentation: .named))
    case nil: "FIDE: " + (report.checkError?.message ?? "sin comprobar")
    }
  }
}

struct DeltaBadge: View {
  let delta: PlayerChange.RatingDelta

  var body: some View {
    let difference = delta.difference ?? 0
    Text(
      "\(delta.kind.label.prefix(3)) \(difference >= 0 ? "+" : "")\(difference)"
    )
    .font(.caption2.monospacedDigit().weight(.semibold))
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .background((difference >= 0 ? Color.green : Color.red).opacity(0.15), in: .capsule)
    .foregroundStyle(difference >= 0 ? .green : .red)
  }
}
