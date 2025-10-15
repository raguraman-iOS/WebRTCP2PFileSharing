//
//  DownloadProgressView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct DownloadProgressView: View {
    let progress: Double
    let status: DownloadStatus
    let speed: String
    let fileName: String
    @ObservedObject var fileManager: FileSharingManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Download Progress")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                
                // Status Badge
                DownloadStatusBadge(status: status)
            }
            
            // File Name
            Text(fileName)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            // Progress Bar
            VStack(spacing: 8) {
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(speed)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 8)
            }
            
            // Status Details
            HStack(spacing: 16) {
                // Status Icon
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
                
                // Status Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action Buttons
                if status == .downloading {
                    Button(action: {
                        fileManager.pauseDownload()
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.orange.opacity(0.1))
                            )
                    }
                } else if status == .paused {
                    Button(action: {
                        fileManager.resumeDownload()
                    }) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.green.opacity(0.1))
                            )
                    }
                }
                
                if status == .downloading || status == .paused {
                    Button(action: {
                        fileManager.cancelDownload()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private var progressColor: Color {
        switch status {
        case .downloading:
            return .green
        case .completed:
            return .green
        case .failed:
            return .red
        case .paused:
            return .orange
        case .idle:
            return .gray
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .downloading:
            return .green
        case .completed:
            return .green
        case .failed:
            return .red
        case .paused:
            return .orange
        case .idle:
            return .gray
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .downloading:
            return "arrow.down.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .idle:
            return "circle"
        }
    }
    
    private var statusDescription: String {
        switch status {
        case .downloading:
            return "File is being downloaded..."
        case .completed:
            return "Download completed successfully"
        case .failed:
            return "Download failed. Please try again"
        case .paused:
            return "Download paused"
        case .idle:
            return "Ready to download"
        }
    }
}

struct DownloadStatusBadge: View {
    let status: DownloadStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.1))
            )
            .foregroundColor(statusColor)
    }
    
    private var statusColor: Color {
        switch status {
        case .downloading:
            return .green
        case .completed:
            return .green
        case .failed:
            return .red
        case .paused:
            return .orange
        case .idle:
            return .gray
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DownloadProgressView(progress: 0.45, status: .downloading, speed: "1.5 MB/s", fileName: "Sample_Document.pdf", fileManager: FileSharingManager())
        DownloadProgressView(progress: 1.0, status: .completed, speed: "0 KB/s", fileName: "Sample_Image.jpg", fileManager: FileSharingManager())
        DownloadProgressView(progress: 0.0, status: .failed, speed: "0 KB/s", fileName: "Sample_Video.mp4", fileManager: FileSharingManager())
    }
    .padding()
}
