import SwiftUI
import MediaPlayer

/// Music widget showing now playing info and controls
class MusicWidget: AuraWidget {
    let id = UUID()
    let name = "Music"
    let iconName = "music.note"
    
    @Published var size: WidgetSize = .medium
    @Published var priority: WidgetPriority = .normal
    @Published var isEnabled: Bool = true
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var trackName: String?
    @Published private(set) var artistName: String?
    @Published private(set) var albumArtwork: NSImage?
    
    private var timer: Timer?
    
    func body(for size: WidgetSize) -> some View {
        MusicWidgetView(
            isPlaying: isPlaying,
            trackName: trackName,
            artistName: artistName,
            albumArtwork: albumArtwork,
            size: size,
            onPlayPause: playPause,
            onNext: next,
            onPrevious: previous
        )
    }
    
    func onAppear() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        updateNowPlaying()
    }
    
    private func updateNowPlaying() {
        // First try native media (Apple Music, Spotify app, etc.)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        
        var foundMusic = false
        
        if let title = info?[MPMediaItemPropertyTitle] as? String {
            trackName = title
            artistName = info?[MPMediaItemPropertyArtist] as? String
            
            if let artworkData = info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
                albumArtwork = artworkData.image(at: CGSize(width: 40, height: 40)) as? NSImage
            }
            
            foundMusic = true
            isPlaying = true
        }
        
        // If no native music, check browser tabs (YouTube Music, Spotify Web, etc.)
        if !foundMusic {
            if let browserInfo = detectBrowserMusic() {
                trackName = browserInfo.title
                artistName = browserInfo.artist ?? "Web Player"
                albumArtwork = nil // Browser tabs don't provide artwork easily
                foundMusic = true
                isPlaying = true
            }
        }
        
        // If still no music found
        if !foundMusic {
            trackName = nil
            artistName = nil
            albumArtwork = nil
            isPlaying = false
        }
        
        // Update priority if music is playing
        priority = foundMusic ? .high : .low
    }
    
    /// Detect music playing in browser tabs (YouTube Music, Spotify Web, etc.)
    private func detectBrowserMusic() -> (title: String, artist: String?)? {
        // Get running browsers
        let browsers = ["Google Chrome", "Safari", "Microsoft Edge", "Firefox", "Arc"]
        
        for browserName in browsers {
            if NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == browserName }) {
                // Use AppleScript to get tab info
                if let musicInfo = getMusicFromBrowser(browserName) {
                    return musicInfo
                }
            }
        }
        
        return nil
    }
    
    /// Use AppleScript to extract music info from browser tabs
    private func getMusicFromBrowser(_ browserName: String) -> (title: String, artist: String?)? {
        let script: String
        
        switch browserName {
        case "Google Chrome", "Microsoft Edge", "Arc":
            script = """
            tell application "\(browserName)"
                set tabTitles to title of tabs of front window
                repeat with tabTitle in tabTitles
                    -- YouTube Music format: "Song - Artist - YouTube Music"
                    if tabTitle contains "YouTube Music" then
                        set musicPart to text 1 thru ((offset of " - YouTube Music" in tabTitle) - 1) of tabTitle
                        if musicPart contains " - " then
                            set AppleScript's text item delimiters to " - "
                            set titleParts to text items of musicPart
                            return item 1 of titleParts & "|" & item 2 of titleParts
                        else
                            return musicPart & "|"
                        end if
                    end if
                    -- Spotify Web format: "Song • Artist - Spotify"
                    if tabTitle contains "Spotify" and tabTitle contains "•" then
                        set musicPart to text 1 thru ((offset of " - Spotify" in tabTitle) - 1) of tabTitle
                        set AppleScript's text item delimiters to " • "
                        set titleParts to text items of musicPart
                        return item 1 of titleParts & "|" & item 2 of titleParts
                    end if
                end repeat
            end tell
            return ""
            """
            
        case "Safari":
            script = """
            tell application "Safari"
                set tabTitles to name of tabs of front window
                repeat with tabTitle in tabTitles
                    if tabTitle contains "YouTube Music" then
                        set musicPart to text 1 thru ((offset of " - YouTube Music" in tabTitle) - 1) of tabTitle
                        if musicPart contains " - " then
                            set AppleScript's text item delimiters to " - "
                            set titleParts to text items of musicPart
                            return item 1 of titleParts & "|" & item 2 of titleParts
                        else
                            return musicPart & "|"
                        end if
                    end if
                    if tabTitle contains "Spotify" and tabTitle contains "•" then
                        set musicPart to text 1 thru ((offset of " - Spotify" in tabTitle) - 1) of tabTitle
                        set AppleScript's text item delimiters to " • "
                        set titleParts to text items of musicPart
                        return item 1 of titleParts & "|" & item 2 of titleParts
                    end if
                end repeat
            end tell
            return ""
            """
            
        default:
            return nil
        }
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil, let resultString = output.stringValue, !resultString.isEmpty {
                let parts = resultString.components(separatedBy: "|")
                return (title: parts[0], artist: parts.count > 1 ? parts[1] : nil)
            }
        }
        
        return nil
    }
    
    // MARK: - Controls
    
    func playPause() {
        // Send play/pause media key event
        sendMediaKeyEvent(key: NX_KEYTYPE_PLAY)
        isPlaying.toggle()
    }
    
    func next() {
        sendMediaKeyEvent(key: NX_KEYTYPE_NEXT)
    }
    
    func previous() {
        sendMediaKeyEvent(key: NX_KEYTYPE_PREVIOUS)
    }
    
    private func sendMediaKeyEvent(key: Int32) {
        // Create and post media key events
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xa << 8)),
            data2: -1
        )
        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xb << 8)),
            data2: -1
        )
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }
}

// Media key constants
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18

struct MusicWidgetView: View {
    let isPlaying: Bool
    let trackName: String?
    let artistName: String?
    let albumArtwork: NSImage?
    let size: WidgetSize
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
            case .medium:
                VStack(spacing: 2) {
                    Image(systemName: trackName != nil ? "music.note" : "music.note.slash")
                        .font(.system(size: 16))
                    Text(trackName ?? "No Music")
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            case .expanded:
                expandedView
            }
        }
        .foregroundColor(themeManager.textColor)
    }
    
    private var expandedView: some View {
        HStack(spacing: 12) {
            // Album artwork or placeholder
            Group {
                if let artwork = albumArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(themeManager.widgetBackground)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(themeManager.secondaryTextColor)
                        )
                }
            }
            .frame(width: 40, height: 40)
            .cornerRadius(6)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(trackName ?? "Not Playing")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(artistName ?? "—")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Controls
            HStack(spacing: 8) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WidgetBackground())
    }
}
