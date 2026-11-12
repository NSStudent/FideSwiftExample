import FideSDK
import SwiftUI

struct OfflineListView: View {
  enum Scope: String, CaseIterable {
    case rated, all, federation

    var label: String {
      switch self {
      case .rated: "Con rating"
      case .all: "Todos"
      case .federation: "Federación"
      }
    }
  }

  @Environment(ShowcaseModel.self) private var model
  @State private var scope = Scope.rated
  @State private var federation = "ESP"
  @State private var activeOnly = false
  @AppStorage(ShowcaseModel.Settings.allowCellular) private var allowCellular = false
  @State private var confirmsRemoval = false

  var body: some View {
    Form {
      installedSection
      importSection
      if model.isSyncing || model.syncProgress != nil || model.syncError != nil {
        progressSection
      }
      Section {
        Text(
          "Sin lista, las búsquedas van a Lichess (máximo 30 resultados, sin filtros). Con ella, se busca en local con FTS5 en milisegundos, también sin conexión, y los jugadores seguidos se actualizan sin peticiones de red."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      } header: {
        Text("¿Para qué sirve?")
      }
    }
    .navigationTitle("Lista oficial")
    .confirmationDialog(
      "¿Eliminar la lista offline?", isPresented: $confirmsRemoval, titleVisibility: .visible
    ) {
      Button("Eliminar", role: .destructive) { Task { await model.removeList() } }
    } message: {
      Text("Los jugadores seguidos no se borran. Puedes volver a descargarla cuando quieras.")
    }
  }

  @ViewBuilder
  private var installedSection: some View {
    Section("Instalada") {
      if let info = model.listInfo {
        LabeledContent("Lista", value: info.listMonth ?? "—")
        LabeledContent("Jugadores", value: info.playerCount.formatted())
        LabeledContent("Importada") {
          Text(info.importedAt, format: .relative(presentation: .named))
        }
        if let size = fileSize(model.client.listStore.fileURL) {
          LabeledContent("Tamaño", value: size)
        }
        Button("Eliminar lista", systemImage: "trash", role: .destructive) {
          confirmsRemoval = true
        }
        .disabled(model.isSyncing)
      } else {
        Label("No descargada", systemImage: "icloud.slash")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var importSection: some View {
    Section {
      Picker("Jugadores", selection: $scope) {
        ForEach(Scope.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)
      if scope == .federation {
        TextField("Federaciones (ESP, FRA…)", text: $federation)
          .textInputAutocapitalization(.characters)
      }
      Toggle("Solo activos", isOn: $activeOnly)
      Toggle("Permitir datos móviles", isOn: $allowCellular)
      Button {
        model.startListSync(filter: filter, force: false, allowCellular: allowCellular)
      } label: {
        Label(
          model.listInfo == nil ? "Descargar e importar" : "Buscar actualización",
          systemImage: "arrow.down.circle")
      }
      .disabled(model.isSyncing)
      if model.listInfo != nil {
        Button("Forzar reimportación", systemImage: "arrow.triangle.2.circlepath") {
          model.startListSync(filter: filter, force: true, allowCellular: allowCellular)
        }
        .disabled(model.isSyncing)
      }
    } header: {
      Text("Importar")
    } footer: {
      Text(
        "Unos 45 MB de descarga. «Con rating» guarda ~800.000 jugadores (~86 MB). Por defecto solo por Wi-Fi. Si la lista ya está al día, FIDE responde 304 y no se descarga nada."
      )
    }
  }

  @ViewBuilder
  private var progressSection: some View {
    Section("Progreso") {
      if let progress = model.syncProgress {
        switch progress {
        case .checking:
          Label("Comprobando con FIDE…", systemImage: "network")
        case .upToDate:
          Label("La lista ya está al día (304)", systemImage: "checkmark.circle")
            .foregroundStyle(.green)
        case .downloading(let received, let expected):
          if let expected {
            ProgressView(value: Double(received), total: Double(expected)) {
              Text("Descargando")
            } currentValueLabel: {
              Text(
                "\(received.formatted(.byteCount(style: .file))) de \(expected.formatted(.byteCount(style: .file)))"
              )
            }
          } else {
            ProgressView("Descargando \(received.formatted(.byteCount(style: .file)))")
          }
        case .importing(let fraction):
          ProgressView(value: fraction) {
            Text("Importando")
          } currentValueLabel: {
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
          }
        case .indexing:
          ProgressView("Construyendo índice de búsqueda…")
        case .finished(let count, let month):
          Label(
            "\(count.formatted()) jugadores · lista \(month?.description ?? "—")",
            systemImage: "checkmark.circle.fill"
          )
          .foregroundStyle(.green)
        }
      }
      if let error = model.syncError {
        Label(error.message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
        if !allowCellular {
          Text("Si estás con datos móviles, activa «Permitir datos móviles».")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if model.isSyncing {
        Button("Cancelar", role: .cancel) { model.cancelListSync() }
      }
    }
  }

  private var filter: ImportFilter {
    switch scope {
    case .rated:
      ImportFilter(ratedOnly: true, activeOnly: activeOnly)
    case .all:
      ImportFilter(ratedOnly: false, activeOnly: activeOnly)
    case .federation:
      ImportFilter(
        ratedOnly: false,
        federations: Set(
          federation.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)),
        activeOnly: activeOnly)
    }
  }

  private func fileSize(_ url: URL) -> String? {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
    return Int64(size).formatted(.byteCount(style: .file))
  }
}
