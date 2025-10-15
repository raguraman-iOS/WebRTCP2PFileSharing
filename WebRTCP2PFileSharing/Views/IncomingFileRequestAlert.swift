//
//  IncomingFileRequestAlert.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct IncomingFileRequestAlert: View {
    let request: IncomingFileRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Incoming File Transfer")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Someone wants to send you a file")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // File Information
            VStack(spacing: 16) {
                // File Icon and Name
                HStack(spacing: 16) {
                    // File Type Icon
                    Image(systemName: fileTypeIcon)
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.fileName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Text(request.fileSize)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Type: \(request.fileType)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Sender Information
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From: \(request.senderId)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Text("Sent: \(timeAgoString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                // Decline Button
                Button(action: onDecline) {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.headline)
                        Text("Decline")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                    )
                }
                
                // Accept Button
                Button(action: onAccept) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.headline)
                        Text("Accept")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green)
                    )
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
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
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

#Preview {
    let sampleRequest = IncomingFileRequest(
        fileName: "Important_Document.pdf",
        fileSize: "2.5 MB",
        fileType: "PDF",
        senderId: "John_Doe",
        timestamp: Date().addingTimeInterval(-300) // 5 minutes ago
    )
    
    IncomingFileRequestAlert(
        request: sampleRequest,
        onAccept: {},
        onDecline: {}
    )
    .padding()
}

