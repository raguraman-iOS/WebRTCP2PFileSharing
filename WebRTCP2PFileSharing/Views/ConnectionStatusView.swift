//
//  ConnectionStatusView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct ConnectionStatusView: View {
    let isOnline: Bool
    let onDisconnect: (() -> Void)?
    let connectionStatus: String
    
    init(isOnline: Bool, onDisconnect: (() -> Void)? = nil, connectionStatus: String = "Connected") {
        self.isOnline = isOnline
        self.onDisconnect = onDisconnect
        self.connectionStatus = connectionStatus
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(isOnline ? (connectionStatus.contains("Ready") ? Color.green : Color.blue) : Color.red)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .shadow(color: isOnline ? (connectionStatus.contains("Ready") ? .green.opacity(0.3) : .blue.opacity(0.3)) : .red.opacity(0.3), radius: 4)
                )
            
            // Status Text
            Text(isOnline ? (connectionStatus.contains("Ready") ? "Ready" : "Connected") : "Offline")
                .font(.headline)
                .foregroundColor(isOnline ? (connectionStatus.contains("Ready") ? .green : .blue) : .red)
            
            // Connection Icon
            Image(systemName: isOnline ? (connectionStatus.contains("Ready") ? "checkmark.circle" : "wifi") : "wifi.slash")
                .font(.title2)
                .foregroundColor(isOnline ? (connectionStatus.contains("Ready") ? .green : .blue) : .red)
            
            Spacer()
            
            // Disconnect Button (if online)
//            if isOnline, let onDisconnect = onDisconnect {
//                Button(action: onDisconnect) {
//                    HStack(spacing: 4) {
//                        Image(systemName: "wifi.slash")
//                            .font(.caption)
//                        Text("Disconnect")
//                            .font(.caption)
//                            .fontWeight(.medium)
//                    }
//                    .foregroundColor(.red)
//                    .padding(.horizontal, 8)
//                    .padding(.vertical, 4)
//                    .background(
//                        RoundedRectangle(cornerRadius: 6)
//                            .fill(Color.red.opacity(0.1))
//                    )
//                }
//                .buttonStyle(PlainButtonStyle())
//            }
            
            // Connection Status (if online)
            if isOnline {
                Text(connectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .padding(.horizontal)
    }
}

#Preview {
    VStack(spacing: 20) {
        ConnectionStatusView(isOnline: true)
        ConnectionStatusView(isOnline: false)
    }
    .padding()
}

