# Gossip Chat Demo

A fully functional Flutter peer-to-peer chat application that enables real-time messaging between nearby Android devices using Google's Nearby Connections API. No internet connection required!

## ✨ Features

- **🔌 Offline P2P Messaging** - Chat with nearby devices without internet
- **🔍 Automatic Device Discovery** - Finds and connects to nearby devices automatically
- **⚡ Real-time Synchronization** - Messages appear instantly on all connected devices
- **📚 Historical Event Sync** - New devices automatically receive complete chat history
- **🎨 Modern UI** - Clean Material Design 3 interface with message bubbles
- **👥 Peer Management** - View all connected users in an elegant sidebar
- **🔔 System Notifications** - Join/leave notifications with user-friendly messages
- **🛡️ Smart Permission Handling** - Intelligent permission requests based on Android version
- **🔄 Auto-reconnection** - Handles network disruptions gracefully
- **💬 Message Types** - Support for text messages and system notifications

## 📱 Requirements

- **Android device** (API level 23 or higher)
- **Bluetooth enabled** for device discovery
- **Location services enabled** (required by Nearby Connections API)
- **Physical proximity** to other devices (typically 100m range)
- **Multiple devices** for testing P2P functionality

## 🔐 Permissions

The app intelligently requests permissions based on your Android version:

### Required Permissions:
- **Location** (ACCESS_FINE_LOCATION) - Required by Nearby Connections API
- **Bluetooth** permissions:
  - Android 11 and below: `BLUETOOTH`
  - Android 12+: `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`

### Optional Permissions:
- **Nearby WiFi Devices** (Android 13+) - For enhanced connectivity
- **Storage** - For potential future file sharing features

The app includes smart permission handling that:
- ✅ Detects your Android version automatically
- ✅ Requests only necessary permissions
- ✅ Provides helpful error messages
- ✅ Guides users through permission setup

## 🚀 Setup Instructions

### Prerequisites
- Flutter SDK installed and configured
- Android SDK with API level 23+
- Physical Android devices for testing (emulators won't work for P2P)

### Installation Steps

1. **Clone the repository:**
```bash
git clone <repository-url>
cd gossip-demo
```

2. **Install Flutter dependencies:**
```bash
flutter pub get
```

3. **Build the APK:**
```bash
flutter build apk --release
```

4. **Install on multiple Android devices:**
```bash
flutter install
# Or manually install the APK from build/app/outputs/flutter-apk/
```

## 📖 How to Use

### First Launch
1. **Open the app** on each Android device
2. **Enter your display name** when prompted
3. **Grant permissions** when requested:
   - Allow Location access
   - Allow Bluetooth permissions
   - Enable Location services if prompted

### Start Chatting
1. **Wait for discovery** - Devices will automatically find each other (usually within 10-30 seconds)
2. **Check connected peers** - Tap the people icon to see connected devices
3. **Start messaging** - Type and send messages that appear on all devices instantly
4. **Watch for notifications** - See when users join or leave the chat

### Troubleshooting
- **No devices found?** Ensure Bluetooth and Location are enabled on both devices
- **Permission errors?** Go to Settings > Apps > Gossip Chat Demo > Permissions
- **Connection issues?** Try moving devices closer together (within 10-20 meters)

## 🏗️ Architecture

### Network Architecture
- **🔗 Direct P2P Mesh Network** - Each device connects directly to every other device
- **📡 Nearby Connections API** - Google's robust P2P networking framework
- **📨 Broadcast Protocol** - Messages sent to all connected peers simultaneously
- **🔄 Auto-discovery** - Continuous scanning for nearby devices
- **🛡️ Connection Management** - Automatic handling of joins, leaves, and failures

### App Architecture
- **🎯 Provider Pattern** - Reactive state management with Flutter Provider
- **📦 Service Layer** - Separated business logic (ChatService, PermissionsService)
- **🎨 Widget Composition** - Reusable UI components (MessageBubble, PeerListDrawer)
- **📱 Material Design 3** - Modern Android design patterns

### Message Protocol
All messages use JSON format over Nearby Connections:

```json
{
  "type": "chat_message",
  "data": {
    "id": "unique-message-id",
    "senderId": "user-id",
    "senderName": "Display Name",
    "content": "Hello world!",
    "timestamp": 1640995200000,
    "type": "text"
  }
}
```

### Message Types
- **`chat_message`** - User text messages with full metadata
- **`user_joined`** - System notification when a user joins the network
- **`user_left`** - System notification when a user leaves the network

## 📁 Project Structure

```
gossip-demo/
├── lib/
│   ├── main.dart                    # 🎯 App entry point with Provider setup
│   ├── models/
│   │   ├── chat_message.dart       # 💬 Message data model with JSON serialization
│   │   └── chat_peer.dart          # 👤 Peer data model with connection status
│   ├── screens/
│   │   ├── name_input_screen.dart  # 📝 User onboarding with validation
│   │   └── chat_screen.dart        # 💬 Main chat interface with real-time updates
│   ├── services/
│   │   ├── chat_service.dart       # 🔧 Core P2P networking and state management
│   │   └── permissions_service.dart # 🔐 Smart Android permission handling
│   └── widgets/
│       ├── message_bubble.dart     # 💭 Chat bubble UI with timestamps
│       └── peer_list_drawer.dart   # 👥 Connected users sidebar
├── android/                        # 🤖 Android-specific configuration
│   ├── app/src/main/AndroidManifest.xml  # Required permissions
│   └── app/build.gradle.kts        # Build configuration
└── README.md                       # 📖 This documentation
```

## 🔧 Technical Implementation

### Core Technologies
- **Flutter SDK** - Cross-platform UI framework
- **nearby_connections** - Official Google plugin for P2P networking
- **Provider** - State management for reactive UI updates
- **SharedPreferences** - Local storage for user identity
- **Material Design 3** - Modern Android UI components

### Key Features Implementation
- **🔍 Automatic Discovery** - Continuous advertising and scanning
- **📡 Multi-peer Support** - Simultaneous connections to multiple devices  
- **💾 Message Deduplication** - Prevents duplicate messages across the network
- **⏰ Smart Timestamps** - Context-aware time formatting (today, yesterday, etc.)
- **🎨 User Avatars** - Generated from names with consistent color coding
- **🔄 Connection Recovery** - Automatic reconnection handling

## ⚠️ Limitations & Considerations

### Platform Limitations
- **Android Only** - Nearby Connections API is Android-exclusive
- **Physical Devices Required** - Cannot test on emulators
- **Range Dependent** - Typically 100m line-of-sight (varies by environment)

### Current Implementation
- **Session-based** - Messages don't persist after app closure
- **Plain Text** - No encryption (fine for demo/local use)
- **No Media** - Text messages only (extensible architecture for future media support)
- **Local Network** - No internet relay or cloud backup

## 🛠️ Development & Testing

### Development Mode
```bash
# Run in development with hot reload
flutter run

# Run with verbose logging for debugging
flutter run --verbose

# Build and test release version
flutter build apk --release
```

### Testing P2P Functionality
Since this is a peer-to-peer app, you need **multiple physical Android devices** to test properly:

1. **Install on Device 1:**
   ```bash
   flutter install
   ```

2. **Install on Device 2 (and 3, 4, etc.):**
   - Copy APK from `build/app/outputs/flutter-apk/app-release.apk`
   - Install manually or use `adb install app-release.apk`

3. **Testing Steps:**
   - Open app on all devices
   - Enter different names on each device  
   - Wait for automatic discovery (10-30 seconds)
   - Check peer list to confirm connections
   - Send messages from each device to test sync

### Debugging Tips
```bash
# View logs from connected device
adb logcat | grep -i flutter

# Check if Nearby Connections is working
adb logcat | grep -i nearby

# Monitor permission requests
adb logcat | grep -i permission
```

## 🔧 Troubleshooting Guide

### Connection Issues
| Problem | Solution |
|---------|----------|
| 🔍 **No devices found** | • Ensure Bluetooth + Location enabled on both devices<br>• Move devices closer (within 20m)<br>• Restart app and wait 30 seconds |
| 🚫 **Permission denied** | • Open Settings > Apps > Gossip Chat Demo > Permissions<br>• Enable Location, Bluetooth, Nearby devices<br>• Restart app after granting permissions |
| 💔 **Frequent disconnections** | • Keep devices closer together<br>• Ensure Location/GPS is enabled<br>• Check for interference (move away from WiFi routers) |
| 📱 **App crashes on startup** | • Check Android version (need API 23+)<br>• Clear app data and try again<br>• Check device compatibility |

### Message Issues
| Problem | Solution |
|---------|----------|
| 📤 **Messages not sending** | • Check peer list - are devices connected?<br>• Try sending from other device first<br>• Restart both apps |
| 👥 **Peer list empty** | • Wait 30+ seconds for discovery<br>• Toggle Bluetooth off/on<br>• Move devices closer together |
| 🔄 **Messages appear twice** | • Normal behavior - each device shows its own messages<br>• Check sender name to distinguish sources |

## 🚀 Future Enhancements

### Planned Features
- **📁 File Sharing** - Send images, documents, and media files
- **💾 Message History** - Persistent storage with local database
- **🔐 End-to-End Encryption** - Secure messaging with key exchange
- **📱 iOS Support** - Using MultipeerConnectivity framework
- **🎨 Themes & Customization** - Dark mode, custom colors, chat backgrounds
- **🔔 Enhanced Notifications** - Background messaging, notification sounds

### Technical Improvements
- **🔄 Mesh Networking** - Improved routing for larger groups
- **📊 Analytics** - Connection quality, message delivery stats
- **🧪 Automated Testing** - Unit and integration tests
- **🌐 Hybrid Connectivity** - Fallback to internet when nearby connections fail

## 📄 License

```
MIT License

Copyright (c) 2024 Gossip Chat Demo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

---

## 🎉 Success! You now have a fully functional P2P chat app!

**Quick Start:** Install on 2+ Android devices → Enter names → Start chatting! 🚀

**Questions?** Check the troubleshooting section above or review the code comments for detailed implementation notes.