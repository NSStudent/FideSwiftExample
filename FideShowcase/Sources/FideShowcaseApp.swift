@preconcurrency import BackgroundTasks
import FideSDK
import SQLiteData
import SwiftUI

@main
struct FideShowcaseApp: App {
  @State private var model: ShowcaseModel
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let model = ShowcaseModel.live()
    _model = State(initialValue: model)
    // `@FetchAll` / `@FetchOne` in views observe the SDK's user database.
    prepareDependencies { $0.defaultDatabase = model.client.userDatabase }
    BackgroundRefresh.register(client: model.client)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .task { await model.observeEvents() }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // Cheap when nothing changed: one throttled HEAD request to FIDE.
        Task { await model.runScheduledUpdate() }
      case .background:
        BackgroundRefresh.schedule()
      default:
        break
      }
    }
  }
}

/// `BGAppRefreshTask` integration: the same entry point as on foreground, without the
/// ~45 MB list download (too heavy for a background slot).
enum BackgroundRefresh {
  static let identifier = "dev.fideswiftsdk.showcase.refresh"

  static func register(client: FideClient) {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      let work = Task {
        _ = try? await client.performScheduledUpdate(UpdateOptions(allowListDownload: false))
        task.setTaskCompleted(success: !Task.isCancelled)
      }
      task.expirationHandler = { work.cancel() }
      schedule()
    }
  }

  static func schedule() {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = .now.addingTimeInterval(12 * 3600)
    try? BGTaskScheduler.shared.submit(request)
  }
}
