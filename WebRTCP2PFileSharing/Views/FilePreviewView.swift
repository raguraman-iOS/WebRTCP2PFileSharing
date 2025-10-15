//
//  FilePreviewView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct FilePreviewView: View {
    let file: ReceivedFile
    @Environment(\.dismiss) private var dismiss
    @State private var showingQuickLook = false
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @State private var fileAccessError: String?
    @State private var isFileAccessible = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // File Header
                    VStack(spacing: 16) {
                        // File Icon/Preview
                        fileIconView
                        
                        // File Details
                        VStack(spacing: 8) {
                            Text(file.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                            
                            Text(file.size)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(file.type.uppercased())
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.1))
                                )
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // File Information
                    fileInfoSection
                    
                    // Action Buttons (only show if file is accessible)
                    if isFileAccessible {
                        actionButtonsSection
                    } else {
                        fileAccessErrorSection
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("File Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingQuickLook) {
            QuickLookPreviewWithNavigation(url: file.url)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [file.url])
        }
        .alert("Delete File", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteFile()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete '\(file.name)'? This action cannot be undone.")
        }
        .onAppear {
            checkFileAccessibility()
        }
    }
    
    // MARK: - File Icon View
    
    @ViewBuilder
    private var fileIconView: some View {
        if let previewImage = generatePreviewImage() {
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: fileIconName)
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                )
        }
    }
    
    // MARK: - File Info Section
    
    private var fileInfoSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("File Information")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            VStack(spacing: 12) {
                infoRow(title: "Name", value: file.name)
                infoRow(title: "Size", value: file.size)
                infoRow(title: "Type", value: file.type.uppercased())
                infoRow(title: "Received", value: formatDate(file.receivedAt))
                infoRow(title: "From", value: file.senderId)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Preview Button
            Button(action: {
                showingQuickLook = true
            }) {
                HStack {
                    Image(systemName: "eye")
                        .font(.title3)
                    Text("Preview File")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            
            // Share Button
            Button(action: {
                showingShareSheet = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    Text("Share File")
                        .font(.headline)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Delete Button
            Button(action: {
                showingDeleteAlert = true
            }) {
                HStack {
                    Image(systemName: "trash")
                        .font(.title3)
                    Text("Delete File")
                        .font(.headline)
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - File Access Error Section
    
    private var fileAccessErrorSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("File Not Accessible")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let error = fileAccessError {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Text("The file may have been moved, deleted, or corrupted.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                checkFileAccessibility()
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    // MARK: - Helper Methods
    
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func generatePreviewImage() -> UIImage? {
        // Try to generate a preview image for supported file types
        return file.url.generatePreviewImage()
    }
    
    private var fileIconName: String {
        switch file.type.lowercased() {
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
    
    private func deleteFile() {
        // This will be handled by the parent view
        dismiss()
    }
    
    private func checkFileAccessibility() {
        // Check if file exists and is accessible
        let fileExists = FileManager.default.fileExists(atPath: file.url.path)
        
        if !fileExists {
            isFileAccessible = false
            fileAccessError = "File not found at expected location"
            return
        }
        
        // Check if file is readable
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            if fileSize == 0 {
                isFileAccessible = false
                fileAccessError = "File appears to be empty or corrupted"
                return
            }
        } catch {
            isFileAccessible = false
            fileAccessError = "Cannot access file: \(error.localizedDescription)"
            return
        }
        
        isFileAccessible = true
        fileAccessError = nil
    }
}

// MARK: - QuickLook Preview

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        
        // Add Done button to navigation bar
        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismissPreview)
        )
        controller.navigationItem.rightBarButtonItem = doneButton
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(url: url, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let dismiss: DismissAction
        
        init(url: URL, dismiss: DismissAction) {
            self.url = url
            self.dismiss = dismiss
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
        
        @objc func dismissPreview() {
            dismiss()
        }
    }
}

// Wrapper to provide navigation bar
struct QuickLookPreviewWithNavigation: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            QuickLookPreview(url: url)
                .navigationTitle("File Preview")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.blue)
                        .font(.headline)
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let sampleFile = ReceivedFile(
        name: "Sample Document.pdf",
        size: "2.5 MB",
        url: URL(fileURLWithPath: "/sample/document.pdf"),
        type: "pdf",
        senderId: "John Doe",
        fileSizeBytes: 2621440
    )
    
    FilePreviewView(file: sampleFile)
}
