# WebRTC P2P File Sharing App

A comprehensive iOS application for peer-to-peer file sharing using WebRTC technology. This app provides both sender and receiver functionality in a single interface.

### Why I Started This Project
- To demonstrate that files can be transferred peer-to-peer over WebRTC `RTCDataChannel`.
- To show WebRTC is more than calls: `MediaStreams` (audio/video), `RTCDataChannel` (reliable data like files/chat), and screen sharing.
- For file transfer, this project focuses on reliable/ordered delivery so data arrives intact.

### Project Goal
- A simple, practical demo of reliable WebRTC data transfer on iOS.

## App Demo Video

Sample video demonstrating app flow:

https://github.com/user-attachments/assets/519fe13f-914f-46e0-b55a-ae44b54458d6

## Installation

1. Clone the repository
2. Start the signaling server (required before running the iOS app)
   ```bash
   cd NodeJS
   npm install
   node app.js
   ```
   The server starts on port `8080` and prints available LAN IP URLs.
3. Open `WebRTCP2PFileSharing.xcodeproj` in Xcode
4. Update signaling server URL in `WebRTCP2PFileSharing/Config.swift`
   - Find:
     ```swift
     let defaultSignalingServerUrl = URL(string: "ws://your-machine-ip:8080")!
     ```
   - Replace `your-machine-ip` with your Mac's LAN IP, for example:
     ```swift
     let defaultSignalingServerUrl = URL(string: "ws://192.168.1.25:8080")!
     ```
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

### Configure app with printed server IP

Run:

```bash
node app.js
```

The server prints available LAN signaling URLs, for example:

```text
Signaling server is now listening on port 8080
Use one of these URLs in Config.swift:
- ws://192.168.1.25:8080
```

Then update `WebRTCP2PFileSharing/Config.swift`:

```swift
let defaultSignalingServerUrl = URL(string: "ws://your-machine-ip:8080")!
```

Replace `your-machine-ip` with one of the printed IPs. Make sure sender and receiver are on the same network and can reach port `8080`.

## Features

- Send and receive files over WebRTC data channels
- Transfer request flow with accept/decline
- Real-time upload/download progress with pause, resume, and cancel
- Connection status and toast-based feedback

## UI Components

- Main transfer screen (connection state, sender/receiver actions, active progress)
- Incoming request prompt (file details + accept/decline)
- Upload and download progress cards with controls

## Technical Implementation

### Architecture
- **SwiftUI**: Modern declarative UI framework
- **MVVM Pattern**: Model-View-ViewModel architecture
- **ObservableObject**: Reactive data binding
- **Protocol-Oriented**: Clean separation of concerns



### Future Enhancements
- **Security**: Add encryption and authentication
- **File Validation**: Implement file type and size restrictions
- **User Management**: Add user accounts and contact lists
- **Transfer History**: Track completed transfers
- **Background Transfers**: Support for background file operations

## Background Transfer Note (Apple Guidance)

Based on discussion with Apple Developer Technical Support:

- Data-only WebRTC transfer can continue only while the app is still running in background.
- Once iOS suspends the app, low-level networking (including WebRTC data channels) stops.
- A short `UIApplication` background task can provide limited time to finish in-flight work.
- For reliable transfer while the app is suspended, use supported background-capable APIs (for example, `URLSession` background sessions).

Reference discussion:
- [WebRTC Data Channel for Background File Transfer Without Audio/Video](https://developer.apple.com/forums/thread/799259)

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


## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+
- WebRTC framework
- Network connectivity

## License

This project is for educational and development purposes.
