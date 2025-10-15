//
//  ToastView.swift
//  WebRTCP2PFileSharing
//
//  Created by Raguraman on 28/08/25.
//

import SwiftUI

struct ToastView: View {
    let message: String
    let type: ToastType
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            VStack {
                Spacer()
                
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundColor(iconColor)
                    
                    // Message
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    // Close Button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isShowing = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .shadow(color: backgroundColor.opacity(0.3), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private var iconName: String {
        switch type {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch type {
        case .success:
            return .green
        case .error:
            return .red
        case .info:
            return .blue
        case .warning:
            return .orange
        }
    }
    
    private var backgroundColor: Color {
        switch type {
        case .success:
            return Color.green
        case .error:
            return Color.red
        case .info:
            return Color.blue
        case .warning:
            return Color.orange
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(message: "File uploaded successfully!", type: .success, isShowing: .constant(true))
        ToastView(message: "Upload failed. Please try again.", type: .error, isShowing: .constant(true))
        ToastView(message: "Connection established.", type: .info, isShowing: .constant(true))
        ToastView(message: "Slow connection detected.", type: .warning, isShowing: .constant(true))
    }
    .padding()
}

