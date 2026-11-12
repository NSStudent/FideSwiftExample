import Charts
import FideSDK
import SQLiteData
import SwiftUI

struct PlayerDetailView: View {
  @Environment(ShowcaseModel.self) private var model
  @State private var player: FidePlayer
  @State private var history: RatingHistory?
  @State private var historyDensity = RatingHistory.Density.dense
  @State private var historyError: FideError?
  @State private var kind = RatingKind.standard
  @State private var range = HistoryRange.fiveYears
  @State private var actionError: FideError?
  @State private var isWorking = false
  @State private var note = ""

  @FetchAll private var trackedRows: [TrackedPlayerRecord]
  @FetchAll private var snapshots: [RatingSnapshotRecord]

  init(player: FidePlayer) {
    _player = State(initialValue: player)
  }

  private var tracked: TrackedPlayerRecord? { trackedRows.first }

  var body: some View {
    List {
      header
      ratingsSection
      historySection
      trackingSection
      if tracked != nil, !snapshots.isEmpty {
        snapshotsSection
      }
      if !player.otherTitles.isEmpty || player.onlineTitle != nil {
        Section("Otros títulos") {
          if !player.otherTitles.isEmpty {
            LabeledContent(
              "Árbitro / entrenador", value: player.otherTitles.joined(separator: ", "))
          }
          if let online = player.onlineTitle {
            LabeledContent("FIDE Online Arena", value: online)
          }
        }
      }
    }
    .navigationTitle(player.lastName)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: player.id) { await load() }
    .alert(
      "Error", isPresented: .constant(actionError != nil),
      presenting: actionError
    ) { _ in
      Button("OK") { actionError = nil }
    } message: {
      Text($0.message)
    }
  }

  // MARK: Sections

  private var header: some View {
    Section {
      HStack(alignment: .center, spacing: 14) {
        Group {
          if let url = player.photoURL {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Color.secondary.opacity(0.15)
            }
          } else {
            Image(systemName: "person.crop.circle.fill")
              .resizable()
              .foregroundStyle(.secondary.opacity(0.4))
          }
        }
        .frame(width: 64, height: 64)
        .clipShape(.circle)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            if let title = player.title { TitleBadge(title: title) }
            if let women = player.womenTitle, women != player.title { TitleBadge(title: women) }
            if player.isInactive {
              Text("Inactivo").font(.caption2).foregroundStyle(.secondary)
            }
          }
          Text(player.displayName).font(.title3.weight(.semibold))
          Text(
            "\(federationFlag(player.federation)) \(player.federation) · FIDE ID \(String(player.id))"
              + (player.birthYear.map { " · \($0)" } ?? "")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)
    } footer: {
      // Photos come from Lichess with a credit that must be shown alongside them.
      if player.photoURL != nil, let credit = player.photoCredit {
        Label("Foto: \(credit)", systemImage: "camera")
          .font(.caption2)
      }
    }
  }

  private var ratingsSection: some View {
    Section("Ratings") {
      Grid(horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          ForEach(RatingKind.allCases, id: \.self) { kind in
            VStack(spacing: 2) {
              Text(kind.label).font(.caption).foregroundStyle(.secondary)
              Text(player.rating(kind).map { String($0.rating) } ?? "—")
                .font(.title2.monospacedDigit().weight(.semibold))
              if let entry = player.rating(kind), let k = entry.kFactor {
                Text("K\(k) · \(entry.games ?? 0) partidas")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  private var historySection: some View {
    Section {
      Picker("Ritmo", selection: $kind) {
        ForEach(RatingKind.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)

      if let history {
        let points = chartPoints(history)
        if points.isEmpty {
          Text("Sin historial para este ritmo").foregroundStyle(.secondary)
        } else {
          Chart(points, id: \.date) { point in
            LineMark(x: .value("Mes", point.date), y: .value("Rating", point.rating))
              .interpolationMethod(.stepEnd)
            AreaMark(
              x: .value("Mes", point.date),
              yStart: .value("Mín", (points.map(\.rating).min() ?? 0) - 20),
              yEnd: .value("Rating", point.rating)
            )
            .interpolationMethod(.stepEnd)
            .foregroundStyle(.tint.opacity(0.12))
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartYAxis {
            AxisMarks(position: .trailing) { value in
              AxisGridLine()
              AxisValueLabel {
                if let rating = value.as(Int.self) { Text(verbatim: String(rating)) }
              }
            }
          }
          .frame(height: 200)
          .padding(.vertical, 6)

          Picker("Rango", selection: $range) {
            ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
        }
      } else if let historyError {
        Text(historyError.message).foregroundStyle(.secondary)
      } else {
        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
      }
    } header: {
      Text("Evolución")
    } footer: {
      if history != nil {
        Text(
          historyDensity == .dense
            ? "Historial mensual completo."
            : "Lichess solo envía los meses con cambios; se rellenan hacia delante."
        )
      }
    }
  }

  private var trackingSection: some View {
    Section {
      if let tracked {
        LabeledContent(
          "Siguiendo desde", value: tracked.addedAt.formatted(date: .abbreviated, time: .omitted))
        LabeledContent("Datos de la lista", value: tracked.dataListMonth ?? "—")
        if let refreshed = tracked.lastRefreshedAt {
          LabeledContent("Actualizado") {
            Text(refreshed, format: .relative(presentation: .named))
          }
        }
        TextField("Nota", text: $note, axis: .vertical)
          .onSubmit {
            Task { try? await model.client.setNote(note.isEmpty ? nil : note, for: player.id) }
          }
        Button("Dejar de seguir", systemImage: "star.slash", role: .destructive) {
          Task { await perform { try await model.client.untrack(id: player.id) } }
        }
      } else {
        Button {
          Task { await perform { try await model.client.track(id: player.id) } }
        } label: {
          Label("Seguir jugador", systemImage: "star")
        }
        .disabled(isWorking)
      }
    } header: {
      Text("Seguimiento")
    } footer: {
      Text(
        "Los jugadores seguidos se guardan en local y se actualizan solo cuando FIDE publica una lista nueva."
      )
    }
  }

  private var snapshotsSection: some View {
    Section("Snapshots guardados") {
      ForEach(snapshots.reversed()) { snapshot in
        HStack {
          Text(snapshot.listMonth).monospacedDigit()
          Spacer()
          Text(
            [snapshot.standard, snapshot.rapid, snapshot.blitz]
              .map { $0.map(String.init) ?? "—" }
              .joined(separator: " · ")
          )
          .monospacedDigit()
          .foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: Loading

  private func load() async {
    let id = player.id
    _ = try? await $trackedRows.load(TrackedPlayerRecord.where { $0.id.eq(id) })
    _ = try? await $snapshots.load(
      RatingSnapshotRecord.where { $0.playerID.eq(id) }.order { $0.listMonth })
    note = tracked?.note ?? ""
    async let fresh = try? model.client.player(id: id)
    do {
      let raw = try await model.client.ratingHistory(id: id)
      historyDensity = raw.density
      history = raw.filledForward()
    } catch {
      historyError = error
    }
    if let fresh = await fresh { player = fresh }
  }

  private func perform(_ action: () async throws -> Void) async {
    isWorking = true
    defer { isWorking = false }
    do { try await action() } catch { actionError = FideError.describe(error) }
  }

  // MARK: Chart data

  private struct ChartPoint {
    let date: Date
    let rating: Int
  }

  private func chartPoints(_ history: RatingHistory) -> [ChartPoint] {
    let points = history.points.compactMap { point -> ChartPoint? in
      guard let rating = point.rating(kind)?.rating else { return nil }
      return ChartPoint(date: point.month.startDate, rating: rating)
    }
    guard let months = range.months, let last = points.last?.date else { return points }
    let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: last) ?? last
    return points.filter { $0.date >= cutoff }
  }
}

enum HistoryRange: CaseIterable {
  case oneYear, fiveYears, all

  var months: Int? {
    switch self {
    case .oneYear: 12
    case .fiveYears: 60
    case .all: nil
    }
  }

  var label: String {
    switch self {
    case .oneYear: "1 año"
    case .fiveYears: "5 años"
    case .all: "Todo"
    }
  }
}
