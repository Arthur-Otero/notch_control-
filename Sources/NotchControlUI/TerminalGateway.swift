import AppKit
import Darwin
import Combine
import NotchControlCore
import SwiftUI

public struct TerminalDescriptor: Decodable, Identifiable {
    public let identity: TerminalIdentity
    public let name: String
    public let provider: String?
    public let conversation: String?
    public let project: String
    public let columns: Int
    public let rows: Int
    public let singlePane: Bool
    public let local: Bool
    public let identityConfirmed: Bool
    public let fullscreen: Bool
    public var id: String { identity.id }
}

private struct ProofMessage: Decodable {
    let version: Int
    let type: String
    let connection: String?
    let terminals: [TerminalDescriptor]?
    let code: String?
    let requestID: String?
    let ambiguous: Bool?
    let restored: Bool?
    let reason: String?
    let docked: Bool?
    let createdTerminal: String?
    let baseline: Bool?
}

private struct ProofCommand: Encodable {
    let version = 1
    let type: String
    let requestID: String
    let connection: String?
    let terminal: TerminalIdentity?
    let selection: UInt64?
    let text: String?
    let suppressBroadcast: Bool?
    let columns: Int?
    let rows: Int?
    let resume: ResumeRequest?
    let before: Int?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
}

@MainActor
public final class TerminalGateway: ObservableObject {
    @Published public private(set) var terminals: [TerminalDescriptor] = []
    @Published public private(set) var accountUsage: [String: AccountUsageReading] = [:]
    @Published public private(set) var selectedID: String?
    @Published public private(set) var snapshot: TerminalSnapshot?
    @Published public private(set) var status = "Preparando integração…"
    @Published public private(set) var isRunning = false
    @Published public private(set) var connected = false
    /// When set, selecting a session moves that iTerm2 window onto the panel instead of copying its cells.
    public var embedOnSelect = false
    public var embedFrame = NSRect.zero
    @Published public private(set) var docked = false
    @Published public private(set) var dockFailed = false
    public var onEvidence: ((AgentEvidence, Bool) -> Void)?
    public var onResume: ((String?, Bool) -> Void)?
    @Published public private(set) var history: [TerminalLine] = []
    @Published public private(set) var historyRevision: UInt64 = 0
    @Published public private(set) var historyHasMore = false
    public var onHistory: (() -> Void)?
    private var historyFirstLine: Int?
    @Published public private(set) var statusCode = "starting"
    private let project: URL
    private let privateSocket: Bool
    private var socketFolder: URL?
    private var session = SessionControl()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var polling: Timer?
    private var requests: [String: String] = [:]
    private var shutdownCompletion: (() -> Void)?
    private var runID: UUID?
    private let writes = DispatchQueue(label: "NotchControl.proof.input")

    public init(project: URL, privateSocket: Bool = false) { self.project = project; self.privateSocket = privateSocket }

    public var selected: TerminalDescriptor? { terminals.first { $0.id == selectedID } }
    public var canSend: Bool {
        connected && snapshot != nil && selected?.identityConfirmed == true && selected?.local == true
    }

    public func start() {
        guard !isRunning else { return }
        session.disconnect()
        selectedID = nil
        snapshot = nil
        buffer.removeAll()
        let runID = UUID()
        self.runID = runID
        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let python = ProcessInfo.processInfo.environment["NOTCH_CONTROL_PYTHON"] ??
            project.appendingPathComponent(".venv/bin/python3").path
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = [project.appendingPathComponent("helper/proof_bridge.py").path, "--serve"]
        if privateSocket {
            let folder = URL(fileURLWithPath: "/private/tmp/nc-" + String(getuid()) + "-" + UUID().uuidString)
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
            catch { statusCode = "local_transport_unavailable"; return }
            socketFolder = folder
            child.arguments! += ["--socket", folder.appendingPathComponent("bridge").path]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["NOTCH_CONTROL_EVENT_DIR"] = project.appendingPathComponent(".notchcontrol/events").path
        child.environment = environment
        child.currentDirectoryURL = project
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.runID == runID else { return }
                self?.disconnected()
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                guard self?.runID == runID else { return }
                self?.receive(data)
            }
        }
        do {
            try child.run()
            process = child
            input = stdinPipe.fileHandleForWriting
            output = stdoutPipe.fileHandleForReading
            isRunning = true
            statusCode = "connecting"
            status = "Conectando ao iTerm2. Autorize o script se ele solicitar."
        } catch {
            self.runID = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            statusCode = "python_unavailable"
            status = "Python indisponível. Execute scripts/run-proof.sh no iTerm2 para preparar o ambiente."
            record("python_unavailable")
        }
    }

    /// Estado de um terminal já selecionado, para testes de apresentação sem ponte nem iTerm2.
    func installFixture(terminal: TerminalDescriptor, snapshot: TerminalSnapshot, history: [TerminalLine] = []) {
        terminals = [terminal]; selectedID = terminal.id
        self.snapshot = snapshot; self.history = history
        connected = true; statusCode = "ready"
    }

    public func refresh() { send("inventory") }
    public func loadOlderHistory() {
        guard historyHasMore, let before = historyFirstLine, let target = try? session.prepareInput("") else { return }
        send("history", target: target, before: before)
    }
    public func loadHistory() {
        guard let target = try? session.prepareInput("") else { return }
        send("history", target: target)
    }
    public func resume(_ request: ResumeRequest) {
        guard connected else { onResume?(nil, false); return }
        send("resume", resume: request)
    }

    public func select(_ terminal: TerminalDescriptor) {
        guard connected, terminal.identityConfirmed, terminal.local else {
            status = "Identidade local ainda não comprovada; entrada desabilitada."
            return
        }
        do {
            try session.select(terminal.id)
            selectedID = terminal.id
            snapshot = nil
            history = []; historyFirstLine = nil; historyHasMore = false
            send("select", target: try session.prepareInput(""))
            status = "Carregando tela…"
        } catch { status = "Atualize o inventário antes de selecionar." }
    }

    public func closeMirror() {
        if let target = try? session.prepareInput("") { send("unselect", target: target) }
        session.deselect()
        selectedID = nil
        snapshot = nil
        history = []
        historyHasMore = false
        historyFirstLine = nil
        statusCode = "closed"
        status = "Espelho fechado. O terminal original continua aberto."
    }

    public func sendText(_ text: String) {
        guard canSend, !text.isEmpty, text.utf8.count <= 1024 * 1024 else { return }
        do {
            let target = try session.prepareInput(text)
            try session.validate(target)
            send("input", target: target)
        } catch { status = "Destino alterado. Entrada cancelada; selecione novamente." }
    }

    public func resize(columns: Int, rows: Int) {
        guard let target = try? session.prepareInput("") else { return }
        send("resize", target: target, columns: columns, rows: rows)
    }

    public func restore() {
        guard let target = try? session.prepareInput("") else { return }
        send("restore", target: target)
    }

    public func shutdown(completion: @escaping () -> Void) {
        polling?.invalidate()
        // No helper (iTerm2 never connected): nobody answers `shutdown`, so waiting out the timeout only delays quitting.
        guard process != nil else { completion(); return }
        shutdownCompletion = completion
        send("shutdown")
        if let input { writes.async { try? input.close() } }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.shutdownCompletion != nil else { return }
            self.process?.terminate()
            self.record("helper_shutdown_timeout")
            self.disconnected()
        }
    }

    private func disconnected() {
        runID = nil
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        process = nil
        if let socketFolder { try? FileManager.default.removeItem(at: socketFolder) }
        socketFolder = nil
        polling?.invalidate()
        polling = nil
        session.disconnect()
        selectedID = nil
        snapshot = nil
        // `connected` cai antes de esvaziar a lista: quem observa `terminals` ignora lista vazia sem conexão e
        // não apaga o registro (números, apelidos, ordem) quando o app é encerrado.
        connected = false
        docked = false
        terminals = []
        accountUsage = [:]
        history = []
        historyHasMore = false
        historyFirstLine = nil
        statusCode = "disconnected"
        isRunning = false
        requests.removeAll()
        if status.hasPrefix("Conectando") || status == "Tela conectada. Estado do agente: desconhecido." {
            status = "Helper desconectado. Entrada desabilitada. Verifique a integração."
        }
        let completion = shutdownCompletion
        shutdownCompletion = nil
        completion?()
    }

    public func place(_ rect: NSRect) {
        guard docked, rect.width >= 80, rect.height >= 80 else { return }
        send("place", frame: rect)
    }

    public func focusEmbedded() {
        guard docked else { return }
        send("focus")
    }

    /// Bring the real iTerm2 session forward. Does not open a mirror or move the session.
    public func reveal(_ terminal: TerminalDescriptor) {
        guard connected, terminal.identityConfirmed, terminal.local else { return }
        send("reveal", terminal: terminal.identity)
    }

    private func send(_ type: String, target: TerminalInput? = nil, columns: Int? = nil, rows: Int? = nil, resume: ResumeRequest? = nil, before: Int? = nil, frame: NSRect? = nil, terminal: TerminalIdentity? = nil) {
        guard let input else { return }
        let id = UUID().uuidString
        let command = ProofCommand(type: type, requestID: id,
                                   connection: target?.connection ?? session.connection, terminal: terminal ?? target?.terminal,
                                   selection: target?.selection, text: type == "input" ? target?.text : nil,
                                   suppressBroadcast: type == "input" ? true : nil, columns: columns, rows: rows, resume: resume, before: before,
                                   frameX: frame.map { Double($0.origin.x) }, frameY: frame.map { Double($0.origin.y) },
                                   frameWidth: frame.map { Double($0.width) }, frameHeight: frame.map { Double($0.height) })
        guard var data = try? JSONEncoder().encode(command) else { return }
        data.append(0x0a)
        requests[id] = type
        let message = data
        let runID = self.runID
        writes.async { [weak self] in
            do { try input.write(contentsOf: message) }
            catch {
                Task { @MainActor in
                    guard self?.runID == runID else { return }
                    self?.status = "Falha no envio. A operação não será repetida automaticamente."
                    self?.snapshot = nil
                    self?.record("bridge_write_failed")
                }
            }
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 32 * 1024 * 1024 else {
            buffer.removeAll()
            snapshot = nil
            status = "Mensagem da ponte excedeu o limite. Entrada desabilitada."
            record("message_too_large")
            return
        }
        while let end = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            consume(line)
        }
    }

    private func consume(_ data: Data) {
        guard let message = try? JSONDecoder().decode(ProofMessage.self, from: data), message.version == 1 else {
            snapshot = nil
            status = "Protocolo da ponte incompatível. Entrada desabilitada."
            record("protocol_incompatible")
            return
        }
        let operation = message.requestID.flatMap { requests.removeValue(forKey: $0) }
        switch message.type {
        case "usage":
            guard let reading = try? JSONDecoder().decode(AccountUsageReading.self, from: data),
                  reading.isValid, reading.connection == session.connection,
                  terminals.contains(where: { $0.identity == reading.terminal && $0.local && $0.identityConfirmed }) else { return }
            accountUsage[reading.terminal.id] = reading
        case "socket_ready":
            connectLocalSocket()
        case "evidence":
            guard message.connection == session.connection else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let value = try decoder.singleValueContainer().decode(String.self)
                let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = format.date(from: value) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid timestamp")) }
                return date
            }
            if let evidence = try? decoder.decode(AgentEvidence.self, from: data) { onEvidence?(evidence, message.baseline == true) }
        case "history":
            if let value = try? JSONDecoder().decode(TerminalHistory.self, from: data),
               let target = try? session.prepareInput(""), value.connection == target.connection,
               value.terminal == target.terminal, value.selection == target.selection, value.lines.count <= 500,
               value.lines.allSatisfy({ $0.cells.count <= 1000 }) {
                history = value.lines; historyHasMore = value.hasMore; historyFirstLine = value.firstLine; historyRevision &+= 1; onHistory?()
            }
        case "connected":
            statusCode = "connected"
            connected = true
            refresh()
            polling = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            record("bridge_connected")
        case "inventory":
            guard let connection = message.connection, let terminals = message.terminals else { return }
            session.reconcile(connection: connection, terminals: terminals.map(\.identity))
            self.terminals = terminals
            accountUsage = accountUsage.filter { _, reading in terminals.contains { $0.identity == reading.terminal } }
            if session.selected?.id != selectedID {
                selectedID = nil
                snapshot = nil
            }
            if selectedID == nil { status = "\(terminals.count) terminais encontrados. Selecione um para testar." }
        case "screen":
            guard let screen = try? JSONDecoder().decode(TerminalSnapshot.self, from: data), session.accepts(screen) else { return }
            snapshot = screen
            statusCode = "ready"
            status = "Tela conectada. Estado do agente: desconhecido."
        case "diagnostic", "error":
            let code = message.code ?? "integration_unavailable"
            statusCode = code
            if operation == "dock" {
                docked = false
                dockFailed = true
                embedOnSelect = false
                if let id = selectedID, let terminal = terminals.first(where: { $0.id == id }) { select(terminal) }
            }
            if operation == "resume" { onResume?(nil, message.ambiguous == true) }
            if operation == "input" || operation == "select" || ["sdk_missing", "connection_unavailable", "protocol_incompatible", "local_transport_unavailable"].contains(code) { snapshot = nil }
            status = explanation(code) + (message.ambiguous == true ? " Resultado incerto; não repetido." : "")
            record(code)
        case "ack":
            if operation == "select" {
                if embedOnSelect, let target = try? session.prepareInput("") {
                    dockFailed = false
                    send("dock", target: target, frame: embedFrame)
                } else if embedOnSelect {
                    dockFailed = true
                } else { loadHistory() }
            }
            if operation == "dock" { docked = message.docked == true; dockFailed = false }
            if operation == "unselect" { docked = false }
            if operation == "resume" { onResume?(message.createdTerminal, false); refresh() }
            if operation == "restore" {
                status = message.restored == true ? "Grade original restaurada." :
                    "Grade preservada: \(message.reason ?? "sem ajuste pertencente ao app")."
            }
            if operation == "resize" { status = "Grade ajustada e confirmada pelo iTerm2." }
        default: break
        }
    }

    private func connectLocalSocket() {
        guard let socketFolder else { return }
        let path = socketFolder.appendingPathComponent("bridge").path
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { statusCode = "local_transport_unavailable"; return }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { statusCode = "local_transport_unavailable"; return }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { Darwin.close(fd); statusCode = "local_transport_unavailable"; return }
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let duplicate = dup(fd)
        guard duplicate >= 0 else { Darwin.close(fd); statusCode = "local_transport_unavailable"; return }
        output?.readabilityHandler = nil
        try? input?.close(); try? output?.close()
        input = FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
        let read = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        output = read
        let activeRun = runID
        read.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                guard self?.runID == activeRun else { return }
                self?.receive(data)
            }
        }
    }

    private func explanation(_ code: String) -> String {
        switch code {
        case "sdk_missing": "SDK ausente. Execute scripts/run-proof.sh no iTerm2."
        case "connection_unavailable": "Conexão indisponível. Abra o iTerm2, habilite a API e autorize o script."
        case "resize_split_unavailable": "Aba dividida: a grade permanece original; use a rolagem do espelho."
        case "resize_fullscreen_unavailable": "Fullscreen: a grade permanece original; use a rolagem do espelho."
        case "resize_ownership_lost": "O tamanho foi alterado fora do app. Sua grade será preservada."
        case "operation_timeout": "A operação não respondeu no prazo. Nenhuma entrada ou aba será reenviada automaticamente."
        case "stale_terminal", "stale_selection", "stale_connection", "identity_unconfirmed":
            "Destino não confirmado. Atualize o inventário e selecione novamente."
        default: "Integração: \(code). Entrada pode exigir nova seleção."
        }
    }

    private func record(_ code: String) {
        let folder = project.appendingPathComponent(".proof")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("diagnostics.jsonl")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let value = ["time": ISO8601DateFormatter().string(from: Date()), "code": code]
        guard var data = try? JSONEncoder().encode(value), let handle = try? FileHandle(forWritingTo: file) else { return }
        data.append(0x0a)
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

public struct ProofView: View {
    @ObservedObject var controller: TerminalGateway
    @State private var viewport = CGSize.zero
    public init(controller: TerminalGateway) { self.controller = controller }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Prova de integração").font(.headline)
                Spacer()
                Button("Conectar", action: controller.start).disabled(controller.isRunning)
                Button("Atualizar", action: controller.refresh).disabled(!controller.connected)
                Button("Ajustar grade") {
                    controller.resize(columns: max(2, Int((viewport.width - 16) / TerminalCanvas.cellWidth)),
                                      rows: max(1, Int((viewport.height - 16) / TerminalCanvas.cellHeight)))
                }.disabled(!controller.canSend)
                Button("Restaurar", action: controller.restore).disabled(!controller.canSend)
                Button("Fechar espelho", action: controller.closeMirror).disabled(controller.selectedID == nil)
            }.padding(12)
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.terminals) { terminal in
                            Button { controller.select(terminal) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(terminal.name).lineLimit(1).font(.headline)
                                    Text(terminal.provider ?? "Terminal · identificação em prova")
                                    Text(terminal.project).font(.caption).lineLimit(2)
                                    Text("Estado: desconhecido").font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(controller.selectedID == terminal.id ? Color.accentColor.opacity(0.16) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                        if controller.terminals.isEmpty {
                            Text("Abra uma aba de teste no iTerm2. A lista aparece após conectar.")
                                .foregroundStyle(.secondary).padding(12)
                        }
                    }.padding(8)
                }.frame(width: 240)
                Divider()
                GeometryReader { geometry in
                    TerminalMirror(snapshot: controller.snapshot, enabled: controller.canSend,
                                   send: controller.sendText)
                        .onAppear { viewport = geometry.size }
                        .onChange(of: geometry.size) { _, size in viewport = size }
                }
            }
            Divider()
            Text(controller.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            Text("A prova não classifica estados ainda. Teclado e colagem precisam de validação nos dois CLIs.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
    }
}

private struct TerminalHistory: Decodable {
    let connection: String
    let terminal: TerminalIdentity
    let selection: UInt64
    let lines: [TerminalLine]
    let firstLine: Int
    let hasMore: Bool
}
