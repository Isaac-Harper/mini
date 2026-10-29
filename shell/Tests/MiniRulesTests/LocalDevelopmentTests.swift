import Testing
import MiniRules

struct LocalDevelopmentTests {
    @Test func localHostsAreLoopbackAndLocalhostNames() {
        for host in ["localhost", "LOCALHOST", "app.localhost", "127.0.0.1", "127.0.1.1", "::1", "[::1]"] {
            #expect(LocalDevelopment.isLocalHost(host), "\(host)")
        }
        for host in ["example.com", "localhost.example.com", "128.0.0.1", "10.0.0.5", "127.0.0", "mylocalhost"] {
            #expect(!LocalDevelopment.isLocalHost(host), "\(host)")
        }
    }

    @Test func portsComeFromLocalAddressesOnly() {
        #expect(LocalDevelopment.port(ofLocalAddress: "http://localhost:3000/dashboard") == 3000)
        #expect(LocalDevelopment.port(ofLocalAddress: "http://127.0.0.1/") == 80)
        #expect(LocalDevelopment.port(ofLocalAddress: "https://app.localhost") == 443)
        #expect(LocalDevelopment.port(ofLocalAddress: "http://[::1]:5173/") == 5173)
        #expect(LocalDevelopment.port(ofLocalAddress: "https://vercel.com:3000") == nil)
        #expect(LocalDevelopment.port(ofLocalAddress: "file:///tmp/a.html") == nil)
        #expect(LocalDevelopment.port(ofLocalAddress: "") == nil)
    }

    @Test func lsofFieldOutputBecomesLoopbackListenersByPort() {
        let output = """
        p4012
        cnext-server
        f23
        n*:3000
        f24
        n[::1]:3000
        p5120
        cnode
        f19
        n127.0.0.1:5173
        p77
        cControlCenter
        f9
        n192.168.1.20:7000
        p88
        cpython3.12
        f3
        n[::]:8000
        """
        #expect(LocalDevelopment.listeners(fromLsofFields: output) == [
            LocalListener(processIdentifier: 4012, command: "next-server", port: 3000),
            LocalListener(processIdentifier: 5120, command: "node", port: 5173),
            LocalListener(processIdentifier: 88, command: "python3.12", port: 8000),
        ])
    }

    @Test func malformedLsofLinesAreSkipped() {
        #expect(LocalDevelopment.listeners(fromLsofFields: "") == [])
        #expect(LocalDevelopment.listeners(fromLsofFields: "n*:3000\npabc\ncx\nn*:99999\nn*:http") == [])
    }

    @Test func colonPortsAlwaysOpenAndBarePortsOnlyWhenListening() {
        #expect(LocalDevelopment.portShortcut(":3000", listeningPorts: []) == 3000)
        #expect(LocalDevelopment.portShortcut(" :8080 ", listeningPorts: []) == 8080)
        #expect(LocalDevelopment.portShortcut("3000", listeningPorts: [3000]) == 3000)
        #expect(LocalDevelopment.portShortcut("2024", listeningPorts: [3000]) == nil)
        #expect(LocalDevelopment.portShortcut(":0", listeningPorts: []) == nil)
        #expect(LocalDevelopment.portShortcut(":70000", listeningPorts: []) == nil)
        #expect(LocalDevelopment.portShortcut(":30a", listeningPorts: []) == nil)
        #expect(LocalDevelopment.portShortcut("next", listeningPorts: [3000]) == nil)
    }

    @Test func retriesBackOffAndStayWithinTheBudget() {
        let delays = LocalDevelopment.retryDelays(totalSeconds: 60)
        #expect(Array(delays.prefix(6)) == [0.25, 0.5, 1, 2, 4, 4])
        #expect(delays.reduce(0, +) <= 60)
        #expect(delays.reduce(0, +) > 55)
        #expect(LocalDevelopment.retryDelays(totalSeconds: 0.1) == [])
    }
}
