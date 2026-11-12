import FideSDK
import SwiftUI

@MainActor
@Observable
final class SearchModel {
  struct Key: Hashable {
    var source: SearchSource
    var federation: String
    var title: FideTitle?
    var activeOnly: Bool
  }

  var text = "" {
    didSet { continuation?.yield(text) }
  }
  var source: SearchSource = .auto
  var federation = ""
  var title: FideTitle?
  var activeOnly = false
  private(set) var state: SearchState = .idle
  private var continuation: AsyncStream<String>.Continuation?

  var key: Key { Key(source: source, federation: federation, title: title, activeOnly: activeOnly) }

  /// Feeds the text field into the SDK's debounced, cancelling search stream.
  func run(client: FideClient) async {
    let (queries, continuation) = AsyncStream<String>.makeStream()
    self.continuation = continuation
    defer { continuation.finish() }
    continuation.yield(text)
    let filter = LocalSearchFilter(
      federation: federation.isEmpty ? nil : federation, title: title, activeOnly: activeOnly,
      limit: 200)
    for await state in client.searchStream(queries, source: source, filter: filter) {
      self.state = state
    }
  }
}

struct SearchView: View {
  @Environment(ShowcaseModel.self) private var model
  @State private var search = SearchModel()
  @State private var showsFilters = false

  var body: some View {
    @Bindable var search = search
    List {
      switch search.state {
      case .idle:
        idleContent
      case .searching(let query):
        HStack(spacing: 10) {
          ProgressView()
          Text("Buscando «\(query)»…").foregroundStyle(.secondary)
        }
      case .results(let results):
        resultsContent(results)
      case .failed(_, let error):
        ContentUnavailableView(
          "No se pudo buscar", systemImage: "wifi.exclamationmark",
          description: Text(error.message))
      }
    }
    .navigationTitle("Jugadores FIDE")
    .searchable(
      text: $search.text, placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Nombre o FIDE ID"
    )
    .autocorrectionDisabled()
    .textInputAutocapitalization(.never)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Filtros", systemImage: "line.3.horizontal.decrease.circle") {
          showsFilters = true
        }
        .symbolVariant(search.key == SearchModel().key ? .none : .fill)
      }
    }
    .sheet(isPresented: $showsFilters) {
      SearchFiltersSheet(search: search, hasList: model.listInfo != nil)
        .presentationDetents([.medium, .large])
    }
    .navigationDestination(for: FidePlayer.self) { PlayerDetailView(player: $0) }
    .task(id: search.key) { await search.run(client: model.client) }
  }

  @ViewBuilder
  private var idleContent: some View {
    Section {
      Text(
        "Escribe al menos 3 letras o un FIDE ID. Las búsquedas usan un debounce de 300 ms y cancelan las peticiones obsoletas."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    Section("Prueba con") {
      ForEach(["Carlsen", "1503014", "Sánchez", "Hou Yifan", "Shirov"], id: \.self) { example in
        Button(example) { search.text = example }
      }
    }
    Section {
      LabeledContent("Fuente actual") {
        Text(model.listInfo == nil ? "Lichess (online)" : "Lista local (FTS5)")
      }
    } footer: {
      Text(
        "Con la lista oficial descargada, «Automático» busca en local: sin límite de 30 resultados, con filtros y sin conexión."
      )
    }
  }

  @ViewBuilder
  private func resultsContent(_ results: SearchResults) -> some View {
    if results.players.isEmpty {
      ContentUnavailableView.search(text: results.query)
    } else {
      Section {
        ForEach(results.players) { player in
          NavigationLink(value: player) { PlayerRow(player: player) }
        }
      } header: {
        HStack {
          Text("\(results.players.count) resultados")
          Spacer()
          Label(
            results.source == .local ? "Local" : "Lichess",
            systemImage: results.source == .local ? "internaldrive" : "network")
        }
      } footer: {
        if results.isPossiblyTruncated {
          Label(
            results.source == .remote
              ? "Lichess devuelve como máximo 30 resultados: afina la búsqueda o descarga la lista oficial."
              : "Hay más coincidencias: afina la búsqueda.",
            systemImage: "exclamationmark.triangle")
        }
      }
    }
  }
}

struct SearchFiltersSheet: View {
  @Bindable var search: SearchModel
  let hasList: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Fuente", selection: $search.source) {
            Text("Automático").tag(SearchSource.auto)
            Text("Lichess").tag(SearchSource.remote)
            Text("Lista local").tag(SearchSource.local)
          }
          .pickerStyle(.segmented)
        } footer: {
          if !hasList {
            Text("La lista local no está descargada; «Lista local» fallará.")
          }
        }
        Section {
          TextField("Federación (p. ej. ESP)", text: $search.federation)
            .textInputAutocapitalization(.characters)
          Picker("Título", selection: $search.title) {
            Text("Cualquiera").tag(FideTitle?.none)
            ForEach(FideTitle.known, id: \.self) { title in
              Text(title.rawValue).tag(FideTitle?.some(title))
            }
          }
          Toggle("Solo activos", isOn: $search.activeOnly)
        } header: {
          Text("Filtros")
        } footer: {
          Text("Los filtros solo se aplican a la lista local; la API de Lichess no los admite.")
        }
      }
      .navigationTitle("Búsqueda")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
        ToolbarItem(placement: .cancellationAction) {
          Button("Restablecer") {
            search.source = .auto
            search.federation = ""
            search.title = nil
            search.activeOnly = false
          }
        }
      }
    }
  }
}
