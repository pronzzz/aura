# Aura ⚡️
> The ultimate Dynamic Island companion for macOS.

![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

**Aura** transforms your Mac's notch into a powerful, context-aware command center. Inspired by Dynamic Island, it provides instant access to media controls, system stats, calendar events, and AI-powered tools right from the top of your screen.

## ✨ Features

- **🎯 Smart Notch Integration**: Automatically positions itself behind the notch on MacBook Pros, or simulates one on other Macs.
- **🎵 Universal Media Controls**: Control Apple Music, Spotify, and **even browser-based players** (YouTube Music, Spotify Web) directly from the notch.
- **🧠 Local AI Power**: Integrated with Ollama for privacy-focused, offline AI commands and assistance.
- **📋 Smart Clipboard**: Drag-and-drop text, images, and files to the notch for temporary storage.
- **⚡️ Automation Workflows**: Create "If This Then That" rules based on battery, focus modes, and more.
- **🔌 Plugin System**: Extend functionality with custom plugins (includes Pomodoro, Weather, and more).
- **🔒 Privacy First**: No keystroke logging, strictly local AI processing, and zero analytics tracking.

## 🚀 Installation

### Download
Download the latest version from the [Releases](https://github.com/pronzzz/aura/releases) page.

### Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/pronzzz/aura.git
   ```
2. Open `Aura.xcodeproj` in Xcode 15+.
3. Build and Run (Cmd+R).

## 📖 Usage Guide

### The Notch
- **Hover** over the notch to expand it.
- **Click** anywhere outside to collapse.
- **Drag & Drop** files/text onto the notch to stash them.

### Media Controls
Aura automatically detects music playing in:
- Native Apps: Apple Music, Spotify
- Browsers: Chrome, Safari, Arc, Edge (YouTube Music, Spotify Web)

### AI Commands
Type natural language commands in the command bar:
- "Start a 20m timer"
- "What's my next meeting?"
- "Turn on Do Not Disturb"

## 🛠 Advanced Configuration

### Automation
Create custom workflows in `Settings > Automation`:
- **Trigger**: Battery < 20% → **Action**: Turn on Low Power Mode
- **Trigger**: Work Focus on → **Action**: Open Slack & Xcode

### Plugins
Aura supports a lightweight plugin architecture. Check out the `Plugins/` directory for examples like the Pomodoro timer and Weather widget.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---
Built with ❤️ by [pronzzz](https://github.com/pronzzz)
