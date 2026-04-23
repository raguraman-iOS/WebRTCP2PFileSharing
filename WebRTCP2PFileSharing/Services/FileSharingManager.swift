//
//  FileSharingManager.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import Foundation
import SwiftUI
import WebRTC
import UniformTypeIdentifiers
import UIKit

enum UploadStatus: String, CaseIterable {
    case idle = "Idle"
    case transferring = "Transferring"
    case completed = "Completed"
    case failed = "Failed"
    case paused = "Paused"
}

enum DownloadStatus: String, CaseIterable {
    case idle = "Idle"
    case downloading = "Downloading"
    case completed = "Completed"
    case failed = "Failed"
    case paused = "Paused"
}

enum ToastType {
    case success
    case error
    case info
    case warning
}

enum FileSharingStatus: String, CaseIterable {
    case pending = "Pending"
    case accepted = "Accepted"
    case declined = "Declined"
    case completed = "Completed"
}

enum FileAccessError: LocalizedError {
    case permissionDenied
    case fileNotFound
    case fileNotReadable
    case fileEmpty
    case fileCorrupted
    case fileCopyFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied to access this file"
        case .fileNotFound:
            return "File not found at the specified location"
        case .fileNotReadable:
            return "File is not readable"
        case .fileEmpty:
            return "File is empty or corrupted"
        case .fileCorrupted:
            return "File appears to be corrupted"
        case .fileCopyFailed:
            return "Failed to copy file to local storage"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please grant permission to access files in Settings > Privacy & Security > Files and Folders"
        case .fileNotFound:
            return "The file may have been moved or deleted. Please select the file again."
        case .fileNotReadable:
            return "The file may be locked or in use by another app."
        case .fileEmpty:
            return "Please select a different file that contains data."
        case .fileCorrupted:
            return "The file may be damaged. Please try selecting the file again or use a different copy."
        case .fileCopyFailed:
            return "Please try selecting the file again. If the issue persists, check available storage space."
        }
    }
}

struct IncomingFileRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let fileSize: String
    let fileType: String
    let senderId: String
    let timestamp: Date
}

struct FileSharingRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let fileSize: String
    let fileType: String
    let senderId: String
    let timestamp: Date
    var status: FileSharingStatus
}

class FileSharingManager: ObservableObject {
    @Published var isConnected = false
    @Published var selectedFile: FileInfo?
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var uploadStatus: UploadStatus = .idle
    @Published var uploadSpeed: String = "0 KB/s"
    @Published var uploadTotalBytes: Int64 = 0
    @Published var uploadSentBytes: Int64 = 0
    
    // Receiver properties
    @Published var incomingFileRequests: [IncomingFileRequest] = []
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: DownloadStatus = .idle
    @Published var downloadSpeed: String = "0 KB/s"
    @Published var currentDownload: FileInfo?
    
    // Internal download speed tracking
    private var lastDownloadBytesForSpeed: Int = 0
    private var lastDownloadTimestamp: Date = Date()
    
    // File sharing request properties
    @Published var pendingFileRequests: [FileSharingRequest] = []
    @Published var showingIncomingRequestAlert = false
    @Published var currentIncomingRequest: IncomingFileRequest?
    
    // Received files tracking
    @Published var receivedFiles: [ReceivedFile] = []
    @Published var showingFilePreview = false
    @Published var fileToPreview: ReceivedFile?
    
    @Published var toastMessage: String?
    @Published var toastType: ToastType = .success
    
    private var uploadTimer: Timer?
    private var speedUpdateTimer: Timer?
    private var downloadTimer: Timer?
    private var downloadSpeedTimer: Timer?
    private let signalClient: SignalingClient
    private var webRTCClient: WebRTCClient? = nil
    private var webRTCFileTransferClient: WebRTCFileTransferHandler? = nil
    
    // Background state tracking
    private var wasUploadingBeforeBackground = false
    private var wasDownloadingBeforeBackground = false
    
    init() {
        let config = Config.default
        signalClient = SignalingClient(webSocket: NativeWebSocket(url: config.signalingServerUrl))
        signalClient.delegate = self
        signalClient.connect()
        
        // Load previously received files
        loadReceivedFiles()
        
        // Check for orphaned files and permissions
        checkForOrphanedFiles()
        checkFilePermissions()
        
        // Set up app lifecycle notifications
        setupAppLifecycleNotifications()
        
        // Simulate incoming file requests
//        startIncomingRequestSimulation()
    }
    
    // MARK: - Sender Methods
    
    
    func selectFile(url: URL) throws {
        // Clean up any previously selected file
        if let previousFile = selectedFile {
            cleanupLocalFile(previousFile.url)
        }
        
        // Check if this is a file in our own documents directory (internal file)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let isInternalFile = url.path.hasPrefix(documentsPath.path)
        
        print("FileSharingManager: Processing file: \(url.path)")
        print("FileSharingManager: Documents path: \(documentsPath.path)")
        print("FileSharingManager: Is internal file: \(isInternalFile)")
        
        // Only use security-scoped resource access for external files
        if !isInternalFile {
            print("FileSharingManager: External file, using security-scoped resource access")
            guard url.startAccessingSecurityScopedResource() else {
                print("FileSharingManager: Failed to access security-scoped resource")
                throw FileAccessError.permissionDenied
            }
            
            defer {
                // Always stop accessing the security-scoped resource
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            print("FileSharingManager: Internal file, no security-scoped resource access needed")
        }
        
        // Validate file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAccessError.fileNotFound
        }
        
        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FileAccessError.fileNotReadable
        }
        
        // Get file attributes to check size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize > 0 else {
            throw FileAccessError.fileEmpty
        }
        
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        print("this are the file attr \(attr)")
        
        // For internal files (like converted images/videos), use them directly
        // For external files, copy to local storage for reliable access
        let finalFileURL: URL
        if isInternalFile {
            print("FileSharingManager: Using internal file directly: \(url.path)")
            finalFileURL = url
        } else {
            print("FileSharingManager: Copying external file to local storage")
            finalFileURL = try copyFileToLocalStorage(from: url)
        }
        
        print("FileSharingManager: Final file URL: \(finalFileURL.path)")
        
        // Create FileInfo with the final file URL
        let fileInfo = try FileInfo(url: finalFileURL)
        selectedFile = fileInfo
        
        // Initialize WebRTC client and create file sharing request
        initializeWebRTCClient()
        createFileSharingRequest(for: fileInfo)
        
        showToast("File selected: \(fileInfo.name)", type: .success)
    }
    
    private func initializeWebRTCClient() {
        guard webRTCClient == nil else { return }
        webRTCClient = WebRTCClient(iceServers: Config.default.webRTCIceServers,
                                    turnServer: Config.default.webRTCTurnServer)
        webRTCClient?.delegate = self
    }
    
    private func createFileSharingRequest(for file: FileInfo) {
        let request = FileSharingRequest(
            fileName: file.name,
            fileSize: file.size,
            fileType: file.type,
            senderId: "You", // In real app, this would be the user's ID
            timestamp: Date(),
            status: .pending
        )
        
        pendingFileRequests.append(request)
        
        // Simulate sending the request to receiver
        // In real implementation, this would be sent via WebRTC
//        simulateFileRequestSent(request)
        self.webRTCClient?.offer { (sdp) in
//            self.hasLocalSdp = true
            self.signalClient.send(sdp: sdp)
        }
        
        showToast("File sharing request sent", type: .info)
    }
    
//    private func simulateFileRequestSent(_ request: FileSharingRequest) {
//        // Simulate the request being sent and waiting for receiver response
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//            // Simulate receiver accepting the request
//            self.handleFileRequestAccepted(request)
//        }
//    }
    
    private func handleFileRequestAccepted(_ request: FileSharingRequest) {
        // Update request status
        if let index = pendingFileRequests.firstIndex(where: { $0.id == request.id }) {
            pendingFileRequests[index].status = .accepted
        }
        
        // Now start the actual upload
        startUpload()
        
        showToast("File transfer accepted! Starting upload...", type: .success)
    }
    
    func startUpload() {
        guard let file = selectedFile, let dc = webRTCClient?.remoteDataChannel else { return }
        
        isUploading = true
        uploadStatus = .transferring
        uploadProgress = 0.0
        
        webRTCFileTransferClient = WebRTCFileTransferHandler()
        webRTCFileTransferClient?.delegate = self // implement WebRTCFileTransferDelegate

        // when your dc opens (or reopens)
        webRTCFileTransferClient?.attach(dc)

        // start an upload
        do {
            try webRTCFileTransferClient?.sendFile(at: file.url)
        } catch { error
            print("file transfer error \(error)")
        }
        

        // pause/resume from UI
//        handler.pauseUpload()
//        handler.resumeUpload()

        // apply (optional) speed cap, e.g. 1.5 Mbps
//        handler.uploadRateLimitBps = 1_500_000
        
        // Simulate upload progress
//        uploadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
//            guard let self = self else { return }
//            
//            if self.uploadProgress < 1.0 {
//                self.uploadProgress += 0.01
//                
//                // Simulate upload completion
//                if self.uploadProgress >= 1.0 {
//                    self.uploadCompleted()
//                }
//            }
//        }
        
        // Simulate speed updates
//        startSpeedSimulation()
    }
    
    func pauseUpload() {
        // Call the WebRTC file transfer handler's pause method
        webRTCFileTransferClient?.pauseUpload()
        
        // Note: The uploadStatus will be updated via the delegate method uploadPaused()
        // Don't clean up local file on pause, as user might resume
    }
    
    func resumeUpload() {
        // Call the WebRTC file transfer handler's resume method
        webRTCFileTransferClient?.resumeUpload()
        
        // Note: The uploadStatus will be updated via the delegate method uploadResumed()
    }
    
    func cancelUpload() {
        // Call the WebRTC file transfer handler's cancel method
        webRTCFileTransferClient?.cancelUpload()
        
        // Reset local state
        uploadStatus = .idle
        isUploading = false
        uploadProgress = 0.0
        uploadSentBytes = 0
        uploadTotalBytes = 0
        uploadSpeed = "0 KB/s"
        uploadTimer?.invalidate()
        speedUpdateTimer?.invalidate()
        
        // Clean up the local copy of the file
        if let selectedFile = selectedFile {
            cleanupLocalFile(selectedFile.url)
            self.selectedFile = nil
        }
        
        // Clear pending requests
        pendingFileRequests.removeAll()
        
        print("Upload cancelled, progress reset")
    }
    
//    private func uploadCompleted() {
//        uploadStatus = .completed
//        isUploading = false
//        uploadTimer?.invalidate()
//        speedUpdateTimer?.invalidate()
//        selectedFile = nil
//        
//        showToast("File uploaded successfully!", type: .success)
//        
//        // Clear pending requests
//        pendingFileRequests.removeAll()
//        
//        // Reset after a delay
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//            self.uploadStatus = .idle
//            self.uploadProgress = 0.0
//        }
//    }
    
    private func startSpeedSimulation() {
        speedUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Simulate varying upload speeds
            let speeds = ["125 KB/s", "256 KB/s", "512 KB/s", "1.2 MB/s", "2.1 MB/s"]
            self.uploadSpeed = speeds.randomElement() ?? "0 KB/s"
        }
    }
    
    // MARK: - Receiver Methods
    
    func acceptFileRequest(_ request: IncomingFileRequest) {
        // Remove from incoming requests
        incomingFileRequests.removeAll { $0.id == request.id }
        
        currentIncomingRequest = request
        
        sendAcceptanceResponse(for: request)
    }
    
    func declineFileRequest(_ request: IncomingFileRequest) {
        // Remove from incoming requests
        incomingFileRequests.removeAll { $0.id == request.id }
        
        // Send decline response to sender (in real implementation)
        sendDeclineResponse(for: request)
        
        showToast("File transfer request declined", type: .info)
    }
    
    private func sendAcceptanceResponse(for request: IncomingFileRequest) {
        // In real implementation, this would send a response via WebRTC
        print("Sending acceptance response for file: \(request.fileName)")
        self.webRTCClient?.answer { (localSdp) in
            self.signalClient.send(sdp: localSdp)
        }
    }
    
    private func sendDeclineResponse(for request: IncomingFileRequest) {
        // In real implementation, this would send a response via WebRTC
        print("Sending decline response for file: \(request.fileName)")
    }
    
    func pauseDownload() {
        downloadStatus = .paused
        downloadTimer?.invalidate()
        downloadSpeedTimer?.invalidate()
    }
    
    func resumeDownload() {
        downloadStatus = .downloading
        // Note: Downloads are handled by the WebRTCFileTransferHandler
        // The actual resume logic is managed by the WebRTC layer
        // This method only updates the UI state
    }
    
    func cancelDownload() {
        downloadStatus = .idle
        isDownloading = false
        downloadProgress = 0.0
        downloadTimer?.invalidate()
        downloadSpeedTimer?.invalidate()
        currentDownload = nil
    }
    
    private func startDownload(for request: IncomingFileRequest) {
        guard let dc = webRTCClient?.localDataChannel else { return }
        webRTCFileTransferClient = WebRTCFileTransferHandler()
        webRTCFileTransferClient?.delegate = self // implement WebRTCFileTransferDelegate

        // when your dc opens (or reopens)
        webRTCFileTransferClient?.attach(dc)
        
        isDownloading = true
        downloadStatus = .downloading
        downloadProgress = 0.0
        
        // Create a mock FileInfo for the download
        let mockFile = FileInfo.mockFile(from: request)
        currentDownload = mockFile
        
        // Simulate download progress
//        downloadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
//            guard let self = self else { return }
//            
//            if self.downloadProgress < 1.0 {
//                self.downloadProgress += 0.01
//                
//                // Simulate download completion
//                if self.downloadProgress >= 1.0 {
//                    self.downloadCompleted()
//                }
//            }
//        }
        
        // Simulate download speed updates
//        startDownloadSpeedSimulation()
        
        showToast("Download started: \(request.fileName)", type: .info)
    }
    
//    private func downloadCompleted() {
//        downloadStatus = .completed
//        isDownloading = false
//        downloadTimer?.invalidate()
//        downloadSpeedTimer?.invalidate()
//        
//        showToast("File downloaded successfully!", type: .success)
//        
//        // Reset after a delay
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//            self.downloadStatus = .idle
//            self.downloadProgress = 0.0
//            self.currentDownload = nil
//        }
//    }
    
//    private func startDownloadSpeedSimulation() {
//        downloadSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
//            guard let self = self else { return }
//            
//            // Simulate varying download speeds
//            let speeds = ["150 KB/s", "300 KB/s", "600 KB/s", "1.5 MB/s", "2.5 MB/s"]
//            self.downloadSpeed = speeds.randomElement() ?? "0 KB/s"
//        }
//    }
    
    private func startIncomingRequestSimulation() {
        // Simulate incoming file requests every 15 seconds
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            
            let mockRequest = IncomingFileRequest(
                fileName: "Sample_File_\(Int.random(in: 1...1000)).pdf",
                fileSize: "\(Int.random(in: 100...5000)) KB",
                fileType: ["PDF", "DOC", "JPG", "MP4"].randomElement() ?? "PDF",
                senderId: "User_\(Int.random(in: 1...100))",
                timestamp: Date()
            )
            
            self.incomingFileRequests.append(mockRequest)
            
            // Show alert for new incoming request
            self.currentIncomingRequest = mockRequest
            self.showingIncomingRequestAlert = true
        }
    }
    
    private func displayIncomingRequest() {
        let mockRequest = IncomingFileRequest(
            fileName: "Sample_File_\(Int.random(in: 1...1000)).pdf",
            fileSize: "\(Int.random(in: 100...5000)) KB",
            fileType: ["PDF", "DOC", "JPG", "MP4"].randomElement() ?? "PDF",
            senderId: "User_\(Int.random(in: 1...100))",
            timestamp: Date()
        )
        
        self.incomingFileRequests.append(mockRequest)
        
        // Show alert for new incoming request
        self.currentIncomingRequest = mockRequest
        self.showingIncomingRequestAlert = true
    }
    
    private func showToast(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type
    }
    
    private func showFileAccessError(_ error: FileAccessError) {
        let errorMessage = error.errorDescription ?? "Unknown file access error"
        let recoveryMessage = error.recoverySuggestion ?? ""
        
        let fullMessage = "\(errorMessage)\n\n\(recoveryMessage)"
        showToast(fullMessage, type: .error)
        
        // Log the error for debugging
        print("File access error: \(errorMessage)")
        if !recoveryMessage.isEmpty {
            print("Recovery suggestion: \(recoveryMessage)")
        }
    }
    
    // MARK: - Received Files Management
    
    private func loadReceivedFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let receivedFilesURL = documentsPath.appendingPathComponent("receivedFiles.json")
        
        if let data = try? Data(contentsOf: receivedFilesURL),
           let files = try? JSONDecoder().decode([ReceivedFile].self, from: data) {
            // Filter out files that no longer exist on disk
            self.receivedFiles = files.filter { file in
                let fileExists = FileManager.default.fileExists(atPath: file.url.path)
                if !fileExists {
                    print("File no longer exists: \(file.url.path)")
                }
                return fileExists
            }
            
            // Save the filtered list back to disk
            if self.receivedFiles.count != files.count {
                saveReceivedFiles()
                print("Removed \(files.count - self.receivedFiles.count) inaccessible files")
            }
        }
    }
    
    func refreshReceivedFiles() {
        // Remove inaccessible files
        let accessibleFiles = receivedFiles.filter { isFileAccessible($0) }
        
        if accessibleFiles.count != receivedFiles.count {
            let removedCount = receivedFiles.count - accessibleFiles.count
            receivedFiles = accessibleFiles
            saveReceivedFiles()
            showToast("Removed \(removedCount) inaccessible files", type: .info)
        }
    }
    
    func checkFilePermissions() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let testFile = documentsPath.appendingPathComponent("test_permissions.txt")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            print("File permissions are working correctly")
        } catch {
            print("File permission error: \(error.localizedDescription)")
            showToast("File access permission issue detected", type: .warning)
        }
    }
    
    func validateFileAccess(url: URL) -> FileAccessError? {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .fileNotFound
        }
        
        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .fileNotReadable
        }
        
        // Check file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            guard fileSize > 0 else {
                return .fileEmpty
            }
        } catch {
            return .fileCorrupted
        }
        
        return nil
    }
    
    func checkAppPermissions() -> [String] {
        var missingPermissions: [String] = []
        
        // Check if app has access to documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if !FileManager.default.isWritableFile(atPath: documentsPath.path) {
            missingPermissions.append("Documents directory access")
        }
        
        // Check if app can create and delete files
        do {
            let testFile = documentsPath.appendingPathComponent("permission_test.tmp")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
        } catch {
            missingPermissions.append("File creation/deletion")
        }
        
        return missingPermissions
    }
    
    func showPermissionHelp() {
        let helpMessage = """
        To fix file access issues:
        
        1. Go to Settings > Privacy & Security > Files and Folders
        2. Find this app and enable "Files and Folders" access
        3. Make sure "Allow Full Disk Access" is enabled if needed
        4. Try selecting the file again
        
        If the issue persists, try:
        - Restarting the app
        - Selecting a different file
        - Moving the file to a different location
        """
        
        showToast(helpMessage, type: .info)
    }
    
    func suggestAlternativeFileLocations() -> [String] {
        return [
            "Files app (Documents folder)",
            "iCloud Drive",
            "Downloads folder",
            "Desktop folder",
            "Move file to a different location first"
        ]
    }
    
    func handleFileAccessFailure(url: URL) {
        // Check what type of error we're dealing with
        if let error = validateFileAccess(url: url) {
            showFileAccessError(error)
        } else {
            // Check app permissions
            let missingPermissions = checkAppPermissions()
            if !missingPermissions.isEmpty {
                showToast("App permissions issue detected. Please check Settings.", type: .warning)
                showPermissionHelp()
            } else {
                showToast("Unknown file access issue. Please try a different file.", type: .error)
            }
        }
    }
    
    func canAccessFile(url: URL) -> Bool {
        // Try to access the file without throwing
        guard url.startAccessingSecurityScopedResource() else {
            return false
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Check if file exists and is readable
        return FileManager.default.fileExists(atPath: url.path) &&
               FileManager.default.isReadableFile(atPath: url.path)
    }
    
    private func copyFileToLocalStorage(from sourceURL: URL) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = sourceURL.lastPathComponent
        let extrnsion = sourceURL.pathExtension
        
        // Create a unique filename to avoid conflicts
        let uniqueFileName = createUniqueFileName(fileName, fileExtension: extrnsion)
        let destinationURL = documentsPath.appendingPathComponent(uniqueFileName)
        
        print("Copying file from: \(sourceURL.path)")
        print("Copying file to: \(destinationURL.path)")
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Copy the file
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // Verify the copy was successful
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw FileAccessError.fileCopyFailed
        }
        
        print("File successfully copied to local storage: \(destinationURL.path)")
        return destinationURL
    }
    
    private func createUniqueFileName(_ originalName: String, fileExtension: String) -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileExtension = fileExtension
        let fileNameWithoutExtension = originalName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        
        var counter = 1
        var uniqueName = originalName
        
        while FileManager.default.fileExists(atPath: documentsPath.appendingPathComponent(uniqueName).path) {
            uniqueName = "\(fileNameWithoutExtension)_\(counter).\(fileExtension)"
            counter += 1
        }
        
        return uniqueName
    }
    
    private func cleanupLocalFile(_ fileURL: URL) {
        // Only clean up files in our documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        guard fileURL.path.hasPrefix(documentsPath.path) else {
            print("Not cleaning up file outside documents directory: \(fileURL.path)")
            return
        }
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                print("Cleaned up local file: \(fileURL.path)")
            }
        } catch {
            print("Failed to clean up local file: \(error.localizedDescription)")
        }
    }
    
    private func cleanupTemporaryFiles() {
        // Clean up any temporary files that might have been left behind
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            
            for item in contents {
                // Clean up temporary files that might have been left behind
                if item.lastPathComponent.contains("_temp_") || 
                   item.lastPathComponent.contains("_copy_") {
                    try FileManager.default.removeItem(at: item)
                    print("Cleaned up temporary file: \(item.lastPathComponent)")
                }
            }
        } catch {
            print("Error cleaning up temporary files: \(error.localizedDescription)")
        }
    }
    
    private func monitorUploadProgress() {
        // Monitor upload progress to detect stuck transfers
        guard uploadStatus == .transferring else { return }
        
        // Check if progress has been stuck for too long
        let currentTime = Date()
        let timeSinceLastProgress = currentTime.timeIntervalSince1970 - (uploadProgress > 0 ? currentTime.timeIntervalSince1970 : 0)
        
        if timeSinceLastProgress > 30.0 && uploadProgress > 0 && uploadProgress < 1.0 {
            print("Upload progress appears to be stuck at \(uploadProgress * 100)%")
            // Could implement retry logic here
        }
    }
    

    
    func getFileLocationType(url: URL) -> String {
        let path = url.path.lowercased()
        
        if path.contains("icloud") {
            return "iCloud Drive"
        } else if path.contains("dropbox") {
            return "Dropbox"
        } else if path.contains("googledrive") || path.contains("google drive") {
            return "Google Drive"
        } else if path.contains("onedrive") {
            return "OneDrive"
        } else if path.contains("box") {
            return "Box"
        } else if path.contains("documents") {
            return "Documents"
        } else if path.contains("downloads") {
            return "Downloads"
        } else if path.contains("desktop") {
            return "Desktop"
        } else {
            return "Unknown Location"
        }
    }
    
    func suggestFileAccessSolution(url: URL) -> String {
        let locationType = getFileLocationType(url: url)
        
        switch locationType {
        case "iCloud Drive":
            return "Try downloading the file to your device first, then select it again"
        case "Dropbox", "Google Drive", "OneDrive", "Box":
            return "Cloud storage files may have access restrictions. Try downloading to your device first"
        case "Documents", "Downloads", "Desktop":
            return "File should be accessible. Check if it's locked or in use by another app"
        default:
            return "Try moving the file to your Documents folder first"
        }
    }
    
    func showDeviceSpecificHelp() {
        let helpMessage = """
        Device-specific file access help:
        
        For iOS 14+ devices:
        1. Go to Settings > Privacy & Security > Files and Folders
        2. Enable access for this app
        
        For older iOS versions:
        1. Go to Settings > Privacy & Security > Files and Folders
        2. Make sure this app has permission
        
        Additional steps:
        - Restart the app after changing permissions
        - Try selecting a file from the Files app first
        - Check if the file is in a protected cloud location
        """
        
        showToast(helpMessage, type: .info)
    }
    
    func checkForOrphanedFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempPath = FileManager.default.temporaryDirectory
        
        // Check if there are any files in temp that should be in documents
        do {
            let tempContents = try FileManager.default.contentsOfDirectory(at: tempPath, includingPropertiesForKeys: nil)
            let documentContents = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            
            for tempFile in tempContents {
                // Check if this file exists in documents
                let fileName = tempFile.lastPathComponent
                let documentFile = documentsPath.appendingPathComponent(fileName)
                
                if !FileManager.default.fileExists(atPath: documentFile.path) {
                    // Move file from temp to documents
                    do {
                        try FileManager.default.moveItem(at: tempFile, to: documentFile)
                        print("Moved orphaned file from temp to documents: \(fileName)")
                    } catch {
                        print("Failed to move orphaned file: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("Error checking for orphaned files: \(error.localizedDescription)")
        }
    }
    
    private func setupAppLifecycleNotifications() {
        // Handle app entering background - pause uploads/downloads
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
        
        // Handle app entering foreground - resume uploads/downloads
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkForOrphanedFiles()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupTemporaryFiles()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle Handlers
    
    private func handleAppDidEnterBackground() {
        print("App entered background - pausing transfers if active")
        
        // Store current state before pausing
        wasUploadingBeforeBackground = isUploading && uploadStatus == .transferring
        wasDownloadingBeforeBackground = isDownloading && downloadStatus == .downloading
        
        // Pause upload if currently transferring
        if wasUploadingBeforeBackground {
            print("Pausing upload due to background")
            pauseUpload()
        }
        
        // Pause download if currently downloading
        if wasDownloadingBeforeBackground {
            print("Pausing download due to background")
            pauseDownload()
        }
    }
    
    private func handleAppWillEnterForeground() {
        print("App entering foreground - resuming transfers if they were active")
        
        // Resume upload if it was active before background
        if wasUploadingBeforeBackground {
            print("Resuming upload after foreground")
            resumeUpload()
        }
        
        // Resume download if it was active before background
        if wasDownloadingBeforeBackground {
            print("Resuming download after foreground")
            resumeDownload()
        }
        
        // Reset background state flags
        wasUploadingBeforeBackground = false
        wasDownloadingBeforeBackground = false
        
        // Refresh received files
        refreshReceivedFiles()
    }
    
    private func saveReceivedFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let receivedFilesURL = documentsPath.appendingPathComponent("receivedFiles.json")
        
        if let data = try? JSONEncoder().encode(receivedFiles) {
            try? data.write(to: receivedFilesURL)
        }
    }
    
    private func validateFile(_ file: ReceivedFile) -> Bool {
        let fileExists = FileManager.default.fileExists(atPath: file.url.path)
        if !fileExists {
            print("File validation failed: \(file.url.path)")
            return false
        }
        
        // Check if file is readable
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            if fileSize == 0 {
                print("File is empty or corrupted: \(file.url.path)")
                return false
            }
        } catch {
            print("File access error: \(error.localizedDescription)")
            return false
        }
        
        return true
    }
    
    private func isFileAccessible(_ file: ReceivedFile) -> Bool {
        return validateFile(file)
    }
    
    private func findFileByName(_ fileName: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            return fileURLs.first { $0.lastPathComponent == fileName }
        } catch {
            print("Error searching for file: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func findFileInDocumentsDirectory(_ fileName: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Search recursively in documents directory
        func searchRecursively(in url: URL) -> URL? {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                
                for item in contents {
                    if item.lastPathComponent == fileName {
                        return item
                    }
                    
                    // Check if it's a directory and search recursively
                    let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDirectory {
                        if let found = searchRecursively(in: item) {
                            return found
                        }
                    }
                }
            } catch {
                print("Error searching directory: \(error.localizedDescription)")
            }
            
            return nil
        }
        
        return searchRecursively(in: documentsPath)
    }
    
    private func tryToRecoverFile(_ file: ReceivedFile) -> Bool {
        // Try to find the file by name in the documents directory
        if let foundURL = findFileInDocumentsDirectory(file.name) {
            // Update the file URL
            let updatedFile = ReceivedFile(
                name: file.name,
                size: file.size,
                url: foundURL,
                type: file.type,
                senderId: file.senderId,
                fileSizeBytes: file.fileSizeBytes
            )
            
            // Replace the old file entry
            if let index = receivedFiles.firstIndex(where: { $0.id == file.id }) {
                receivedFiles[index] = updatedFile
                saveReceivedFiles()
                showToast("File recovered: \(file.name)", type: .success)
                return true
            }
        }
        return false
    }
    
    private func addReceivedFile(_ file: ReceivedFile) {
        receivedFiles.append(file)
        saveReceivedFiles()
        
        // Show file preview
        fileToPreview = file
        showingFilePreview = true
        
        showToast("File received: \(file.name)", type: .success)
    }
    
    func showFilePreview(_ file: ReceivedFile) {
        // Validate file before showing preview
        guard isFileAccessible(file) else {
            // Try to recover the file first
            if tryToRecoverFile(file) {
                // File was recovered, show it
                fileToPreview = file
                showingFilePreview = true
                return
            }
            
            // File couldn't be recovered, show error and remove it
            showToast("File is no longer accessible: \(file.name)", type: .error)
            // Remove the inaccessible file from the list
            receivedFiles.removeAll { $0.id == file.id }
            saveReceivedFiles()
            return
        }
        
        fileToPreview = file
        showingFilePreview = true
    }
    
    func deleteReceivedFile(_ file: ReceivedFile) {
        // Remove file from disk
        try? FileManager.default.removeItem(at: file.url)
        
        // Remove from array
        receivedFiles.removeAll { $0.id == file.id }
        saveReceivedFiles()
        
        showToast("File deleted: \(file.name)", type: .info)
    }
    
    // MARK: - Connection Management
    
    func disconnectWebRTC() {
        webRTCClient?.disconnect()
        webRTCClient = nil
        showToast("WebRTC connection closed", type: .info)
    }
    
    func resetConnection() {
        // Disconnect current connection
        webRTCClient?.disconnect()
//        signalClient.disconnect()
        
        // Clean up local files
        if let selectedFile = selectedFile {
            cleanupLocalFile(selectedFile.url)
            self.selectedFile = nil
        }
        
        // Reset connection state
//        isConnected = false
        uploadStatus = .idle
        downloadStatus = .idle
        uploadProgress = 0.0
        uploadSentBytes = 0
        uploadTotalBytes = 0
        uploadSpeed = "0 KB/s"
        downloadProgress = 0.0
        
        // Clear current transfers
        currentDownload = nil
        pendingFileRequests.removeAll()
        incomingFileRequests.removeAll()
        
        showToast("Connection reset", type: .info)
    }
    
    func getConnectionStatus() -> String {
        if isConnected {
            if uploadStatus == .idle && downloadStatus == .idle {
                return "Ready for Transfer"
            } else if uploadStatus == .transferring {
                return "Uploading..."
            } else if downloadStatus == .downloading {
                return "Downloading..."
            } else if uploadStatus == .completed || downloadStatus == .completed {
                return "Transfer Complete"
            } else if uploadStatus == .failed || downloadStatus == .failed {
                return "Transfer Failed"
            } else {
                return "Connected"
            }
        } else {
            return "Disconnected"
        }
    }
    
    func isConnectionReady() -> Bool {
        return isConnected && uploadStatus == .idle && downloadStatus == .idle
    }
    
    func canStartNewTransfer() -> Bool {
        return isConnected && uploadStatus == .idle && downloadStatus == .idle
    }
    
    func getTransferQueueStatus() -> String {
        if uploadStatus == .transferring {
            return "Upload in progress"
        } else if downloadStatus == .downloading {
            return "Download in progress"
        } else if uploadStatus == .completed || downloadStatus == .completed {
            return "Transfer completed, ready for next"
        } else if uploadStatus == .failed || downloadStatus == .failed {
            return "Transfer failed, ready to retry"
        } else {
            return "Ready for transfer"
        }
    }
    
    var uploadProgressFormatted: String {
        let percentage = Int(uploadProgress * 100)
        let sentMB = Double(uploadSentBytes) / (1024 * 1024)
        let totalMB = Double(uploadTotalBytes) / (1024 * 1024)
        return "\(percentage)% (\(String(format: "%.1f", sentMB)) MB / \(String(format: "%.1f", totalMB)) MB)"
    }
    
    var uploadProgressDetails: String {
        let percentage = Int(uploadProgress * 100)
        let sentFormatted = ByteCountFormatter.string(fromByteCount: uploadSentBytes, countStyle: .file)
        let totalFormatted = ByteCountFormatter.string(fromByteCount: uploadTotalBytes, countStyle: .file)
        return "\(percentage)% (\(sentFormatted) / \(totalFormatted))"
    }
}

// File Information Model
struct FileInfo: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let url: URL
    let type: String
    let previewImage: UIImage?
    
    init(url: URL) throws {
        self.url = url
        self.name = url.lastPathComponent
        
        // Validate file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAccessError.fileNotFound
        }
        
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FileAccessError.fileNotReadable
        }
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize > 0 else {
            throw FileAccessError.fileEmpty
        }
        
        self.size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        
        // Get file type
        self.type = url.pathExtension.isEmpty ? "Unknown" : url.pathExtension.uppercased()
        
        // Generate preview image for supported types (don't fail if this fails)
        self.previewImage = url.generatePreviewImage()
    }
    
    init(name: String,
         size: String,
         url: URL,
         type: String,
         previewImage: UIImage?) {
        self.name = name
        self.size = size
        self.url = url
        self.type = type
        self.previewImage = previewImage
    }
    
    // Mock file for downloads
    static func mockFile(from request: IncomingFileRequest) -> FileInfo {
        let mockURL = URL(fileURLWithPath: "/mock/\(request.fileName)")
        let mockFile = FileInfo(
            name: request.fileName,
            size: request.fileSize,
            url: mockURL,
            type: request.fileType,
            previewImage: nil
        )
        return mockFile
    }
}

// Received File Model for tracking downloaded files
struct ReceivedFile: Identifiable, Codable {
    var id = UUID()
    let name: String
    let size: String
    let url: URL
    let type: String
    let receivedAt: Date
    let senderId: String
    let fileSizeBytes: Int64
    
    init(name: String, size: String, url: URL, type: String, senderId: String, fileSizeBytes: Int64) {
        self.name = name
        self.size = size
        self.url = url
        self.type = type
        self.receivedAt = Date()
        self.senderId = senderId
        self.fileSizeBytes = fileSizeBytes
    }
    
    // Create from FileInfo
    init(from fileInfo: FileInfo, senderId: String, fileSizeBytes: Int64) {
        self.name = fileInfo.name
        self.size = fileInfo.size
        self.url = fileInfo.url
        self.type = fileInfo.type
        self.receivedAt = Date()
        self.senderId = senderId
        self.fileSizeBytes = fileSizeBytes
    }
    
    // Codable conformance for URL
    enum CodingKeys: String, CodingKey {
        case id, name, size, url, type, receivedAt, senderId, fileSizeBytes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(String.self, forKey: .size)
        let urlString = try container.decode(String.self, forKey: .url)
        // Create URL from the stored path
        let url = URL(fileURLWithPath: urlString)
        self.url = url
        type = try container.decode(String.self, forKey: .type)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        senderId = try container.decode(String.self, forKey: .senderId)
        fileSizeBytes = try container.decode(Int64.self, forKey: .fileSizeBytes)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(url.path, forKey: .url)
        try container.encode(type, forKey: .type)
        try container.encode(receivedAt, forKey: .receivedAt)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(fileSizeBytes, forKey: .fileSizeBytes)
    }
}

extension URL {
    var fileSize: Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    func generatePreviewImage() -> UIImage? {
        let fileExtension = self.pathExtension.lowercased()
        
        // For images, return the image itself
        if ["jpg", "jpeg", "png", "gif", "heic"].contains(fileExtension) {
            return UIImage(contentsOfFile: self.path)
        }
        
        // For other file types, return a system icon
        let systemImageName: String
        switch fileExtension {
        case "pdf":
            systemImageName = "doc.text"
        case "doc", "docx":
            systemImageName = "doc.text"
        case "xls", "xlsx":
            systemImageName = "tablecells"
        case "ppt", "pptx":
            systemImageName = "chart.bar.doc.horizontal"
        case "mp4", "mov", "avi":
            systemImageName = "video"
        case "mp3", "wav", "aac":
            systemImageName = "music.note"
        case "txt":
            systemImageName = "doc.text"
        default:
            systemImageName = "doc"
        }
        
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        return UIImage(systemName: systemImageName, withConfiguration: config)
    }
}

extension FileSharingManager: SignalClientDelegate {
    func signalClientDidConnect(_ signalClient: SignalingClient) {
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    
    func signalClientDidDisconnect(_ signalClient: SignalingClient) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.showToast("Signaling server disconnected", type: .warning)
        }
    }
    
    func signalClient(_ signalClient: SignalingClient, didReceiveRemoteSdp sdp: RTCSessionDescription) {
        print("Received remote sdp")
        self.initializeWebRTCClient()
        self.webRTCClient?.set(remoteSdp: sdp) { (error) in
//            self.hasRemoteSdp = true
            DispatchQueue.main.async {
                if let request = self.pendingFileRequests.first {
//                    self.handleFileRequestAccepted(request)
                } else {
                    self.displayIncomingRequest()
                }
            }
        }
    }
    
    func signalClient(_ signalClient: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate) {
        self.webRTCClient?.set(remoteCandidate: candidate) { error in
            print("Received remote candidate")
//            self.remoteCandidateCount += 1
        }
    }
}

extension FileSharingManager: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            print("dataChannel updated")
            if let request = self.pendingFileRequests.last {
//                guard let dataToSend = "Hi this is the start".data(using: .utf8) else {
//                    return
//                }
//                self.webRTCClient.sendData(dataToSend)
                self.handleFileRequestAccepted(request)
            } else if let request = self.currentIncomingRequest {
                self.startDownload(for: request)
            }
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        print("discovered local candidate")
        self.signalClient.send(candidate: candidate)
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        let textColor: UIColor
        switch state {
        case .connected, .completed:
            textColor = .green
            DispatchQueue.main.async {
                self.isConnected = true
            }
            
        case .disconnected:
            textColor = .orange
            DispatchQueue.main.async {
                self.showToast("WebRTC connection lost", type: .warning)
            }
        case .failed, .closed:
            textColor = .red
            // Update connection status when connection is closed
            DispatchQueue.main.async {
                self.showToast("WebRTC connection closed", type: .info)
            }
        case .new, .checking, .count:
            textColor = .black
        @unknown default:
            textColor = .black
        }
        print("WebRTC Status: \(state.description.capitalized)")
//        DispatchQueue.main.async {
//            self.webRTCStatusLabel?.text = state.description.capitalized
//            self.webRTCStatusLabel?.textColor = textColor
//        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {
        DispatchQueue.main.async {
            let message = String(data: data, encoding: .utf8) ?? "(Binary: \(data.count) bytes)"
            print("message received \(message)")
//            let alert = UIAlertController(title: "Message from WebRTC", message: message, preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
//            self.present(alert, animated: true, completion: nil)
        }
    }
}

extension FileSharingManager: WebRTCFileTransferDelegate {
    // MARK: - Sender (Uploader) Methods
    
    func uploadStarted(fileId: String, name: String, size: Int) {
        DispatchQueue.main.async {
            self.uploadStatus = .transferring
            self.isUploading = true
            self.uploadProgress = 0.0
            self.uploadTotalBytes = Int64(size)
            self.uploadSentBytes = 0
            self.showToast("Upload started: \(name)", type: .info)
            
            print("Upload started: \(name), size: \(size) bytes")
        }
    }
    
    func uploadProgress(fileId: String, sentBytes: Int, totalBytes: Int, speedBps: Double, etaSeconds: Double?) {
        DispatchQueue.main.async {
            // Validate the progress values
            guard totalBytes > 0, sentBytes >= 0, sentBytes <= totalBytes else {
                print("Invalid progress values: sentBytes=\(sentBytes), totalBytes=\(totalBytes)")
                return
            }
            
            // Store the current values
            self.uploadSentBytes = Int64(sentBytes)
            self.uploadTotalBytes = Int64(totalBytes)
            
            // Calculate progress
            let progress = Double(sentBytes) / Double(totalBytes)
            
            // Validate progress is reasonable
            if progress.isNaN || progress.isInfinite {
                print("Invalid progress calculation: \(progress)")
                return
            }
            
            // Update progress (now properly calculated from acknowledged chunks)
            self.uploadProgress = progress
            
            // Update speed
            self.uploadSpeed = ByteCountFormatter.string(fromByteCount: Int64(speedBps), countStyle: .file) + "/s"
            
            print("Upload Progress: \(sentBytes)/\(totalBytes) = \(progress * 100)%")
        }
    }
    
    func uploadPaused(fileId: String) {
        DispatchQueue.main.async {
            self.uploadStatus = .paused
            self.showToast("Upload paused", type: .warning)
        }
    }
    
    func uploadResumed(fileId: String) {
        DispatchQueue.main.async {
            self.uploadStatus = .transferring
            self.showToast("Upload resumed", type: .info)
        }
    }
    
    func uploadCompleted(fileId: String) {
        DispatchQueue.main.async {
            self.uploadStatus = .completed
            self.isUploading = false
            self.uploadProgress = 1.0
            self.showToast("Upload completed successfully!", type: .success)
            
            // Clean up the local copy of the file
            if let selectedFile = self.selectedFile {
                self.cleanupLocalFile(selectedFile.url)
                self.selectedFile = nil
            }
            
            // Keep WebRTC connection open for future transfers
            self.disconnectWebRTC()
            
            // Reset after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.pendingFileRequests.removeAll()
                self.incomingFileRequests.removeAll()
                self.uploadStatus = .idle
                self.uploadProgress = 0.0
                self.uploadSpeed = "0 KB/s"
            }
        }
    }
    
    func uploadFailed(fileId: String, error: Error) {
        DispatchQueue.main.async {
            self.uploadStatus = .failed
            self.isUploading = false
            self.showToast("Upload failed: \(error.localizedDescription)", type: .error)
            
            // Clean up the local copy of the file
            if let selectedFile = self.selectedFile {
                self.cleanupLocalFile(selectedFile.url)
                self.selectedFile = nil
            }
            
            // Keep WebRTC connection open even after failed upload
            // self.webRTCClient.disconnect() // Removed automatic disconnection
            
            // Reset after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.uploadStatus = .idle
                self.uploadProgress = 0.0
                self.uploadSpeed = "0 KB/s"
            }
        }
    }
    
    // MARK: - Receiver (Downloader) Methods
    
    func downloadPrepared(fileId: String, name: String, size: Int, tempURL: URL) {
        DispatchQueue.main.async {
            self.downloadStatus = .downloading
            self.isDownloading = true
            self.downloadProgress = 0.0
            self.downloadSpeed = "0 KB/s"
            self.lastDownloadBytesForSpeed = 0
            self.lastDownloadTimestamp = Date()
            
            // Create a FileInfo for the download
            let fileInfo = FileInfo(
                name: name,
                size: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                url: tempURL,
                type: tempURL.pathExtension.isEmpty ? "Unknown" : tempURL.pathExtension.uppercased(),
                previewImage: nil
            )
            self.currentDownload = fileInfo
            
            self.showToast("Download started: \(name)", type: .info)
        }
    }
    
    func downloadProgress(fileId: String, receivedBytes: Int, totalBytes: Int) {
        DispatchQueue.main.async {
            self.downloadProgress = Double(receivedBytes) / Double(totalBytes)
            
            // Calculate instantaneous speed based on delta since last update
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastDownloadTimestamp)
            if elapsed > 0.15 { // throttle updates ~6+ times/sec
                let deltaBytes = max(0, receivedBytes - self.lastDownloadBytesForSpeed)
                let bps = elapsed > 0 ? Double(deltaBytes) / elapsed : 0
                self.downloadSpeed = ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
                self.lastDownloadBytesForSpeed = receivedBytes
                self.lastDownloadTimestamp = now
            }
        }
    }
    
    
    func downloadCompleted(fileId: String, finalURL: URL) {
        DispatchQueue.main.async {
            self.downloadStatus = .completed
            self.isDownloading = false
            self.downloadProgress = 1.0
            
            // Create ReceivedFile and add to history
            let fileInfo = FileInfo(
                name: finalURL.lastPathComponent,
                size: ByteCountFormatter.string(fromByteCount: finalURL.fileSize, countStyle: .file),
                url: finalURL,
                type: finalURL.pathExtension.isEmpty ? "Unknown" : finalURL.pathExtension.uppercased(),
                previewImage: finalURL.generatePreviewImage()
            )
            
            let receivedFile = ReceivedFile(
                from: fileInfo,
                senderId: "Unknown Sender", // In real app, this would come from the sender
                fileSizeBytes: finalURL.fileSize
            )
            
            self.addReceivedFile(receivedFile)
            
            self.disconnectWebRTC()
            
            // Reset download state
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.pendingFileRequests.removeAll()
                self.incomingFileRequests.removeAll()
                self.downloadStatus = .idle
                self.downloadProgress = 0.0
                self.downloadSpeed = "0 KB/s"
                self.currentDownload = nil
            }
        }
    }
    
    func downloadFailed(fileId: String, error: Error) {
        DispatchQueue.main.async {
            self.downloadStatus = .failed
            self.isDownloading = false
            self.showToast("Download failed: \(error.localizedDescription)", type: .error)
            
            // Keep WebRTC connection open even after failed download
            // self.webRTCClient.disconnect() // Removed automatic disconnection
            
            // Reset after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.downloadStatus = .idle
                self.downloadProgress = 0.0
                self.downloadSpeed = "0 KB/s"
                self.currentDownload = nil
            }
        }
    }
}

