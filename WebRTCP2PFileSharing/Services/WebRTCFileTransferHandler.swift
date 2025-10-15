//
//  WebRTCFileTransferHandler.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import Foundation
import WebRTC

// MARK: - Delegate

public protocol WebRTCFileTransferDelegate: AnyObject {
    // Sender (uploader)
    func uploadStarted(fileId: String, name: String, size: Int)
    func uploadProgress(fileId: String, sentBytes: Int, totalBytes: Int, speedBps: Double, etaSeconds: Double?)
    func uploadPaused(fileId: String)
    func uploadResumed(fileId: String)
    func uploadCompleted(fileId: String)
    func uploadFailed(fileId: String, error: Error)

    // Receiver (downloader)
    func downloadPrepared(fileId: String, name: String, size: Int, tempURL: URL)
    func downloadProgress(fileId: String, receivedBytes: Int, totalBytes: Int)
    func downloadCompleted(fileId: String, finalURL: URL)
    func downloadFailed(fileId: String, error: Error)
}

public extension WebRTCFileTransferDelegate {
    func uploadStarted(fileId: String, name: String, size: Int) {}
    func uploadProgress(fileId: String, sentBytes: Int, totalBytes: Int, speedBps: Double, etaSeconds: Double?) {}
    func uploadPaused(fileId: String) {}
    func uploadResumed(fileId: String) {}
    func uploadCompleted(fileId: String) {}
    func uploadFailed(fileId: String, error: Error) {}

    func downloadPrepared(fileId: String, name: String, size: Int, tempURL: URL) {}
    func downloadProgress(fileId: String, receivedBytes: Int, totalBytes: Int) {}
    func downloadCompleted(fileId: String, finalURL: URL) {}
    func downloadFailed(fileId: String, error: Error) {}
}

// MARK: - Handler

/// Single object that can both send and receive a file over a WebRTC RTCDataChannel.
/// Attach the data channel whenever it opens (including after reconnect).
public final class WebRTCFileTransferHandler: NSObject {

    // MARK: Control protocol (JSON text). Chunks are sent as binary frames.

    private enum CtrlType: String, Codable { case manifest, have, end, complete, cancel, ack, error }

    private struct ManifestMessage: Codable {
        let t: CtrlType = .manifest
        let id: String
        let name: String
        let size: Int
        let chunk: Int
        let total: Int
    }
    private struct HaveMessage: Codable {
        let t: CtrlType = .have
        let id: String
        let idx: [Int]
    }
    private struct EndMessage: Codable {
        let t: CtrlType = .end
        let id: String
    }
    private struct CompleteMessage: Codable {
        let t: CtrlType = .complete
        let id: String
    }
    private struct CancelMessage: Codable {
        let t: CtrlType = .cancel
        let id: String
    }
    private struct AckMessage: Codable {
        let t: CtrlType = .ack
        let id: String
        let index: Int
        let success: Bool
    }
    private struct ErrorMessage: Codable {
        let t: CtrlType = .error
        let id: String
        let index: Int
        let error: String
    }

    /// Binary CHUNK frame layout:
    /// [1 byte type=0xC1][4 bytes fileIdLen][fileId UTF8][4 bytes index][4 bytes payloadLen][payload]

    // MARK: Configuration knobs

    public weak var delegate: WebRTCFileTransferDelegate?

    /// Where completed files are saved. Defaults to app Documents directory.
    public var finalSaveDirectory: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return url
    }()

    /// Where partial downloads & metadata live. Defaults to <Documents>/WebRTCDownloads
    public var downloadsWorkDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WebRTCDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Size in bytes per chunk (16–64 KB recommended; keep ≤ ~64 KB for cross-platform safety).
    public var chunkSize: Int = 32 * 1024

    /// Optional upload rate cap (bytes/second). Set to nil for unlimited.
    public var uploadRateLimitBps: Int? = nil

    /// Maximum retry attempts for failed chunks
    public var maxRetryAttempts: Int = 3

    /// Timeout for waiting for acknowledgment (seconds)
    public var ackTimeout: TimeInterval = 10.0

    // MARK: Internal state

    private let q = DispatchQueue(label: "webrtc.file.transfer", qos: .userInitiated)
    private var dc: RTCDataChannel? {
        didSet {
            oldValue?.delegate = nil
            dc?.delegate = self
            if dc?.readyState == .open {
                // Re-advertise manifest if we were mid-upload (auto-resume handshake)
                q.async { [weak self] in self?.maybeResumeAfterAttach() }
            }
        }
    }

    // Sender (uploader) state
    private struct SendState {
        let fileId: String
        let name: String
        let url: URL
        let size: Int
        let totalChunks: Int
        var nextIndex: Int
        var paused: Bool
        var userPaused: Bool
        var startedAt: Date
        var lastSecondAt: Date
        var bytesSentThisSecond: Int
        var totalBytesReported: Int
        var fileHandle: FileHandle
        var missing: Set<Int>           // chunks that the receiver still needs
        var awaitingHave: Bool          // waiting for receiver to tell what it has
        var waitingForAck: Bool         // waiting for acknowledgment of current chunk
        var currentChunkIndex: Int?     // index of chunk currently being sent
        var retryCount: [Int: Int]      // retry count for each chunk index
        var ackTimer: DispatchSourceTimer?
    }
    private var send: SendState?

    // Receiver (downloader) state, keyed by fileId (supports one at a time; map for extensibility)
    private struct RecvState {
        let fileId: String
        let name: String
        let size: Int
        let chunk: Int
        let total: Int
        let workDir: URL
        let partURL: URL
        let finalURL: URL
        var received: Set<Int>
        var fileHandle: FileHandle
        var lastPersistAt: Date
    }
    private var recv: [String: RecvState] = [:]

    // MARK: Lifecycle

    public override init() { super.init() }

    /// Attach (or reattach) the RTCDataChannel whenever it opens (including after reconnect).
    public func attach(_ channel: RTCDataChannel) {
        q.async { self.dc = channel }
    }

    /// Notify the handler that the PC/DC is going down; we auto-pause to avoid partial buffering.
    public func onConnectionWillClose() {
        q.async {
            if var s = self.send {
                s.paused = true
                s.userPaused = s.userPaused // keep user intent
                self.send = s
                self.delegate?.uploadPaused(fileId: s.fileId)
            }
        }
    }

    // MARK: Sender API

    /// Start sending a file (new transfer) or resume into a known fileId (optional).
    public func sendFile(at url: URL, fileId: String? = nil) throws {
        print("sendFile at \(url)")
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attr[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw NSError(domain: "WebRTCFile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty file"]) }

        let total = Int(ceil(Double(size) / Double(chunkSize)))
        let fid = fileId ?? UUID().uuidString
        let fh = try FileHandle(forReadingFrom: url)

        q.async {
            self.send = SendState(
                fileId: fid,
                name: url.lastPathComponent,
                url: url,
                size: size,
                totalChunks: total,
                nextIndex: 0,
                paused: false,
                userPaused: false,
                startedAt: Date(),
                lastSecondAt: Date(),
                bytesSentThisSecond: 0,
                totalBytesReported: 0,
                fileHandle: fh,
                missing: Set(0..<total),
                awaitingHave: true,
                waitingForAck: false,
                currentChunkIndex: nil,
                retryCount: [:],
                ackTimer: nil
            )
            self.delegate?.uploadStarted(fileId: fid, name: url.lastPathComponent, size: size)
            
            // Send initial progress update (0%)
            self.delegate?.uploadProgress(fileId: fid,
                                          sentBytes: 0,
                                          totalBytes: size,
                                          speedBps: 0.0,
                                          etaSeconds: nil)
            
            self.sendManifest()
        }
    }

    public func pauseUpload() {
        q.async {
            guard var s = self.send else { return }
            s.paused = true
            s.userPaused = true
            self.send = s
            self.delegate?.uploadPaused(fileId: s.fileId)
        }
    }

    public func resumeUpload() {
        q.async {
            guard var s = self.send else { return }
            s.userPaused = false
            s.paused = false
            self.send = s
            self.delegate?.uploadResumed(fileId: s.fileId)
            if s.awaitingHave {
                self.sendManifest() // need receiver's HAVE to reconcile
            } else if !s.waitingForAck {
                self.sendNextChunk()
            }
        }
    }

    public func cancelUpload() {
        q.async {
            guard let s = self.send else { return }
            self.sendText(Self.CancelMessage(id: s.fileId))
            self.cleanupSend()
        }
    }

    // MARK: Internals — Sender

    private func sendManifest() {
        guard let s = self.send else { return }
        guard let _ = self.dc, self.dc?.readyState == .open else { return }
        let m = ManifestMessage(id: s.fileId, name: s.name, size: s.size, chunk: self.chunkSize, total: s.totalChunks)
        self.sendText(m)
        // wait for HAVE before pumping
    }

    private func maybeResumeAfterAttach() {
        guard let s = self.send else { return }
        // Only auto-resume if not user-paused
        if s.userPaused { return }
        // We re-send manifest to learn what the receiver already persisted
        sendManifest()
    }

    private func sendNextChunk() {
        guard var s = self.send, let dc = self.dc, dc.readyState == .open else { return }
        if s.paused || s.awaitingHave || s.waitingForAck { return }

        // Finished?
        if s.missing.isEmpty {
            self.sendText(Self.EndMessage(id: s.fileId))
            self.delegate?.uploadCompleted(fileId: s.fileId)
            self.cleanupSend()
            return
        }

        // Rate limit (simple per-second cap)
        if let cap = self.uploadRateLimitBps {
            let now = Date()
            let dt = now.timeIntervalSince(s.lastSecondAt)
            if dt >= 1.0 {
                s.lastSecondAt = now
                s.bytesSentThisSecond = 0
            } else if s.bytesSentThisSecond >= cap {
                self.send = s
                self.scheduleTickResume()
                return
            }
        }

        // Choose next missing index (monotonic preference)
        guard let idx = s.missing.first(where: { $0 >= s.nextIndex }) ?? s.missing.first else {
            s.nextIndex = 0
            self.send = s
            self.sendNextChunk()
            return
        }

        // Read chunk
        let offset = idx * self.chunkSize
        let length = min(self.chunkSize, s.size - offset)
        do {
            try s.fileHandle.seek(toOffset: UInt64(offset))
            guard let data = try s.fileHandle.read(upToCount: length), !data.isEmpty else {
                // skip & continue
                s.missing.remove(idx)
                s.nextIndex = idx + 1
                self.send = s
                self.sendNextChunk()
                return
            }

            // Build binary frame
            let frame = self.buildChunkFrame(fileId: s.fileId, index: idx, payload: data)

            // Try to send
            let ok = dc.sendData(RTCDataBuffer(data: frame, isBinary: true))
            if !ok {
                // If channel refused (rare), schedule a short retry
                self.send = s
                self.scheduleTickResume()
                return
            }

            // Update state to wait for acknowledgment
            s.waitingForAck = true
            s.currentChunkIndex = idx
            s.bytesSentThisSecond += length
            
            // Don't update totalBytesReported here - wait for acknowledgment
            // This will be updated when we receive a successful ack
            
            s.nextIndex = idx + 1
            self.send = s

            // Start acknowledgment timer
            self.startAckTimer(for: idx)

        } catch {
            self.delegate?.uploadFailed(fileId: s.fileId, error: error)
            self.cleanupSend()
        }
    }

    private func startAckTimer(for index: Int) {
        guard var s = self.send else { return }
        
        s.ackTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: q)
        timer.schedule(deadline: .now() + ackTimeout)
        timer.setEventHandler { [weak self] in
            self?.handleAckTimeout(for: index)
        }
        s.ackTimer = timer
        timer.resume()
        self.send = s
    }

    private func handleAckTimeout(for index: Int) {
        guard var s = self.send, s.currentChunkIndex == index else { return }
        
        // Increment retry count
        let retryCount = s.retryCount[index, default: 0] + 1
        s.retryCount[index] = retryCount
        
        if retryCount >= maxRetryAttempts {
            // Max retries exceeded, fail the transfer
            self.delegate?.uploadFailed(fileId: s.fileId, 
                                        error: NSError(domain: "WebRTCFile", code: 3, 
                                        userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded for chunk \(index)"]))
            self.cleanupSend()
            return
        }
        
        // Reset state and retry
        s.waitingForAck = false
        s.currentChunkIndex = nil
        s.ackTimer?.cancel()
        s.ackTimer = nil
        self.send = s
        
        // Retry sending the same chunk
        self.sendNextChunk()
    }

    private func handleAck(ack: AckMessage) {
        guard var s = self.send, s.fileId == ack.id, s.currentChunkIndex == ack.index else { return }
        
        if ack.success {
            // Chunk received successfully, remove from missing set
            s.missing.remove(ack.index)
            s.waitingForAck = false
            s.currentChunkIndex = nil
            s.ackTimer?.cancel()
            s.ackTimer = nil
            
            // Update totalBytesReported to reflect successfully acknowledged chunks
            let acknowledgedChunks = s.totalChunks - s.missing.count
            let acknowledgedBytes = min(s.size, acknowledgedChunks * self.chunkSize)
            s.totalBytesReported = acknowledgedBytes
            
            // Send progress update
            let elapsed = max(0.001, Date().timeIntervalSince(s.startedAt))
            let speed = Double(s.totalBytesReported) / elapsed
            let remaining = max(0, s.size - s.totalBytesReported)
            let eta = speed > 0 ? Double(remaining) / speed : nil
            
            self.delegate?.uploadProgress(fileId: s.fileId,
                                          sentBytes: s.totalBytesReported,
                                          totalBytes: s.size,
                                          speedBps: speed,
                                          etaSeconds: eta)
            
            self.send = s
            
            // Send next chunk
            self.sendNextChunk()
        } else {
            // Chunk failed, retry
            let retryCount = s.retryCount[ack.index, default: 0] + 1
            s.retryCount[ack.index] = retryCount
            
            if retryCount >= maxRetryAttempts {
                self.delegate?.uploadFailed(fileId: s.fileId, 
                                            error: NSError(domain: "WebRTCFile", code: 4, 
                                            userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded for chunk \(ack.index)"]))
                self.cleanupSend()
                return
            }
            
            // Reset state and retry
            s.waitingForAck = false
            s.currentChunkIndex = nil
            s.ackTimer?.cancel()
            s.ackTimer = nil
            self.send = s
            
            // Retry sending the same chunk
            self.sendNextChunk()
        }
    }

    private func handleError(error: ErrorMessage) {
        guard var s = self.send, s.fileId == error.id, s.currentChunkIndex == error.index else { return }
        
        // Reset state and retry the failed chunk
        s.waitingForAck = false
        s.currentChunkIndex = nil
        s.ackTimer?.cancel()
        s.ackTimer = nil
        self.send = s
        
        // Retry sending the same chunk
        self.sendNextChunk()
    }

    private func scheduleTickResume() {
        q.asyncAfter(deadline: .now() + .milliseconds(60)) { [weak self] in
            self?.sendNextChunk()
        }
    }

    private func cleanupSend() {
        try? send?.fileHandle.close()
        send?.ackTimer?.cancel()
        send = nil
    }

    // MARK: Internals — Receiver

    private func handle(manifest m: ManifestMessage) {
        // Prepare workspace for this fileId
        let workDir = downloadsWorkDirectory.appendingPathComponent(m.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let partURL = workDir.appendingPathComponent("\(m.name).part")
        let finalURL = finalSaveDirectory.appendingPathComponent(m.name)

        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }

        // Try to open file for update
        guard let fh = try? FileHandle(forUpdating: partURL) else {
            delegate?.downloadFailed(fileId: m.id, error: NSError(domain: "WebRTCFile", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open partial file"]))
            return
        }

        // Load prior bitmap for resume
        let bitmapURL = workDir.appendingPathComponent("received.idx")
        var received = Set<Int>()
        if let data = try? Data(contentsOf: bitmapURL),
           let list = try? JSONDecoder().decode([Int].self, from: data) {
            received = Set(list)
        }

        let r = RecvState(fileId: m.id, name: m.name, size: m.size, chunk: m.chunk, total: m.total,
                          workDir: workDir, partURL: partURL, finalURL: finalURL,
                          received: received, fileHandle: fh, lastPersistAt: Date())
        recv[m.id] = r

        delegate?.downloadPrepared(fileId: m.id, name: m.name, size: m.size, tempURL: partURL)

        // Tell sender what we already have (resume handshake)
        sendText(HaveMessage(id: m.id, idx: Array(received)))
    }

    private func handle(have: HaveMessage) {
        // Sender reconciles what receiver already has and starts/continues pumping
        guard var s = send, s.fileId == have.id else { return }
        s.missing.subtract(have.idx)

        // Progress correction after resume (optional conservative update)
        let bytes = have.idx.reduce(0) { $0 + min(chunkSize, s.size - ($1 * chunkSize)) }
        s.totalBytesReported = max(s.totalBytesReported, min(s.size, bytes))
        s.awaitingHave = false
        send = s

        sendNextChunk()
    }

    private func handle(end: EndMessage) {
        guard var r = recv[end.id] else { return }
        if r.received.count == r.total {
            finalize(&r)
            recv[end.id] = r
            sendText(CompleteMessage(id: r.fileId))
            delegate?.downloadCompleted(fileId: r.fileId, finalURL: r.finalURL)
        } else {
            // Ask for the rest by re-sending what we have
            sendText(HaveMessage(id: r.fileId, idx: Array(r.received)))
        }
    }

    private func handle(complete: CompleteMessage) {
        guard let s = send, s.fileId == complete.id else { return }
        delegate?.uploadCompleted(fileId: s.fileId)
        cleanupSend()
    }

    private func handle(cancel: CancelMessage) {
        if var r = recv[cancel.id] {
            try? r.fileHandle.close()
            try? FileManager.default.removeItem(at: r.partURL)
            recv.removeValue(forKey: cancel.id)
        }
    }

    private func handleChunk(_ data: Data) {
        var cursor = 0
        func take(_ n: Int) -> Data? {
            guard data.count >= cursor + n else { return nil }
            let slice = data[cursor ..< cursor + n]
            cursor += n
            return Data(slice)
        }

        guard let type = take(1)?.first, type == 0xC1 else { return }
        guard let idLenData = take(4) else { return }
        let idLen = Int(idLenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard let idData = take(idLen), let fileId = String(data: idData, encoding: .utf8) else { return }
        guard let idxData = take(4) else { return }
        let index = Int(idxData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard let plenData = take(4) else { return }
        let pLen = Int(plenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard let payload = take(pLen) else { return }

        guard var r = recv[fileId] else { return }
        if r.received.contains(index) { 
            // Already have this chunk, send acknowledgment
            sendText(AckMessage(id: r.fileId, index: index, success: true))
            return 
        }

        let offset = UInt64(index * r.chunk)
        do {
            try r.fileHandle.seek(toOffset: offset)
            try r.fileHandle.write(contentsOf: payload)
            
            // Send success acknowledgment
            sendText(AckMessage(id: r.fileId, index: index, success: true))
            
        } catch {
            // Send error acknowledgment with index
            sendText(ErrorMessage(id: r.fileId, index: index, error: error.localizedDescription))
            delegate?.downloadFailed(fileId: r.fileId, error: error)
            return
        }

        r.received.insert(index)

        // Periodically persist received bitmap for crash-safe resume
        let now = Date()
        if now.timeIntervalSince(r.lastPersistAt) > 0.6 || r.received.count == r.total {
            let bitmapURL = r.workDir.appendingPathComponent("received.idx")
            if let data = try? JSONEncoder().encode(Array(r.received)) {
                try? data.write(to: bitmapURL, options: .atomic)
            }
            r.lastPersistAt = now
        }

        // Progress callback
        // (We can compute exact bytes by summing chunks; here's a simple estimator)
        let bytes = min(r.size, (r.received.count - 1) * r.chunk + payload.count)
        delegate?.downloadProgress(fileId: fileId, receivedBytes: bytes, totalBytes: r.size)

        recv[fileId] = r
    }

    private func finalize(_ r: inout RecvState) {
        try? r.fileHandle.close()
        // Move .part to final save location (overwrite if exists)
        try? FileManager.default.removeItem(at: r.finalURL)
        try? FileManager.default.moveItem(at: r.partURL, to: r.finalURL)
        // Cleanup bitmap + work dir
        try? FileManager.default.removeItem(at: r.workDir.appendingPathComponent("received.idx"))
        try? FileManager.default.removeItem(at: r.workDir)
    }

    // MARK: Send helpers

    private func sendText<T: Encodable>(_ obj: T) {
        guard let dc, dc.readyState == .open else { return }
        print("===>>> WebRTC send data \(obj)")
        if let data = try? JSONEncoder().encode(obj) {
            _ = dc.sendData(RTCDataBuffer(data: data, isBinary: false))
        }
    }

    private func buildChunkFrame(fileId: String, index: Int, payload: Data) -> Data {
        var out = Data()
        out.append(0xC1)
        var idBytes = [UInt8](fileId.utf8)
        var u32 = UInt32(idBytes.count).bigEndian
        withUnsafeBytes(of: &u32) { out.append(contentsOf: $0) }
        out.append(contentsOf: idBytes)
        var idx = UInt32(index).bigEndian
        withUnsafeBytes(of: &idx) { out.append(contentsOf: $0) }
        var len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCFileTransferHandler: RTCDataChannelDelegate {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        // Auto-resume handshake if re-opened and we weren't user-paused
        if dataChannel.readyState == .open {
            q.async { [weak self] in self?.maybeResumeAfterAttach() }
        }
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if buffer.isBinary {
            q.async { [weak self] in self?.handleChunk(buffer.data) }
            return
        }
        // Parse control JSON
        guard
            let dict = (try? JSONSerialization.jsonObject(with: buffer.data)) as? [String: Any],
            let raw = dict["t"] as? String,
            let kind = CtrlType(rawValue: raw)
        else { return }

        q.async { [weak self] in
            guard let self else { return }
            print("===>>> data Channel received message: kind \(raw), dict \(dict)")
            switch kind {
            case .manifest:
                if let msg = try? JSONDecoder().decode(ManifestMessage.self, from: buffer.data) {
                    self.handle(manifest: msg)
                }
            case .have:
                if let msg = try? JSONDecoder().decode(HaveMessage.self, from: buffer.data) {
                    self.handle(have: msg)
                }
            case .end:
                if let msg = try? JSONDecoder().decode(EndMessage.self, from: buffer.data) {
                    self.handle(end: msg)
                }
            case .complete:
                if let msg = try? JSONDecoder().decode(CompleteMessage.self, from: buffer.data) {
                    self.handle(complete: msg)
                }
            case .cancel:
                if let msg = try? JSONDecoder().decode(CancelMessage.self, from: buffer.data) {
                    self.handle(cancel: msg)
                }
            case .ack:
                if let msg = try? JSONDecoder().decode(AckMessage.self, from: buffer.data) {
                    self.handleAck(ack: msg)
                }
            case .error:
                if let msg = try? JSONDecoder().decode(ErrorMessage.self, from: buffer.data) {
                    self.handleError(error: msg)
                }
            }
        }
    }
}
