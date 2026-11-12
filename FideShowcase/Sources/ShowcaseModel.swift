import FideSDK
import Foundation
import Observation

/// App-wide state shared by the tabs.
@MainActor
@Observable
final class ShowcaseModel {
  struct LoggedEvent: Identifiable {
    let id = UUID()
    let date: Date
    let event: FideEvent
  }

  let client: FideClient
  private(set) var events: [LoggedEvent] = []
  private(set) var lastReport: UpdateReport?
  private(set) var lastReportDate: Date?
  private(set) var isUpdating = false
  private(set) var updateError: FideError?
  private(set) var syncState: SyncStateRecord?
  private(set) var listInfo: ListMetaRecord?

  // Full-list sync
  private(set) var syncProgress: ListSyncProgress?
  private(set) var syncError: FideError?
  private(set) var isSyncing = false
  private var syncTask: Task<Void, Never>?

  init(client: FideClient) {
    self.client = client
  }

  static func live() -> ShowcaseModel {
    var configuration = FideClientConfiguration()
    configuration.userAgent = "FideShowcase/0.1 (FideSwiftSDK demo)"
    configuration.preferAuthoritativeImmediate = UserDefaults.standard.bool(
      forKey: Settings.immediateMode)
    do {
      return ShowcaseModel(client: try FideClient(configuration: configuration))
    } catch {
      // The on-disk store couldn't be opened: keep the demo usable in memory.
      configuration.storage = .inMemory
      return ShowcaseModel(client: try! FideClient(configuration: configuration))
    }
  }

  enum Settings {
    static let immediateMode = "immediateMode"
    static let allowCellular = "allowCellular"
  }

  // MARK: Events

  func observeEvents() async {
    await refreshStatus()
    for await event in client.events() {
      events.insert(LoggedEvent(date: .now, event: event), at: 0)
      if events.count > 200 { events.removeLast() }
      if case .listSync = event { continue }
      await refreshStatus()
    }
  }

  func refreshStatus() async {
    syncState = try? await client.userStore.syncState()
    listInfo = try? await client.fullListInfo()
  }

  // MARK: Updates

  func runScheduledUpdate(force: Bool = false) async {
    guard !isUpdating else { return }
    isUpdating = true
    defer { isUpdating = false }
    do {
      lastReport = try await client.performScheduledUpdate(UpdateOptions(force: force))
      lastReportDate = .now
      updateError = nil
    } catch {
      updateError = error
    }
    await refreshStatus()
  }

  // MARK: Full list

  func startListSync(filter: ImportFilter, force: Bool, allowCellular: Bool) {
    guard !isSyncing else { return }
    isSyncing = true
    syncError = nil
    syncProgress = .checking
    syncTask = Task {
      do {
        for try await progress in client.syncFullList(
          filter: filter, force: force, policy: allowCellular ? .any : .wifiOnly)
        {
          syncProgress = progress
        }
      } catch {
        syncError = FideError.describe(error)
      }
      isSyncing = false
      await refreshStatus()
    }
  }

  func cancelListSync() {
    syncTask?.cancel()
  }

  func removeList() async {
    try? await client.removeFullList()
    syncProgress = nil
    await refreshStatus()
  }
}

extension FideError {
  static func describe(_ error: any Error) -> FideError {
    if let error = error as? FideError { return error }
    if error is CancellationError { return .remote("Cancelado") }
    return .remote(error.localizedDescription)
  }

  var message: String {
    switch self {
    case .offline: "Sin conexión. Los jugadores seguidos siguen disponibles."
    case .rateLimited: "Lichess pide esperar un minuto (429)."
    case .playerNotFound(let id): "No existe ningún jugador con FIDE ID \(id)."
    case .listNotInstalled: "No hay lista offline. Descárgala en la pestaña Lista."
    case .listSyncInProgress: "Ya hay una sincronización en curso."
    case .remote(let text): text
    case .storage(let text): "Error de almacenamiento: \(text)"
    }
  }
}
