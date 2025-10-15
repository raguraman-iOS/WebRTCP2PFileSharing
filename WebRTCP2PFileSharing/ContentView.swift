//
//  ContentView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var fileSharingManager = FileSharingManager()
    @State private var showingFilePicker = false
    @State private var showingImagePicker = false
    @State private var showingSharingOptions = false
    @State private var selectedImage: UIImage?
    @State private var isProcessingMedia = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .success
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Main File Sharing Tab
            mainFileSharingView
                .tabItem {
                    Image(systemName: "folder.badge.plus")
                    Text("Share")
                }
                .tag(0)
            
            // Received Files History Tab
            ReceivedFilesHistoryView(fileSharingManager: fileSharingManager)
                .tabItem {
                    Image(systemName: "tray")
                    Text("Received")
                }
                .tag(1)
        }
        .onReceive(fileSharingManager.$toastMessage) { message in
            if let message = message {
                showToast(message, type: fileSharingManager.toastType)
            }
        }
        .sheet(isPresented: $fileSharingManager.showingFilePreview) {
            if let file = fileSharingManager.fileToPreview {
                FilePreviewView(file: file)
                    .onDisappear {
                        fileSharingManager.fileToPreview = nil
                    }
            }
        }
        .sheet(isPresented: $fileSharingManager.showingIncomingRequestAlert) {
            if let request = fileSharingManager.currentIncomingRequest {
                if #available(iOS 16.0, *) {
                    IncomingFileRequestAlert(
                        request: request,
                        onAccept: {
                            fileSharingManager.acceptFileRequest(request)
                            fileSharingManager.showingIncomingRequestAlert = false
                        },
                        onDecline: {
                            fileSharingManager.declineFileRequest(request)
                            fileSharingManager.showingIncomingRequestAlert = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    IncomingFileRequestAlert(
                        request: request,
                        onAccept: {
                            fileSharingManager.acceptFileRequest(request)
                            fileSharingManager.showingIncomingRequestAlert = false
                        },
                        onDecline: {
                            fileSharingManager.declineFileRequest(request)
                            fileSharingManager.showingIncomingRequestAlert = false
                        }
                    )
                }
            }
        }
        .overlay(
            // Toast Notification
            ToastView(
                message: toastMessage,
                type: toastType,
                isShowing: $showingToast
            )
            .animation(.easeInOut(duration: 0.3), value: showingToast)
        )
    }
    
    // MARK: - Main File Sharing View
    
    private var mainFileSharingView: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status Header
                ConnectionStatusView(
                    isOnline: fileSharingManager.isConnected,
                    onDisconnect: {
                        fileSharingManager.disconnectWebRTC()
                    },
                    connectionStatus: fileSharingManager.getConnectionStatus()
                )
                
                // Main Content
                if fileSharingManager.isConnected {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Start File Sharing Button (Sender Mode)
                            VStack(spacing: 12) {
                                Text("Send Files")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Button(action: {
                                    showingSharingOptions = true
                                }) {
                                    HStack {
                                        Image(systemName: "folder.badge.plus")
                                            .font(.title2)
                                        Text("Start File Sharing")
                                            .font(.headline)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(fileSharingManager.canStartNewTransfer() ? Color.blue : Color.gray)
                                    .cornerRadius(12)
                                }
                                .disabled(!fileSharingManager.canStartNewTransfer())
                            }
                            
                            // Media Processing Status
                            if isProcessingMedia {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Processing media...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            
                            // File Info Display (if sending)
//                            if let selectedFile = fileSharingManager.selectedFile {
//                                FileInfoView(file: selectedFile)
//                            }
                            
                            // Pending File Requests (if any)
                            if !fileSharingManager.pendingFileRequests.isEmpty {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Pending Requests")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        
                                        Text("\(fileSharingManager.pendingFileRequests.count)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(Color.blue.opacity(0.1))
                                            )
                                            .foregroundColor(.blue)
                                    }
                                    
                                    ForEach(fileSharingManager.pendingFileRequests) { request in
                                        PendingFileRequestRow(request: request)
                                    }
                                }
                            }
                            
                            // Upload Progress (if uploading)
                            if fileSharingManager.isUploading {
                                UploadProgressView(
                                    progress: fileSharingManager.uploadProgress,
                                    status: fileSharingManager.uploadStatus,
                                    speed: fileSharingManager.uploadSpeed,
                                    fileManager: fileSharingManager
                                )
                            }
                            
                            // Download Progress (if downloading)
                            if fileSharingManager.isDownloading, let downloadFile = fileSharingManager.currentDownload {
                                DownloadProgressView(
                                    progress: fileSharingManager.downloadProgress,
                                    status: fileSharingManager.downloadStatus,
                                    speed: fileSharingManager.downloadSpeed,
                                    fileName: downloadFile.name,
                                    fileManager: fileSharingManager
                                )
                            }
                            
                            // Incoming File Requests Section
                            if !fileSharingManager.incomingFileRequests.isEmpty {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Incoming Requests")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        
                                        Text("\(fileSharingManager.incomingFileRequests.count)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(Color.orange.opacity(0.1))
                                            )
                                            .foregroundColor(.orange)
                                    }
                                    
                                    Text("New file transfer requests will appear as alerts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 8)
                                }
                            }
                            
                            // Quick Access to Received Files
                            if !fileSharingManager.receivedFiles.isEmpty {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Recent Files")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        
                                        Button("View All") {
                                            selectedTab = 1
                                        }
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    }
                                    
                                    // Show last 3 received files
                                    ForEach(Array(fileSharingManager.receivedFiles.prefix(3))) { file in
                                        Button(action: {
                                            fileSharingManager.showFilePreview(file)
                                        }) {
                                            HStack(spacing: 12) {
                                                // File Icon
                                                Image(systemName: fileIconName(for: file.type))
                                                    .font(.title3)
                                                    .foregroundColor(.blue)
                                                    .frame(width: 32, height: 32)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(Color.blue.opacity(0.1))
                                                    )
                                                
                                                // File Info
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(file.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                    
                                                    HStack {
                                                        Text(file.size)
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        
                                                        Text("•")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        
                                                        Text(formatDate(file.receivedAt))
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color(.systemGray6))
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    // Offline State
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("You're offline")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("Please check your connection and try again")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("P2P File Sharing")
            .navigationBarTitleDisplayMode(.large)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data, .image, .movie, .audio, .text, .pdf, .plainText, .archive],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Start accessing the security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        showToast("Permission denied to access this file", type: .error)
                        return
                    }
                    
                    // Process the file with proper error handling
                    do {
                        try fileSharingManager.selectFile(url: url)
                    } catch {
                        showToast("Failed to process file: \(error.localizedDescription)", type: .error)
                    }
                    
                    // Stop accessing the security-scoped resource
                    url.stopAccessingSecurityScopedResource()
                }
            case .failure(let error):
                showToast("Failed to select file: \(error.localizedDescription)", type: .error)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                selectedImage: $selectedImage, 
                fileSharingManager: fileSharingManager,
                onProcessingStart: {
                    isProcessingMedia = true
                },
                onProcessingComplete: {
                    isProcessingMedia = false
                }
            )
        }
        .confirmationDialog(
            "Choose Sharing Type",
            isPresented: $showingSharingOptions,
            titleVisibility: .visible
        ) {
            Button("Share File") {
                showingFilePicker = true
            }
            
            Button("Share Photo/Video") {
                showingImagePicker = true
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Select what you want to share")
        }
    }
    
    // MARK: - Helper Methods
    
    private func fileIconName(for fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf":
            return "doc.text"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo"
        case "mp4", "mov", "avi":
            return "video"
        case "mp3", "wav", "aac":
            return "music.note"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "chart.bar.doc.horizontal"
        case "ppt", "pptx":
            return "chart.bar"
        case "txt":
            return "doc.plaintext"
        case "zip", "rar", "7z":
            return "archivebox"
        default:
            return "doc"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func showToast(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        showingToast = true
        
        // Auto-hide toast after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showingToast = false
        }
    }
}

// Incoming File Request Row Component
struct IncomingFileRequestRow: View {
    let request: IncomingFileRequest
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // File Type Icon
                Image(systemName: fileTypeIcon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                
                // File Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(request.fileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("From: \(request.senderId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Time and Arrow
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeAgoString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var fileTypeIcon: String {
        let fileExtension = request.fileType.lowercased()
        
        switch fileExtension {
        case "pdf":
            return "doc.text"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "tablecells"
        case "ppt", "pptx":
            return "chart.bar.doc.horizontal"
        case "mp4", "mov", "avi":
            return "video"
        case "mp3", "wav", "aac":
            return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo"
        case "txt":
            return "doc.text"
        default:
            return "doc"
        }
    }
    
    private var timeAgoString: String {
        let timeInterval = Date().timeIntervalSince(request.timestamp)
        
        if timeInterval < 60 {
            return "Now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    let fileSharingManager: FileSharingManager
    let onProcessingStart: () -> Void
    let onProcessingComplete: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
                // Convert image to file and share it
                parent.processSelectedImage(image)
            } else if let videoURL = info[.mediaURL] as? URL {
                // Handle video selection
                parent.processSelectedVideo(videoURL)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
    
    private func processSelectedImage(_ image: UIImage) {
        // Notify that processing has started
        onProcessingStart()
        
        // Convert image to file and share it
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to JPEG data")
            onProcessingComplete()
            return
        }
        
        // Create a temporary file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "shared_image_\(Date().timeIntervalSince1970).jpg"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        print("ImagePicker: Saving image to: \(fileURL.path)")
        
        do {
            try imageData.write(to: fileURL)
            print("ImagePicker: Image saved successfully")
            
            // Verify the file was created
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("ImagePicker: File was not created after saving")
                onProcessingComplete()
                return
            }
            
            // Get file size for verification
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("ImagePicker: Saved file size: \(fileSize) bytes")
            
            // Now share the file using the file sharing manager
            DispatchQueue.main.async {
                do {
                    print("ImagePicker: Attempting to share file: \(fileURL.path)")
                    try self.fileSharingManager.selectFile(url: fileURL)
                    print("ImagePicker: File sharing initiated successfully")
                    self.onProcessingComplete()
                } catch {
                    print("ImagePicker: Failed to share image: \(error)")
                    print("ImagePicker: Error details: \(error.localizedDescription)")
                    self.onProcessingComplete()
                }
            }
        } catch {
            print("ImagePicker: Failed to save image: \(error)")
            onProcessingComplete()
        }
    }
    
    private func processSelectedVideo(_ videoURL: URL) {
        // Notify that processing has started
        onProcessingStart()
        
        print("ImagePicker: Processing video from: \(videoURL.path)")
        
        // Handle video selection - copy to documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "shared_video_\(Date().timeIntervalSince1970).mov"
        let destinationURL = documentsPath.appendingPathComponent(fileName)
        
        print("ImagePicker: Copying video to: \(destinationURL.path)")
        
        do {
            try FileManager.default.copyItem(at: videoURL, to: destinationURL)
            print("ImagePicker: Video copied successfully")
            
            // Verify the file was copied
            guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                print("ImagePicker: Video file was not copied successfully")
                onProcessingComplete()
                return
            }
            
            // Get file size for verification
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("ImagePicker: Copied video file size: \(fileSize) bytes")
            
            // Now share the video file using the file sharing manager
            DispatchQueue.main.async {
                do {
                    print("ImagePicker: Attempting to share video: \(destinationURL.path)")
                    try self.fileSharingManager.selectFile(url: destinationURL)
                    print("ImagePicker: Video sharing initiated successfully")
                    self.onProcessingComplete()
                } catch {
                    print("ImagePicker: Failed to share video: \(error)")
                    print("ImagePicker: Error details: \(error.localizedDescription)")
                    self.onProcessingComplete()
                }
            }
        } catch {
            print("ImagePicker: Failed to copy video: \(error)")
            onProcessingComplete()
        }
    }
}
