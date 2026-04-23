# WebRTC P2P File Sharing App

A comprehensive iOS application for peer-to-peer file sharing using WebRTC technology. This app provides both sender and receiver functionality in a single interface.

## Features

### 🔌 Connection Status
- Real-time online/offline status indicator
- Visual connection status with color-coded indicators
- Automatic reconnection handling

### 📤 File Sending (Sender Mode)
- **File Selection**: Tap "Start File Sharing" to select files from your device
- **File Sharing Request**: Creates and sends a file transfer request to the receiver
- **Request Status**: View pending requests and their status (pending, accepted, declined)
- **File Preview**: View file information including name, size, type, and preview image
- **Upload Progress**: Real-time progress tracking with percentage and speed (only after acceptance)
- **Status Management**: Pause, resume, and cancel uploads
- **File Types Supported**: Images, documents, videos, audio, and more

### 📥 File Receiving (Receiver Mode)
- **Incoming Requests**: Automatic alerts for new file transfer requests
- **Request Details**: See file information, sender details, and timestamp
- **Accept/Decline**: Choose to accept or decline incoming file transfers
- **Download Progress**: Track download progress with real-time updates
- **Download Management**: Pause, resume, and cancel downloads

### 🔔 Notifications & Feedback
- **Toast Messages**: Success, error, info, and warning notifications
- **Progress Indicators**: Visual progress bars and status badges
- **Real-time Updates**: Live progress and speed information

## UI Components

### Main Screen
- **Connection Status Header**: Shows online/offline status
- **File Sharing Section**: For sending files to other users
- **Incoming Requests Section**: Lists pending file transfer requests
- **Progress Tracking**: Shows upload/download progress when active

### File Transfer Request Alert
- **File Information**: Name, size, type, and preview
- **Sender Details**: User ID and timestamp
- **Action Buttons**: Accept or decline the transfer

### Progress Views
- **Upload Progress**: Shows file upload status and controls
- **Download Progress**: Shows file download status and controls
- **Status Badges**: Color-coded status indicators
- **Action Controls**: Pause, resume, and cancel buttons

## Technical Implementation

### Architecture
- **SwiftUI**: Modern declarative UI framework
- **MVVM Pattern**: Model-View-ViewModel architecture
- **ObservableObject**: Reactive data binding
- **Protocol-Oriented**: Clean separation of concerns

### Core Services
- **FileSharingManager**: Central business logic controller
- **SignalingClient**: WebRTC signaling server communication
- **WebSocketProvider**: Real-time communication layer
- **File Management**: File selection, preview, and metadata

### Data Models
- **FileInfo**: File metadata and preview generation
- **IncomingFileRequest**: Incoming transfer request details
- **UploadStatus/DownloadStatus**: Transfer state management
- **ToastType**: Notification categorization

## Usage

### Sending Files
1. Ensure you're connected to the network
2. Tap "Start File Sharing"
3. Select a file from your device
4. **File sharing request is automatically sent to receiver**
5. **Wait for receiver to accept the request**
6. **Once accepted, upload begins automatically**
7. Monitor upload progress
8. Use pause/resume/cancel controls as needed

### Receiving Files
1. **Incoming file transfer requests appear as alerts automatically**
2. Review file details and sender information in the alert
3. Choose to accept or decline the transfer
4. If accepted, download begins automatically
5. Monitor download progress
6. Use download controls as needed

## Development Notes

### Current Implementation
- **Simulation Mode**: Currently uses simulated data for demonstration
- **UI Complete**: Full user interface implemented
- **State Management**: Complete state handling for all scenarios
- **Error Handling**: Comprehensive error states and user feedback

### Integration Points
- **WebRTC Client**: Ready for WebRTC implementation
- **Signaling Server**: Prepared for real server communication
- **File System**: Integrated with iOS file management
- **Network Layer**: WebSocket infrastructure in place

### Future Enhancements
- **Real WebRTC**: Implement actual P2P file transfer
- **Security**: Add encryption and authentication
- **File Validation**: Implement file type and size restrictions
- **User Management**: Add user accounts and contact lists
- **Transfer History**: Track completed transfers
- **Background Transfers**: Support for background file operations

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+
- WebRTC framework
- Network connectivity

## Installation

1. Clone the repository
2. Update signaling server URL in `WebRTCP2PFileSharing/Config.swift`
   - Find:
     ```swift
     let defaultSignalingServerUrl = URL(string: "ws://your-machine-ip:8080")!
     ```
   - Replace `your-machine-ip` with your Mac's LAN IP, for example:
     ```swift
     let defaultSignalingServerUrl = URL(string: "ws://192.168.1.25:8080")!
     ```
3. Start the signaling server (required before running the iOS app)
   ```bash
   cd NodeJS
   npm install
   node app.js
   ```
   The server starts on port `8080` and prints available LAN IP URLs.
4. Open `WebRTCP2PFileSharing.xcodeproj` in Xcode
5. Build and run on a device or simulator
6. Grant necessary permissions when prompted

## Signaling Server (NodeJS)

The signaling server is included in this repository under `NodeJS/`.

### Start locally
```bash
cd NodeJS
npm install
node app.js
```

Expected output:
```text
Signaling server is now listening on port 8080
Use one of these URLs in Config.swift:
- ws://192.168.1.25:8080
```

### Update app configuration with your IP

In `WebRTCP2PFileSharing/Config.swift`, update:

```swift
let defaultSignalingServerUrl = URL(string: "ws://your-machine-ip:8080")!
```

Use one of the printed IPs from `node app.js`.

### Use the IP printed by the server

When you run:

```bash
node app.js
```

the server prints available LAN signaling URLs, for example:

```text
Signaling server is now listening on port 8080
Use one of these URLs in Config.swift:
- ws://192.168.1.25:8080
```

Copy one of the printed `ws://<ip>:8080` values into `WebRTCP2PFileSharing/Config.swift`.
Make sure both sender and receiver clients are on the same network and can reach this host/port.

## App Demo Video

Sample video demonstrating app flow:

- Local file: `/Users/raguraman/Documents/WebRTCFileSharing.mov`

For GitHub rendering, place the video in the repository (for example `assets/WebRTCFileSharing.mov`) and update the link here to that relative path.

## License

This project is for educational and development purposes.
