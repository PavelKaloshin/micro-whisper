import SwiftUI
import WebKit

// MARK: - Hotkey Display Helper

func currentHotkeyDisplayString() -> String {
    let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 25
    let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    
    var parts: [String] = []
    let modifiers = NSEvent.ModifierFlags(rawValue: UInt(savedModifiers))
    
    if modifiers.contains(.control) { parts.append("⌃") }
    if modifiers.contains(.option) { parts.append("⌥") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.command) { parts.append("⌘") }
    
    let keyMap: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M", 49: "Space"
    ]
    parts.append(keyMap[savedKeyCode] ?? "?")
    
    return parts.joined()
}

// MARK: - Markdown WebView

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let isDarkMode: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        // Enable scrolling
        webView.enclosingScrollView?.hasVerticalScroller = true
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                // Open link in default browser
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
    
    private func generateHTML(from markdown: String) -> String {
        let textColor = isDarkMode ? "#FFFFFF" : "#000000"
        let tableBorder = isDarkMode ? "#555555" : "#CCCCCC"
        let tableHeaderBg = isDarkMode ? "#3A3A3C" : "#F0F0F0"
        let codeBg = isDarkMode ? "#2C2C2E" : "#F5F5F5"
        let linkColor = isDarkMode ? "#64D2FF" : "#007AFF"
        
        // Convert markdown to HTML manually
        let htmlContent = convertMarkdownToHTML(markdown)
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    height: auto;
                    overflow-y: auto;
                    overflow-x: hidden;
                    -webkit-overflow-scrolling: touch;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                    font-size: 13px;
                    line-height: 1.5;
                    color: \(textColor);
                    background: transparent;
                    padding: 4px;
                    -webkit-font-smoothing: antialiased;
                }
                p { margin-bottom: 8px; }
                ul, ol { margin: 8px 0; padding-left: 20px; }
                li { margin: 4px 0; }
                strong, b { font-weight: 600; }
                em, i { font-style: italic; }
                code {
                    font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                    font-size: 12px;
                    background: \(codeBg);
                    padding: 2px 6px;
                    border-radius: 4px;
                    white-space: pre-wrap;
                    word-break: break-word;
                }
                pre {
                    background: \(codeBg);
                    padding: 12px;
                    border-radius: 8px;
                    overflow-x: auto;
                    margin: 8px 0;
                    white-space: pre;
                    font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                    font-size: 12px;
                    line-height: 1.4;
                }
                pre code { 
                    background: none; 
                    padding: 0;
                    white-space: pre;
                    display: block;
                }
                a { color: \(linkColor); text-decoration: none; }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 12px 0;
                    font-size: 12px;
                }
                th, td {
                    border: 1px solid \(tableBorder);
                    padding: 8px 12px;
                    text-align: left;
                }
                th {
                    background: \(tableHeaderBg);
                    font-weight: 600;
                }
                h1, h2, h3, h4 { margin: 12px 0 8px 0; font-weight: 600; }
                h1 { font-size: 18px; }
                h2 { font-size: 16px; }
                h3 { font-size: 14px; }
                blockquote {
                    border-left: 3px solid \(linkColor);
                    padding-left: 12px;
                    margin: 8px 0;
                    opacity: 0.8;
                }
                a {
                    color: \(linkColor);
                    text-decoration: underline;
                }
                a:hover {
                    opacity: 0.8;
                }
            </style>
        </head>
        <body>\(htmlContent)</body>
        </html>
        """
    }
    
    private func convertMarkdownToHTML(_ text: String) -> String {
        var html = text
        
        // Escape HTML special chars first (but preserve our conversions)
        html = html.replacingOccurrences(of: "&", with: "&amp;")
        html = html.replacingOccurrences(of: "<", with: "&lt;")
        html = html.replacingOccurrences(of: ">", with: "&gt;")
        
        // Code blocks (```language ... ``` or ``` ... ```)
        // Handle with optional language and optional newline
        let codeBlockPattern = "```(\\w*)\\n?([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            html = regex.stringByReplacingMatches(in: html, options: [], range: NSRange(html.startIndex..., in: html), withTemplate: "<pre><code>$2</code></pre>")
        }
        
        // If no code blocks but looks like code (indentation, common patterns), wrap in pre
        if !html.contains("<pre>") && looksLikeCode(html) {
            html = "<pre><code>\(html)</code></pre>"
        }
        
        // Inline code (`...`)
        let inlineCodePattern = "`([^`]+)`"
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) {
            html = regex.stringByReplacingMatches(in: html, options: [], range: NSRange(html.startIndex..., in: html), withTemplate: "<code>$1</code>")
        }
        
        // Tables
        html = convertTables(html)
        
        // Headers
        html = html.replacingOccurrences(of: "(?m)^#### (.+)$", with: "<h4>$1</h4>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)
        
        // Bold (**text** or __text__)
        html = html.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "__([^_]+)__", with: "<strong>$1</strong>", options: .regularExpression)
        
        // Italic (*text* or _text_)
        html = html.replacingOccurrences(of: "(?<![*])\\*([^*]+)\\*(?![*])", with: "<em>$1</em>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?<!_)_([^_]+)_(?!_)", with: "<em>$1</em>", options: .regularExpression)
        
        // Links [text](url)
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            html = regex.stringByReplacingMatches(in: html, options: [], range: NSRange(html.startIndex..., in: html), withTemplate: "<a href=\"$2\" target=\"_blank\">$1</a>")
        }
        
        // Unordered lists
        html = html.replacingOccurrences(of: "(?m)^[*-] (.+)$", with: "<li>$1</li>", options: .regularExpression)
        
        // Ordered lists
        html = html.replacingOccurrences(of: "(?m)^\\d+\\. (.+)$", with: "<li>$1</li>", options: .regularExpression)
        
        // Wrap consecutive <li> in <ul>
        html = html.replacingOccurrences(of: "(<li>.*</li>\\n?)+", with: "<ul>$0</ul>", options: .regularExpression)
        
        // Paragraphs - wrap lines that aren't already HTML
        let lines = html.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                result.append("")
            } else if trimmed.hasPrefix("<") {
                result.append(line)
            } else {
                result.append("<p>\(line)</p>")
            }
        }
        html = result.joined(separator: "\n")
        
        // Clean up empty paragraphs
        html = html.replacingOccurrences(of: "<p></p>", with: "")
        html = html.replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        
        return html
    }
    
    private func convertTables(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            // Check if this line looks like a table row (contains |)
            if line.contains("|") && i + 1 < lines.count && lines[i + 1].contains("-") && lines[i + 1].contains("|") {
                // This is a table header
                var tableHTML = "<table>"
                
                // Header row
                let headerCells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                tableHTML += "<tr>"
                for cell in headerCells where !cell.isEmpty {
                    tableHTML += "<th>\(cell)</th>"
                }
                tableHTML += "</tr>"
                
                i += 2 // Skip header and separator
                
                // Data rows
                while i < lines.count && lines[i].contains("|") {
                    let cells = lines[i].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    tableHTML += "<tr>"
                    for cell in cells where !cell.isEmpty {
                        tableHTML += "<td>\(cell)</td>"
                    }
                    tableHTML += "</tr>"
                    i += 1
                }
                
                tableHTML += "</table>"
                result.append(tableHTML)
            } else {
                result.append(line)
                i += 1
            }
        }
        
        return result.joined(separator: "\n")
    }
    
    /// Detect if text looks like code (for auto-formatting)
    private func looksLikeCode(_ text: String) -> Bool {
        let codePatterns = [
            "^(def |class |import |from |if |for |while |return |async |await )",  // Python
            "^(function |const |let |var |import |export |if |for |while |return )",  // JS/TS
            "^(func |struct |class |import |if |for |while |return |guard |let |var )",  // Swift
            "^(public |private |class |interface |import |if |for |while |return )",  // Java
            "\\{|\\}|\\(\\)|=>|->|::|&&|\\|\\|",  // Common code symbols
            "^\\s{2,}\\S",  // Indented lines
            "\\w+\\s*=\\s*\\w+",  // Assignment
            "\\w+\\(.*\\)",  // Function calls
        ]
        
        let lines = text.components(separatedBy: "\n")
        var codeLineCount = 0
        
        for line in lines {
            for pattern in codePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
                   regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil {
                    codeLineCount += 1
                    break
                }
            }
        }
        
        // If more than 50% of lines look like code, treat as code
        return lines.count > 0 && Double(codeLineCount) / Double(lines.count) > 0.5
    }
}

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseAnimation = false
    
    var body: some View {
        Group {
            if case .showingResult(let text) = appState.processingState {
                ResultView(text: text)
            } else {
                recordingView
            }
        }
    }
    
    private var recordingView: some View {
        VStack(spacing: 16) {
            // Animated audio visualization
            ZStack {
                if appState.isRecording {
                    AudioLevelCircles(level: appState.audioLevel)
                } else if appState.processingState == .transcribing || appState.processingState == .processing {
                    ProcessingAnimation()
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(iconColor)
                }
            }
            .frame(width: 120, height: 120)
            
            // Status text
            Text(statusText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            // Subtitle
            Text(subtitleText)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Controls during recording
            if appState.isRecording {
                VStack(spacing: 8) {
                    // Section 1: Language
                    VStack(spacing: 4) {
                        Text("LANGUAGE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                        HStack(spacing: 5) {
                            LanguageButton(key: "0", label: "Auto", code: "auto", currentLanguage: appState.whisperLanguage)
                            LanguageButton(key: "1", label: "EN", code: "en", currentLanguage: appState.whisperLanguage)
                            LanguageButton(key: "2", label: "RU", code: "ru", currentLanguage: appState.whisperLanguage)
                        }
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Section 2: Mode
                    VStack(spacing: 4) {
                        Text("MODE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                        HStack(spacing: 4) {
                            ForEach([RecordingMode.transcribe, .askGPT, .respond], id: \.self) { mode in
                                RecordingModeButton(mode: mode, currentMode: appState.recordingMode)
                            }
                        }
                        HStack(spacing: 4) {
                            ForEach([RecordingMode.code, .process], id: \.self) { mode in
                                RecordingModeButton(mode: mode, currentMode: appState.recordingMode)
                            }
                        }
                    }
                    
                    // Section 3: Mode-specific options
                    if appState.recordingMode == .transcribe {
                        Divider().opacity(0.3)
                        VStack(spacing: 4) {
                            Text("FORMAT")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.7))
                            HStack(spacing: 4) {
                                ForEach(FormattingMode.allCases, id: \.self) { mode in
                                    FormattingButton(mode: mode, currentMode: appState.formattingMode)
                                }
                            }
                        }
                    }
                    
                    if appState.recordingMode == .code {
                        Divider().opacity(0.3)
                        VStack(spacing: 4) {
                            Text("LANGUAGE")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.7))
                            HStack(spacing: 4) {
                                ForEach(CodeLanguageMode.allCases, id: \.self) { mode in
                                    CodeLanguageButton(mode: mode, currentMode: appState.codeLanguageMode)
                                }
                            }
                        }
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Section 4: Options
                    VStack(spacing: 4) {
                        Text("OPTIONS")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        HStack(spacing: 8) {
                            // Clipboard toggle (for modes that use it)
                            if appState.recordingMode.usesClipboard {
                                ClipboardIndicator(
                                    content: appState.clipboardContent,
                                    useClipboard: $appState.useClipboardContext
                                )
                            }
                            
                            // Terminology toggle (only in transcribe mode if terms exist)
                            if appState.recordingMode == .transcribe && !appState.customTerminology.isEmpty {
                                TerminologyToggle(isEnabled: $appState.enableTerminologyCorrection)
                            }
                            
                            // Output mode toggle (paste vs chat)
                            if appState.recordingMode != .askGPT {
                                OutputModeToggle(autoPaste: $appState.autoPasteResult)
                            }
                        }
                    }
                    
                    Text("Esc/Q — cancel")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 360, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    outputBorderColor,
                    lineWidth: appState.recordingMode == .askGPT ? 0 : 3
                )
        )
    }
    
    /// Border color based on output mode
    private var outputBorderColor: Color {
        if appState.recordingMode == .askGPT {
            return .clear // Ask mode always shows in chat, no border needed
        }
        return appState.autoPasteResult ? .green : .cyan
    }
    
    private var iconName: String {
        switch appState.processingState {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        case .processing:
            return "brain.head.profile"
        case .showingResult:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch appState.processingState {
        case .idle:
            return .primary
        case .recording:
            return .red
        case .transcribing:
            return .green
        case .processing:
            return .blue
        case .showingResult:
            return .green
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch appState.processingState {
        case .idle:
            return "Ready"
        case .recording:
            return "Listening..."
        case .transcribing:
            return "Transcribing..."
        case .processing:
            return "Processing..."
        case .showingResult:
            return "Done"
        case .error:
            return "Error"
        }
    }
    
    private var subtitleText: String {
        let hotkey = currentHotkeyDisplayString()
        switch appState.processingState {
        case .idle:
            return "Press 🌐🌐 or \(hotkey) to start"
        case .recording:
            return "Speak now • Press 🌐🌐 or \(hotkey) to finish"
        case .transcribing:
            return "Converting speech to text..."
        case .processing:
            return "Refining with AI..."
        case .showingResult:
            return ""
        case .error(let msg):
            return msg
        }
    }
}

// MARK: - Audio Level Visualization

struct AudioLevelCircles: View {
    let level: Float
    
    var body: some View {
        ZStack {
            // Outer pulsing circle - reacts to audio
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.red.opacity(0.4), Color.red.opacity(0.1)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .scaleEffect(1.0 + CGFloat(level) * 0.5)
                .animation(.easeOut(duration: 0.1), value: level)
            
            // Middle circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.red.opacity(0.5), Color.red.opacity(0.2)],
                        center: .center,
                        startRadius: 10,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .scaleEffect(1.0 + CGFloat(level) * 0.3)
                .animation(.easeOut(duration: 0.08), value: level)
            
            // Inner circle
            Circle()
                .fill(Color.red.opacity(0.6))
                .frame(width: 60, height: 60)
                .scaleEffect(1.0 + CGFloat(level) * 0.15)
                .animation(.easeOut(duration: 0.05), value: level)
            
            // Audio bars
            AudioBars(level: level)
        }
    }
}

struct AudioBars: View {
    let level: Float
    let barCount = 5
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                AudioBar(
                    level: level,
                    delay: Double(index) * 0.05,
                    baseHeight: 8 + CGFloat(index % 2) * 4
                )
            }
        }
        .frame(width: 50)
    }
}

struct AudioBar: View {
    let level: Float
    let delay: Double
    let baseHeight: CGFloat
    
    @State private var animatedLevel: CGFloat = 0
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 6, height: max(baseHeight, baseHeight + animatedLevel * 25))
            .animation(.easeOut(duration: 0.1).delay(delay), value: animatedLevel)
            .onChange(of: level) { newValue in
                animatedLevel = CGFloat(newValue)
            }
    }
}

// MARK: - Language Button

struct LanguageButton: View {
    let key: String
    let label: String
    let code: String
    let currentLanguage: String
    
    var isSelected: Bool {
        currentLanguage == code
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
        )
    }
}

struct RecordingModeButton: View {
    let mode: RecordingMode
    let currentMode: RecordingMode
    @State private var isHovering = false
    
    var isSelected: Bool {
        currentMode == mode
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Text(mode.hotkey)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            Text(mode.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.purple : Color.gray.opacity(0.25))
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            Text(mode.tooltip)
                .font(.system(size: 11))
                .padding(8)
                .frame(maxWidth: 200)
        }
    }
}

struct FormattingButton: View {
    let mode: FormattingMode
    let currentMode: FormattingMode
    @State private var isHovering = false
    
    var isSelected: Bool {
        currentMode == mode
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Text(mode.hotkey)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            Text(mode.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.blue : Color.gray.opacity(0.25))
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            Text(mode.tooltip)
                .font(.system(size: 11))
                .padding(8)
                .frame(maxWidth: 200)
        }
    }
}

struct CodeLanguageButton: View {
    let mode: CodeLanguageMode
    let currentMode: CodeLanguageMode
    
    var isSelected: Bool {
        currentMode == mode
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Text(mode.hotkey)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            Text(mode.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.green : Color.gray.opacity(0.25))
        )
    }
}

struct ClipboardIndicator: View {
    let content: AppState.ClipboardContent
    @Binding var useClipboard: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            // Toggle for using clipboard
            Button(action: { useClipboard.toggle() }) {
                Image(systemName: useClipboard ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(useClipboard ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle clipboard context (V)")
            
            // Clipboard status
            HStack(spacing: 4) {
                Image(systemName: content.hasContent ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                    .font(.system(size: 10))
                    .foregroundColor(content.hasContent ? .green : .secondary)
                
                Text(content.preview)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.2))
        )
    }
}

struct TerminologyToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            HStack(spacing: 4) {
                Text("X")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                Image(systemName: isEnabled ? "text.book.closed.fill" : "text.book.closed")
                    .font(.system(size: 10))
                Text("Terms")
                    .font(.system(size: 10))
            }
            .foregroundColor(isEnabled ? .purple : .secondary)
        }
        .buttonStyle(.plain)
        .help("X: Toggle terminology correction")
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isEnabled ? Color.purple.opacity(0.2) : Color.gray.opacity(0.2))
        )
    }
}

struct OutputModeToggle: View {
    @Binding var autoPaste: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: { autoPaste.toggle() }) {
                HStack(spacing: 4) {
                    Text("O")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                    Image(systemName: autoPaste ? "doc.on.doc" : "bubble.left.and.bubble.right")
                        .font(.system(size: 10))
                    Text(autoPaste ? "Paste" : "Chat")
                        .font(.system(size: 10))
                }
                .foregroundColor(autoPaste ? .green : .cyan)
            }
            .buttonStyle(.plain)
            .help("O: Toggle output mode - Paste to app or show in chat")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.2))
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let role: String
    let content: String
    let isLast: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var isUser: Bool {
        role == "user"
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: isUser ? "person.fill" : "brain.head.profile")
                        .font(.system(size: 10))
                        .foregroundColor(isUser ? .blue : .purple)
                    Text(isUser ? "You" : "GPT")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                if isUser {
                    // User messages - simple text
                    Text(content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.15))
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    // GPT messages - render markdown with WebView
                    // Use fixed max height with internal scrolling for long content
                    MarkdownWebView(markdown: content, isDarkMode: colorScheme == .dark)
                        .frame(height: min(estimatedHeight, 400)) // Max 400px, then scroll inside
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.1))
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            if !isUser {
                Spacer(minLength: 20)
            }
        }
    }
    
    // Estimate height based on content - generous to avoid clipping
    private var estimatedHeight: CGFloat {
        let lineCount = content.components(separatedBy: "\n").count
        let charCount = content.count
        
        // Estimate wrapped lines (assuming ~45 chars per line at typical width)
        let wrappedLines = charCount / 45
        let totalLines = max(lineCount, wrappedLines)
        
        // 28px per line + base padding
        return CGFloat(totalLines) * 28 + 40
    }
}

// MARK: - Result View (for Ask GPT answers)

struct ResultView: View {
    let text: String
    @EnvironmentObject var appState: AppState
    
    private var messageCount: Int {
        appState.conversationHistory.count / 2
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.purple)
                Text("Chat with GPT")
                    .font(.system(size: 16, weight: .semibold))
                if messageCount > 0 {
                    Text("(\(messageCount) exchanges)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Scrollable conversation history
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 1).id("top")
                        
                        ForEach(Array(appState.conversationHistory.enumerated()), id: \.offset) { index, message in
                            MessageBubble(
                                role: message.role,
                                content: message.content,
                                isLast: index == appState.conversationHistory.count - 1
                            )
                            .id(index)
                        }
                        
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 600)
                .onAppear {
                    // For single exchanges (Code/Process modes), scroll to top to show full response
                    // For multi-turn conversations (Ask GPT), scroll to latest
                    if appState.conversationHistory.count <= 2 {
                        proxy.scrollTo("top", anchor: .top)
                    } else if !appState.conversationHistory.isEmpty {
                        proxy.scrollTo(appState.conversationHistory.count - 1, anchor: .bottom)
                    }
                }
                .onChange(of: appState.conversationHistory.count) { _ in
                    if !appState.conversationHistory.isEmpty {
                        withAnimation {
                            proxy.scrollTo(appState.conversationHistory.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Actions
            HStack(spacing: 10) {
                Button(action: { appState.startRecording() }) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Continue")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { appState.dismissResult(copyToClipboard: true) }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { appState.dismissResult(copyToClipboard: false) }) {
                    Text("Close")
                        .font(.system(size: 13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Text("🌐🌐 / \(currentHotkeyDisplayString()) — continue • Esc — close • C — copy last")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 550, height: 580)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        )
    }
}

// MARK: - Processing Animation

struct ProcessingAnimation: View {
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Rotating arcs
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.0, to: 0.3)
                    .stroke(
                        Color.orange.opacity(0.6 - Double(index) * 0.15),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: CGFloat(80 + index * 20), height: CGFloat(80 + index * 20))
                    .rotationEffect(.degrees(rotation + Double(index * 120)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// Window controller for the overlay
class RecordingWindowController: NSObject {
    static let shared = RecordingWindowController()
    
    private var window: NSWindow?
    private var localEventMonitor: Any?
    
    func showWindow() {
        if window == nil {
            let contentView = RecordingOverlayView()
                .environmentObject(AppState.shared)
            
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 450, height: 450)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 450),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            window.contentView = hostingView
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.center()
            
            self.window = window
        }
        
        // Add keyboard monitor for Escape and Q
        startKeyboardMonitor()
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideWindow() {
        stopKeyboardMonitor()
        window?.orderOut(nil)
    }
    
    func updatePosition() {
        window?.center()
    }
    
    // MARK: - Keyboard Monitoring
    
    private func startKeyboardMonitor() {
        stopKeyboardMonitor() // Remove any existing monitor
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let state = AppState.shared.processingState
            
            // Handle result view keys
            if case .showingResult = state {
                if event.keyCode == 53 { // Escape - close
                    Task { @MainActor in
                        AppState.shared.dismissResult(copyToClipboard: false)
                    }
                    return nil
                }
                if event.keyCode == 8 { // C - copy & close
                    Task { @MainActor in
                        AppState.shared.dismissResult(copyToClipboard: true)
                    }
                    return nil
                }
                return event
            }
            
            // Handle recording keys
            if AppState.shared.isRecording {
                // Escape key (keyCode 53) or Q key (keyCode 12) - cancel
                if event.keyCode == 53 || event.keyCode == 12 {
                    Task { @MainActor in
                        AppState.shared.cancelRecording()
                    }
                    return nil
                }
                
                // Language selection: 0 = auto, 1 = English, 2 = Russian
                if event.keyCode == 29 { // 0
                    Task { @MainActor in
                        AppState.shared.whisperLanguage = "auto"
                    }
                    return nil
                }
                if event.keyCode == 18 { // 1
                    Task { @MainActor in
                        AppState.shared.whisperLanguage = "en"
                    }
                    return nil
                }
                if event.keyCode == 19 { // 2
                    Task { @MainActor in
                        AppState.shared.whisperLanguage = "ru"
                    }
                    return nil
                }
                
                // Mode selection: T=Transcribe, A=Ask, R=Respond, C=Code, P=Process
                if event.keyCode == 17 { // T
                    Task { @MainActor in
                        AppState.shared.recordingMode = .transcribe
                    }
                    return nil
                }
                if event.keyCode == 0 { // A
                    Task { @MainActor in
                        AppState.shared.recordingMode = .askGPT
                    }
                    return nil
                }
                if event.keyCode == 15 { // R
                    Task { @MainActor in
                        AppState.shared.recordingMode = .respond
                        AppState.shared.refreshClipboard()
                    }
                    return nil
                }
                if event.keyCode == 8 { // C
                    Task { @MainActor in
                        AppState.shared.recordingMode = .code
                    }
                    return nil
                }
                if event.keyCode == 35 { // P
                    Task { @MainActor in
                        AppState.shared.recordingMode = .process
                        AppState.shared.refreshClipboard()
                    }
                    return nil
                }
                
                // V = Toggle clipboard usage
                if event.keyCode == 9 { // V
                    Task { @MainActor in
                        AppState.shared.useClipboardContext.toggle()
                    }
                    return nil
                }
                
                // O = Toggle output mode (paste vs chat)
                if event.keyCode == 31 { // O
                    Task { @MainActor in
                        AppState.shared.autoPasteResult.toggle()
                    }
                    return nil
                }
                
                // X = Toggle terminology correction (only if terms exist)
                if event.keyCode == 7 { // X
                    Task { @MainActor in
                        if !AppState.shared.customTerminology.isEmpty {
                            AppState.shared.enableTerminologyCorrection.toggle()
                        }
                    }
                    return nil
                }
                
                // Formatting mode selection (only in transcribe mode): D = Default, N = Notion, S = Slack
                if AppState.shared.recordingMode == .transcribe {
                    if event.keyCode == 2 { // D
                        Task { @MainActor in
                            AppState.shared.formattingMode = .standard
                        }
                        return nil
                    }
                    if event.keyCode == 45 { // N
                        Task { @MainActor in
                            AppState.shared.formattingMode = .notion
                        }
                        return nil
                    }
                    if event.keyCode == 1 { // S
                        Task { @MainActor in
                            AppState.shared.formattingMode = .slack
                        }
                        return nil
                    }
                }
                
                // Code language selection (only in code mode): U = Auto, Y = Python, B = Bash
                if AppState.shared.recordingMode == .code {
                    if event.keyCode == 32 { // U
                        Task { @MainActor in
                            AppState.shared.codeLanguageMode = .auto
                        }
                        return nil
                    }
                    if event.keyCode == 16 { // Y
                        Task { @MainActor in
                            AppState.shared.codeLanguageMode = .python
                        }
                        return nil
                    }
                    if event.keyCode == 11 { // B
                        Task { @MainActor in
                            AppState.shared.codeLanguageMode = .bash
                        }
                        return nil
                    }
                }
            }
            
            return event
        }
    }
    
    private func stopKeyboardMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}

#Preview {
    RecordingOverlayView()
        .environmentObject(AppState.shared)
}

