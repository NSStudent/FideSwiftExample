import FideSDK
import SwiftUI

/// Shows the update strategy at work: detected release, Lichess readiness, events.
struct StatusView: View {
  @Environment(ShowcaseModel.self) private var model
  @AppStorage(ShowcaseModel.Settings.immediateMode) private var immediateMode = false
  @State private var checkResult: String?

  var body: some View {
    List {
      releaseSection
      actionsSection
      Section {
        Toggle("Modo inmediato (ratings.fide.com)", isOn: $immediateMode)
      } header: {
        Text("Ajustes")
      } footer: {
        Text(
          "Lee los valores nuevos directamente de FIDE en cuanto publica la lista, sin esperar a Lichess (máx. 50 seguidos). Se aplica al reiniciar la app."
        )
      }
      eventsSection
    }
    .navigationTitle("Estado")
    .refreshable { await model.refreshStatus() }
  }

  @ViewBuilder
  private var releaseSection: some View {
    Section {
      if let state = model.syncState {
        LabeledContent("Última comprobación") {
          if let last = state.lastCheckedAt {
            Text(last, format: .relative(presentation: .named))
          } else {
            Text("Nunca")
          }
        }
        if let error = state.lastCheckError {
          LabeledContent("Error", value: error)
        }
        LabeledContent("Lista FIDE detectada") {
          Text(state.releaseLastModified.map { YearMonth(date: $0).description } ?? "—")
        }
        if let published = state.releaseLastModified {
          LabeledContent("Publicada") {
            Text(published.formatted(date: .abbreviated, time: .shortened))
          }
          let ready = UpdatePlanner.lichessReadyAt(
            publishedAt: published,
            syncHourUTC: model.client.configuration.lichessSyncHourUTC,
            margin: model.client.configuration.lichessSyncMargin)
          LabeledContent("Lichess al día desde") {
            Text(ready.formatted(date: .abbreviated, time: .shortened))
              .foregroundStyle(ready > .now ? .orange : .primary)
          }
        }
        LabeledContent("Aplicada a seguidos") {
          Image(
            systemName: state.appliedReleaseIdentity != nil
              && state.appliedReleaseIdentity == state.releaseIdentity
              ? "checkmark.circle.fill" : "clock")
        }
        if let retry = state.verificationRetryAt {
          LabeledContent("Reverificación") {
            Text(retry, format: .relative(presentation: .named))
          }
        }
      } else {
        ProgressView()
      }
    } header: {
      Text("Lista mensual")
    } footer: {
      Text(
        "FIDE publica una vez al mes (no siempre el día 1). Lichess importa la lista a diario a las 04:00 UTC, así que tras una publicación el SDK espera a esa hora antes de refrescar."
      )
    }
  }

  private var actionsSection: some View {
    Section {
      Button("Comprobar si hay lista nueva", systemImage: "antenna.radiowaves.left.and.right") {
        Task {
          do {
            let status = try await model.client.checkForListUpdate(force: true)
            checkResult =
              switch status {
              case .upToDate: "Sin cambios (HTTP 304)"
              case .newRelease(let release): "Nueva lista \(release.listMonth?.description ?? "")"
              case .skipped: "Omitido"
              }
          } catch {
            checkResult = FideError.describe(error).message
          }
          await model.refreshStatus()
        }
      }
      if let checkResult {
        Text(checkResult).font(.caption).foregroundStyle(.secondary)
      }
      Button("Ejecutar actualización programada", systemImage: "arrow.triangle.2.circlepath") {
        Task { await model.runScheduledUpdate(force: true) }
      }
      .disabled(model.isUpdating)
      if let report = model.lastReport, let date = model.lastReportDate {
        UpdateReportView(report: report, date: date)
      }
    } header: {
      Text("Acciones")
    }
  }

  private var eventsSection: some View {
    Section("Eventos del SDK") {
      if model.events.isEmpty {
        Text("Todavía no hay eventos").foregroundStyle(.secondary)
      }
      ForEach(model.events.filter { !$0.event.isDownloadProgress }.prefix(50)) { entry in
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.event.summary).font(.callout)
          Text(entry.date.formatted(date: .omitted, time: .standard))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    }
  }
}

extension FideEvent {
  var isDownloadProgress: Bool {
    if case .listSync(.downloading) = self { return true }
    if case .listSync(.importing) = self { return true }
    return false
  }

  var summary: String {
    switch self {
    case .newListDetected(let release):
      "📣 Nueva lista FIDE \(release.listMonth?.description ?? "")"
    case .refreshPending(let until):
      "⏳ Esperando a Lichess hasta \(until.formatted(date: .omitted, time: .shortened))"
    case .trackedPlayersUpdated(let changes):
      "⭐️ "
        + changes.map { change in
          let deltas = change.ratings.map { delta in
            "\(delta.kind.label.prefix(3)) \(delta.old.map(String.init) ?? "—")→\(delta.new.map(String.init) ?? "—")"
          }
          return "\(PlayerName(change.name).lastName): \(deltas.joined(separator: ", "))"
        }.joined(separator: " · ")
    case .listSync(let progress):
      switch progress {
      case .checking: "🔎 Comprobando lista oficial"
      case .upToDate: "✅ Lista offline al día"
      case .downloading: "⬇️ Descargando"
      case .importing: "📥 Importando"
      case .indexing: "🗂️ Indexando"
      case .finished(let count, let month):
        "✅ Lista \(month?.description ?? "") importada: \(count.formatted()) jugadores"
      }
    }
  }
}
