//
//  FileInfoView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct FileInfoView: View {
    let file: FileInfo
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Selected File")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                
                // File Type Badge
                Text(file.type)
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
            
            // File Preview and Info
            HStack(spacing: 16) {
                // Preview Image
                if let previewImage = file.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "doc")
                                .font(.title2)
                                .foregroundColor(.gray)
                        )
                }
                
                // File Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(file.size)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Type: \(file.type)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    // Remove file action
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text("Remove")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                
                Spacer()
                
                Button(action: {
                    // View file details action
                }) {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("Details")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
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
}

#Preview {
    let sampleFile = try! FileInfo(url: URL(fileURLWithPath: "/sample/document.pdf"))
    FileInfoView(file: sampleFile)
        .padding()
}

