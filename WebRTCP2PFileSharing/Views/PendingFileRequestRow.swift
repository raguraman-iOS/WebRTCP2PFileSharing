//
//  PendingFileRequestRow.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct PendingFileRequestRow: View {
    let request: FileSharingRequest
    
    var body: some View {
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
                    
                    Text("Sent: \(timeAgoString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status Badge
            PendingStatusBadge(status: request.status)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
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

struct PendingStatusBadge: View {
    let status: FileSharingStatus
    
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
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .declined:
            return .red
        case .completed:
            return .blue
        }
    }
}

#Preview {
    let sampleRequest = FileSharingRequest(
        fileName: "Important_Document.pdf",
        fileSize: "2.5 MB",
        fileType: "PDF",
        senderId: "You",
        timestamp: Date().addingTimeInterval(-120), // 2 minutes ago
        status: .pending
    )
    
    PendingFileRequestRow(request: sampleRequest)
        .padding()
}

