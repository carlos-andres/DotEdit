import Foundation
import Testing
@testable import DotEdit

@Suite("VolumeMonitor (BL-010)")
struct VolumeMonitorTests {

    // MARK: - Helpers

    private func writeTempFile(_ content: String = "A=1") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotedit-voltest-\(UUID().uuidString).env")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Local File Accessible

    @Test("Local file reports accessible")
    @MainActor
    func localFileAccessible() throws {
        let url = try writeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let monitor = VolumeMonitor(checkInterval: 60)
        monitor.monitor(url: url)

        #expect(monitor.isAccessible(url: url) == true)
    }

    // MARK: - Deleted File Inaccessible

    @Test("Deleted file triggers inaccessible callback")
    @MainActor
    func deletedFileTriggers() throws {
        let url = try writeTempFile()

        let monitor = VolumeMonitor(checkInterval: 60)
        monitor.monitor(url: url)

        var callbackURL: URL?
        var callbackAccessible: Bool?
        monitor.setHandler { url, accessible in
            callbackURL = url
            callbackAccessible = accessible
        }

        // Delete the file
        try FileManager.default.removeItem(at: url)

        // Force check
        monitor.checkAccessibility()

        #expect(callbackURL != nil)
        #expect(callbackAccessible == false)
        #expect(monitor.isAccessible(url: url) == false)
    }

    // MARK: - File Re-created → Accessible Again

    @Test("Re-created file triggers accessible callback")
    @MainActor
    func reCreatedFileTriggers() throws {
        let url = try writeTempFile()

        let monitor = VolumeMonitor(checkInterval: 60)
        monitor.monitor(url: url)

        var callbacks: [(URL, Bool)] = []
        monitor.setHandler { url, accessible in
            callbacks.append((url, accessible))
        }

        // Delete
        try FileManager.default.removeItem(at: url)
        monitor.checkAccessibility()

        // Re-create
        try "B=2".write(to: url, atomically: true, encoding: .utf8)
        monitor.checkAccessibility()

        defer { try? FileManager.default.removeItem(at: url) }

        #expect(callbacks.count == 2)
        #expect(callbacks[0].1 == false)
        #expect(callbacks[1].1 == true)
    }

    // MARK: - No Spurious Callbacks

    @Test("No callback when accessibility unchanged")
    @MainActor
    func noSpuriousCallbacks() throws {
        let url = try writeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let monitor = VolumeMonitor(checkInterval: 60)
        monitor.monitor(url: url)

        var callbackCount = 0
        monitor.setHandler { _, _ in
            callbackCount += 1
        }

        // Check multiple times — file hasn't changed
        monitor.checkAccessibility()
        monitor.checkAccessibility()
        monitor.checkAccessibility()

        #expect(callbackCount == 0)
    }

    // MARK: - ViewModel Accessibility State

    @Test("ViewModel accessibility state updates correctly")
    @MainActor
    func viewModelAccessibility() throws {
        let url = try writeTempFile("X=1")
        defer { try? FileManager.default.removeItem(at: url) }

        let file = EnvParser.parse(content: "X=1", filePath: url.resolvingSymlinksInPath().path)
        let vm = ComparisonViewModel(leftFile: file, rightFile: file)

        #expect(vm.isLeftAccessible == true)
        #expect(vm.isRightAccessible == true)

        vm.setAccessibility(url: url, isAccessible: false)

        #expect(vm.isLeftAccessible == false)
        #expect(vm.isRightAccessible == false)

        vm.setAccessibility(url: url, isAccessible: true)

        #expect(vm.isLeftAccessible == true)
        #expect(vm.isRightAccessible == true)
    }

    // MARK: - Unmonitor

    @Test("Unmonitored URL is not tracked")
    @MainActor
    func unmonitorRemovesURL() throws {
        let url = try writeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let monitor = VolumeMonitor(checkInterval: 60)
        monitor.monitor(url: url)
        monitor.unmonitor(url: url)

        var callbackCount = 0
        monitor.setHandler { _, _ in
            callbackCount += 1
        }

        try FileManager.default.removeItem(at: url)
        monitor.checkAccessibility()

        #expect(callbackCount == 0)
    }
}
