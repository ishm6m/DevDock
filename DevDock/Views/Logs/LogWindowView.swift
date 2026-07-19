import SwiftUI

/// A live, searchable, auto-scrolling log window for a server DevDock launched.
struct LogWindowView: View {
    @StateObject private var viewModel: LogViewModel

    init(viewModel: LogViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if viewModel.isAvailable {
                logList
            } else {
                unavailableState
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle(viewModel.title)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft").foregroundStyle(.secondary)
            TextField("Filter log lines…", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Spacer()
            Toggle(isOn: $viewModel.autoScroll) {
                Label("Auto-scroll", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(10)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(viewModel.lines) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.isError ? .red : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: viewModel.lines.count) { _, _ in
                guard viewModel.autoScroll else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.doc").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Logs unavailable").font(.headline)
            Text("macOS can't read the output of a process it didn't start. Restart this server from DevDock to capture its logs live.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let bottomAnchor = "devdock.logs.bottom"
}
