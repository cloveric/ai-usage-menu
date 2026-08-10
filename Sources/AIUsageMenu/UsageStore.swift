import AIUsageCore
import Combine
import Foundation
import OSLog

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var snapshot: DashboardSnapshot
    @Published private(set) var isRefreshing = false
    @Published var showsDetails = false

    private let service: UsageService
    private let usesFixture: Bool
    private var refreshLoop: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.cloveric.ai-usage-menu", category: "cache")

    private init(service: UsageService = UsageService()) {
        self.service = service
        self.usesFixture = ProcessInfo.processInfo.arguments.contains("--fixture")
        if self.usesFixture {
            self.snapshot = .designFixture()
        } else {
            self.snapshot = UsageCache.load() ?? .empty
            Task { @MainActor [weak self] in
                self?.startAutoRefresh()
            }
        }
    }

    var menuBarTitle: String {
        self.snapshot.averageRemainingPercent.map { "AI \($0)%" } ?? "AI --"
    }

    func startAutoRefresh() {
        guard !self.usesFixture, self.refreshLoop == nil else { return }
        self.refreshLoop = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15 * 60))
                } catch {
                    return
                }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !self.isRefreshing, !self.usesFixture else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }
        let refreshed = await self.service.fetchAll(previous: self.snapshot)
        self.snapshot = refreshed
        do {
            try UsageCache.save(refreshed)
        } catch {
            self.logger.error("保存用量缓存失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
