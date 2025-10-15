//
//  ReceivedFilesHistoryView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct ReceivedFilesHistoryView: View {
    @ObservedObject var fileSharingManager: FileSharingManager
    @State private var searchText = ""
    @State private var selectedFilter: FileFilter = .all
    @State private var showingSortOptions = false
    @State private var sortOrder: SortOrder = .dateDescending
    
    enum FileFilter: String, CaseIterable {
        case all = "All"
        case images = "Images"
        case documents = "Documents"
        case videos = "Videos"
        case audio = "Audio"
        case archives = "Archives"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .all: return "folder"
            case .images: return "photo"
            case .documents: return "doc.text"
            case .videos: return "video"
            case .audio: return "music.note"
            case .archives: return "archivebox"
            case .other: return "doc"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case nameAscending = "Name A-Z"
        case nameDescending = "Name Z-A"
        case sizeDescending = "Largest First"
        case sizeAscending = "Smallest First"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                searchAndFilterBar
                
                // File Count
                fileCountSection
                
                // Files List
                if fileSharingManager.receivedFiles.isEmpty {
                    emptyStateView
                } else {
                    filesListView
                }
            }
            .navigationTitle("Received Files")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {
                            fileSharingManager.refreshReceivedFiles()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        
                        Button(action: {
                            showingSortOptions = true
                        }) {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
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
        .actionSheet(isPresented: $showingSortOptions) {
            ActionSheet(
                title: Text("Sort Files"),
                buttons: SortOrder.allCases.map { order in
                    .default(Text(order.rawValue)) {
                        sortOrder = order
                    }
                } + [.cancel()]
            )
        }
    }
    
    // MARK: - Search and Filter Bar
    
    private var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FileFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            filter: filter,
                            isSelected: selectedFilter == filter,
                            action: {
                                selectedFilter = filter
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - File Count Section
    
    private var fileCountSection: some View {
        HStack {
            Text("\(filteredFiles.count) file\(filteredFiles.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if selectedFilter != .all {
                Button("Clear Filter") {
                    selectedFilter = .all
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Files Received")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("Files you receive will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Files List View
    
    private var filesListView: some View {
        List {
            ForEach(filteredFiles) { file in
                ReceivedFileRow(
                    file: file,
                    onTap: {
                        fileSharingManager.showFilePreview(file)
                    },
                    onDelete: {
                        fileSharingManager.deleteReceivedFile(file)
                    }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Computed Properties
    
    private var filteredFiles: [ReceivedFile] {
        var files = fileSharingManager.receivedFiles
        
        // Apply search filter
        if !searchText.isEmpty {
            files = files.filter { file in
                file.name.localizedCaseInsensitiveContains(searchText) ||
                file.type.localizedCaseInsensitiveContains(searchText) ||
                file.senderId.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply type filter
        if selectedFilter != .all {
            files = files.filter { file in
                switch selectedFilter {
                case .images:
                    return ["jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff"].contains(file.type.lowercased())
                case .documents:
                    return ["pdf", "doc", "docx", "txt", "rtf", "pages"].contains(file.type.lowercased())
                case .videos:
                    return ["mp4", "mov", "avi", "mkv", "wmv", "flv"].contains(file.type.lowercased())
                case .audio:
                    return ["mp3", "wav", "aac", "flac", "m4a"].contains(file.type.lowercased())
                case .archives:
                    return ["zip", "rar", "7z", "tar", "gz"].contains(file.type.lowercased())
                case .other:
                    return !["jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff", "pdf", "doc", "docx", "txt", "rtf", "pages", "mp4", "mov", "avi", "mkv", "wmv", "flv", "mp3", "wav", "aac", "flac", "m4a", "zip", "rar", "7z", "tar", "gz"].contains(file.type.lowercased())
                default:
                    return true
                }
            }
        }
        
        // Apply sorting
        switch sortOrder {
        case .dateDescending:
            files.sort { $0.receivedAt > $1.receivedAt }
        case .dateAscending:
            files.sort { $0.receivedAt < $1.receivedAt }
        case .nameAscending:
            files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .sizeDescending:
            files.sort { $0.fileSizeBytes > $1.fileSizeBytes }
        case .sizeAscending:
            files.sort { $0.fileSizeBytes < $1.fileSizeBytes }
        }
        
        return files
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let filter: ReceivedFilesHistoryView.FileFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Received File Row

struct ReceivedFileRow: View {
    let file: ReceivedFile
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // File Icon
                fileIconView
                
                // File Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 12) {
                        Text(file.size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(file.type.uppercased())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.1))
                            )
                            .foregroundColor(.blue)
                    }
                    
                    HStack(spacing: 8) {
                        Text("From: \(file.senderId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatDate(file.receivedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Action Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var fileIconView: some View {
        if let previewImage = file.url.generatePreviewImage() {
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: fileIconName)
                        .font(.title2)
                        .foregroundColor(.gray)
                )
        }
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    let manager = FileSharingManager()
    
    // Add some sample files
    let sampleFiles = [
        ReceivedFile(name: "Document.pdf", size: "2.5 MB", url: URL(fileURLWithPath: "/sample/doc.pdf"), type: "pdf", senderId: "John Doe", fileSizeBytes: 2621440),
        ReceivedFile(name: "Photo.jpg", size: "1.2 MB", url: URL(fileURLWithPath: "/sample/photo.jpg"), type: "jpg", senderId: "Jane Smith", fileSizeBytes: 1258291),
        ReceivedFile(name: "Video.mp4", size: "15.7 MB", url: URL(fileURLWithPath: "/sample/video.mp4"), type: "mp4", senderId: "Bob Johnson", fileSizeBytes: 16448256)
    ]
    
    manager.receivedFiles = sampleFiles
    
    return ReceivedFilesHistoryView(fileSharingManager: manager)
}
