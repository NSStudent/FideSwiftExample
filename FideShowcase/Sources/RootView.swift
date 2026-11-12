import SwiftUI

struct RootView: View {
  enum TabID: Hashable {
    case search, tracked, list, status
  }

  @State private var selection = TabID.search

  var body: some View {
    TabView(selection: $selection) {
      Tab("Buscar", systemImage: "magnifyingglass", value: .search) {
        NavigationStack { SearchView() }
      }
      Tab("Seguidos", systemImage: "star", value: .tracked) {
        NavigationStack { TrackedView() }
      }
      Tab("Lista", systemImage: "arrow.down.circle", value: .list) {
        NavigationStack { OfflineListView() }
      }
      Tab("Estado", systemImage: "waveform.path.ecg", value: .status) {
        NavigationStack { StatusView() }
      }
    }
  }
}
