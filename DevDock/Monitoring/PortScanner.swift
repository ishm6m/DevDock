import Darwin
import Foundation

/// A single listening socket discovered by the port scan: a PID bound to a port.
struct PortScanRecord: Hashable {
    let pid: Int32
    let command: String
    let port: Int
    let address: String
}

/// Discovers listening TCP sockets directly through `libproc` — no subprocess.
///
/// **Why not `lsof`?** DevDock used to shell out to `/usr/sbin/lsof` once per refresh.
/// It works, but it costs a fork + exec + pipe drain. Measured on this machine, same
/// result set (10 listeners):
///
/// | approach | median wall | min | max | CPU per call |
/// |---|---|---|---|---|
/// | `libproc` (this) | **1.3 ms** | 1.3 | 1.3 | ~1 ms |
/// | `lsof -nP +c 0 -iTCP -sTCP:LISTEN -Fpcn` | 95.7 ms | 90.0 | 97.8 | ~10 ms |
///
/// Be precise about what this buys: the ~70x is **wall-clock latency**, most of it
/// fork/exec/dyld rather than computation — `lsof` only burns ~10 ms of actual CPU, so
/// this is not the large energy win the wall figures suggest. What it does buy is real:
/// the refresh no longer blocks ~96 ms (which is what makes the 1 s panel-open cadence
/// affordable), and it removes a process spawn per pass — spawns cost page faults,
/// dyld work, and scheduler wake-ups that a CPU-time measurement does not capture.
///
/// There is no coverage loss: `proc_pidfdinfo` returns socket
/// details only for processes the caller may inspect (same uid, or root), and
/// unprivileged `lsof` is subject to exactly the same restriction. Processes owned by
/// other users were never visible, and DevDock would refuse to signal them anyway.
///
/// The remaining alternatives were rejected: `netstat` is another subprocess and does
/// not report PIDs; `NSNetServiceBrowser`/Bonjour only sees advertised services, not
/// arbitrary bound ports; and there is no public notification for "a socket was bound",
/// so polling — cheaply — is the only option.
final class PortScanner: @unchecked Sendable {

    /// `proc_pidinfo` / socket flavors, declared with raw values so we don't depend on
    /// the C macros being imported into Swift (matching `Proc`).
    private static let PID_LIST_FDS: Int32 = 1        // PROC_PIDLISTFDS
    private static let FD_SOCKETINFO: Int32 = 3       // PROC_PIDFDSOCKETINFO
    private static let FDTYPE_SOCKET: UInt32 = 2      // PROX_FDTYPE_SOCKET
    private static let SOCK_KIND_TCP: Int32 = 2       // SOCKINFO_TCP
    private static let TCP_LISTEN: Int32 = 1          // TSI_S_LISTEN
    private static let IPV4_FLAG: UInt8 = 0x1         // INI_IPV4
    private static let IPV6_FLAG: UInt8 = 0x2         // INI_IPV6

    func scan() async -> [PortScanRecord] {
        var records: [PortScanRecord] = []
        for pid in Proc.allPIDs() {
            let sockets = Self.listeningSockets(pid: pid)
            guard !sockets.isEmpty else { continue }
            // Resolve the name only for processes that actually listen — a handful,
            // not the several hundred PIDs on a typical system.
            let command = Proc.name(pid) ?? ""
            for socket in sockets {
                records.append(PortScanRecord(pid: pid, command: command, port: socket.port, address: socket.address))
            }
        }
        return records
    }

    /// The listening TCP sockets held by one process. Returns empty for processes we
    /// may not inspect, which is the common case for other users' daemons.
    private static func listeningSockets(pid: Int32) -> [(port: Int, address: String)] {
        let bufferSize = proc_pidinfo(pid, PID_LIST_FDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / stride)
        let written = proc_pidinfo(pid, PID_LIST_FDS, 0, &descriptors, bufferSize)
        guard written > 0 else { return [] }

        var result: [(port: Int, address: String)] = []
        for descriptor in descriptors.prefix(Int(written) / stride)
        where descriptor.proc_fdtype == FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, FD_SOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == SOCK_KIND_TCP else { continue }

            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TCP_LISTEN else { continue }

            // Ports come back in network byte order in the low 16 bits.
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
            guard port > 0 else { continue }
            result.append((port, address(of: tcp.tcpsi_ini)))
        }
        return result
    }

    /// Formats a bound local address using the same vocabulary the rest of discovery
    /// expects: `*` / `0.0.0.0` / `[::]` for a wildcard bind, otherwise the literal.
    private static func address(of socket: in_sockinfo) -> String {
        var socket = socket
        if socket.insi_vflag & IPV4_FLAG != 0 {
            let raw = socket.insi_laddr.ina_46.i46a_addr4.s_addr
            if raw == 0 { return "*" }
            var address = in_addr(s_addr: raw)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return "*" }
            return String(cString: buffer)
        }
        if socket.insi_vflag & IPV6_FLAG != 0 {
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let text: String? = withUnsafePointer(to: &socket.insi_laddr.ina_6) { pointer in
                inet_ntop(AF_INET6, pointer, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil
                    ? String(cString: buffer) : nil
            }
            guard let text else { return "*" }
            return text == "::" ? "[::]" : "[\(text)]"
        }
        return "*"
    }
}
