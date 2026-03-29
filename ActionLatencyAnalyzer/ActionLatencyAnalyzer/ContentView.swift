import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Data Models
struct FrameData: Identifiable {
    let id = UUID()
    let frameId: String
    let duration: Double // ms
    let action: Int
    let gazePoints: [CGPoint]
    let score: Int
    let frameIndex: Int
}

struct LatencyEvent: Identifiable {
    let id = UUID()
    let frameIndex: Int
    let latency: Double // ms
    let objectType: String
    let action: Int
}

struct PlayerStats: Identifiable {
    let id = UUID()
    let fileName: String
    let avgLatency: Double
    let minLatency: Double
    let maxLatency: Double
    let stdDev: Double
    let eventCount: Int
}

struct DepthBucket: Identifiable {
    let id = UUID()
    let depthLabel: String
    let avgLatency: Double
    let eventCount: Int
    let avgScore: Double
}

struct FileData: Identifiable {
    let id = UUID()
    let fileName: String
    var frames: [FrameData]
    var latencyEvents: [LatencyEvent]
    var playerStats: PlayerStats
    var depthBuckets: [DepthBucket]
}

enum VisualizationType: String, CaseIterable {
    case latencyOverTime = "Latency Over Time"
    case latencyByDepth = "Latency by Game Depth"
    case playerComparison = "Player Comparison"
}

// MARK: - Main View
struct ContentView: View {
    @State private var files: [FileData] = []
    @State private var selectedFileId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedViz: VisualizationType = .latencyOverTime
    
    var selectedFile: FileData? {
        files.first { $0.id == selectedFileId }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Gaze-Action Latency Analysis")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("What is the latency between looking at a game object and taking action?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack {
                Button("Add File(s)") {
                    selectFiles()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                if !files.isEmpty {
                    Button("Clear All") {
                        files.removeAll()
                        selectedFileId = nil
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
            
            if isLoading {
                ProgressView("Analyzing data...")
            }
            
            if !files.isEmpty {
                // File tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(files) { file in
                            FileTab(
                                fileName: file.fileName,
                                isSelected: selectedFileId == file.id,
                                onSelect: { selectedFileId = file.id },
                                onClose: { removeFile(file.id) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Visualization picker
                Picker("Visualization", selection: $selectedViz) {
                    ForEach(VisualizationType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as VisualizationType)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Content based on visualization type
                Group {
                    switch selectedViz {
                    case .latencyOverTime:
                        if let file = selectedFile {
                            LatencyTimeView(file: file)
                        }
                    case .latencyByDepth:
                        if let file = selectedFile {
                            LatencyDepthView(file: file)
                        }
                    case .playerComparison:
                        PlayerComparisonView(files: files)
                    }
                }
                .frame(minHeight: 400)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                .padding(.horizontal)
                
                // Stats for selected file
                if let file = selectedFile, selectedViz != .playerComparison {
                    StatsCardView(stats: file.playerStats)
                }
            } else {
                Spacer()
                Text("Add one or more data files to analyze gaze-action latency")
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 800, minHeight: 750)
    }
    
    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select one or more .txt files containing gaze data"
        
        if panel.runModal() == .OK {
            loadFiles(urls: panel.urls)
        }
    }
    
    func loadFiles(urls: [URL]) {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            var newFiles: [FileData] = []
            
            for url in urls {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let frames = parseFrames(content)
                    let latencyEvents = calculateLatency(frames: frames)
                    let stats = calculateStats(events: latencyEvents, fileName: url.lastPathComponent)
                    let depthBuckets = calculateDepthBuckets(frames: frames, events: latencyEvents)
                    
                    let fileData = FileData(
                        fileName: url.lastPathComponent,
                        frames: frames,
                        latencyEvents: latencyEvents,
                        playerStats: stats,
                        depthBuckets: depthBuckets
                    )
                    newFiles.append(fileData)
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error reading \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.files.append(contentsOf: newFiles)
                if self.selectedFileId == nil, let first = self.files.first {
                    self.selectedFileId = first.id
                }
                self.isLoading = false
            }
        }
    }
    
    func removeFile(_ id: UUID) {
        files.removeAll { $0.id == id }
        if selectedFileId == id {
            selectedFileId = files.first?.id
        }
    }
    
    func parseFrames(_ content: String) -> [FrameData] {
        let lines = content.components(separatedBy: .newlines)
        var frames: [FrameData] = []
        
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let frameId = values[0]
            let score = Int(values[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let duration = Double(values[3].trimmingCharacters(in: .whitespaces)) ?? 0
            let action = Int(values[5].trimmingCharacters(in: .whitespaces)) ?? 0
            
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            var gazePoints: [CGPoint] = []
            var j = 0
            while j < gazeValues.count - 1 {
                gazePoints.append(CGPoint(x: gazeValues[j], y: gazeValues[j + 1]))
                j += 2
            }
            
            frames.append(FrameData(
                frameId: frameId,
                duration: duration,
                action: action,
                gazePoints: gazePoints,
                score: score,
                frameIndex: frames.count
            ))
        }
        
        return frames
    }
    
    func calculateLatency(frames: [FrameData]) -> [LatencyEvent] {
        var events: [LatencyEvent] = []
        
        // Detect when action changes (indicating player input)
        for i in 1..<frames.count {
            let currentAction = frames[i].action
            let prevAction = frames[i-1].action
            
            // Action changed - calculate latency from recent gaze shift
            if currentAction != prevAction && currentAction != 0 {
                // Look back to find when gaze shifted to relevant area
                var latency: Double = 0
                var lookbackFrames = min(i, 10)
                
                for j in stride(from: i-1, through: max(0, i - lookbackFrames), by: -1) {
                    latency += frames[j].duration
                    
                    // Check if gaze was in different region (simplified detection)
                    if !frames[j].gazePoints.isEmpty && !frames[i].gazePoints.isEmpty {
                        let prevGaze = frames[j].gazePoints.first!
                        let currGaze = frames[i].gazePoints.first!
                        let distance = sqrt(pow(currGaze.x - prevGaze.x, 2) + pow(currGaze.y - prevGaze.y, 2))
                        
                        if distance > 2.0 { // Significant gaze shift detected
                            break
                        }
                    }
                }
                
                events.append(LatencyEvent(
                    frameIndex: i,
                    latency: latency,
                    objectType: "Game Object",
                    action: currentAction
                ))
            }
        }
        
        return events
    }
    
    func calculateStats(events: [LatencyEvent], fileName: String) -> PlayerStats {
        guard !events.isEmpty else {
            return PlayerStats(fileName: fileName, avgLatency: 0, minLatency: 0, maxLatency: 0, stdDev: 0, eventCount: 0)
        }
        
        let latencies = events.map { $0.latency }
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        let minVal = latencies.min() ?? 0
        let maxVal = latencies.max() ?? 0
        
        let variance = latencies.map { pow($0 - avg, 2) }.reduce(0, +) / Double(latencies.count)
        let stdDev = sqrt(variance)
        
        return PlayerStats(
            fileName: fileName,
            avgLatency: avg,
            minLatency: minVal,
            maxLatency: maxVal,
            stdDev: stdDev,
            eventCount: events.count
        )
    }
    
    func calculateDepthBuckets(frames: [FrameData], events: [LatencyEvent]) -> [DepthBucket] {
        let totalFrames = frames.count
        guard totalFrames > 0 else { return [] }
        
        let bucketSize = totalFrames / 4
        var buckets: [DepthBucket] = []
        
        let labels = ["Early Game", "Mid-Early", "Mid-Late", "Late Game"]
        
        for (index, label) in labels.enumerated() {
            let startFrame = index * bucketSize
            let endFrame = index == 3 ? totalFrames : (index + 1) * bucketSize
            
            let bucketEvents = events.filter { $0.frameIndex >= startFrame && $0.frameIndex < endFrame }
            let bucketFrames = frames.filter { $0.frameIndex >= startFrame && $0.frameIndex < endFrame }
            
            let avgLatency = bucketEvents.isEmpty ? 0 : bucketEvents.map { $0.latency }.reduce(0, +) / Double(bucketEvents.count)
            let avgScore = bucketFrames.isEmpty ? 0 : Double(bucketFrames.map { $0.score }.reduce(0, +)) / Double(bucketFrames.count)
            
            buckets.append(DepthBucket(
                depthLabel: label,
                avgLatency: avgLatency,
                eventCount: bucketEvents.count,
                avgScore: avgScore
            ))
        }
        
        return buckets
    }
}

// MARK: - File Tab View
struct FileTab: View {
    let fileName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(fileName)
                .font(.caption)
                .lineLimit(1)
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
        )
        .foregroundColor(isSelected ? .white : .primary)
        .onTapGesture { onSelect() }
    }
}

// MARK: - Latency Over Time View
struct LatencyTimeView: View {
    let file: FileData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Gaze-Action Latency Over Time")
                .font(.headline)
            
            Text("Each point represents the delay between looking at a game object and taking action")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if file.latencyEvents.isEmpty {
                Text("No latency events detected in this file")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(file.latencyEvents) { event in
                    PointMark(
                        x: .value("Frame", event.frameIndex),
                        y: .value("Latency (ms)", event.latency)
                    )
                    .foregroundStyle(Color.blue)
                    
                    LineMark(
                        x: .value("Frame", event.frameIndex),
                        y: .value("Latency (ms)", event.latency)
                    )
                    .foregroundStyle(Color.blue.opacity(0.3))
                }
                .chartXAxisLabel("Frame Index (Game Progression →)")
                .chartYAxisLabel("Latency (ms)")
            }
        }
    }
}

// MARK: - Latency by Depth View
struct LatencyDepthView: View {
    let file: FileData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Latency by Game Depth")
                .font(.headline)
            
            Text("How does reaction time change as the game progresses?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Chart(file.depthBuckets) { bucket in
                BarMark(
                    x: .value("Game Phase", bucket.depthLabel),
                    y: .value("Avg Latency (ms)", bucket.avgLatency)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .yellow, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
                .annotation(position: .top) {
                    Text(String(format: "%.0fms", bucket.avgLatency))
                        .font(.caption2)
                }
            }
            .chartYAxisLabel("Average Latency (ms)")
            
            // Additional info
            HStack {
                ForEach(file.depthBuckets) { bucket in
                    VStack {
                        Text(bucket.depthLabel)
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text("\(bucket.eventCount) events")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Player Comparison View
struct PlayerComparisonView: View {
    let files: [FileData]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Latency Comparison Across Players")
                .font(.headline)
            
            Text("Compare average gaze-action latency between different players/sessions")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if files.isEmpty {
                Text("Add multiple files to compare players")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(files) { file in
                    BarMark(
                        x: .value("Player", file.fileName),
                        y: .value("Avg Latency", file.playerStats.avgLatency)
                    )
                    .foregroundStyle(Color.blue)
                    .cornerRadius(8)
                    .annotation(position: .top) {
                        Text(String(format: "%.0fms", file.playerStats.avgLatency))
                            .font(.caption2)
                    }
                }
                .chartYAxisLabel("Average Latency (ms)")
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                // Stats table
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detailed Statistics")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(files) { file in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.fileName)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .lineLimit(1)
                                    Text("Avg: \(String(format: "%.1f", file.playerStats.avgLatency))ms")
                                        .font(.caption2)
                                    Text("Min: \(String(format: "%.1f", file.playerStats.minLatency))ms")
                                        .font(.caption2)
                                    Text("Max: \(String(format: "%.1f", file.playerStats.maxLatency))ms")
                                        .font(.caption2)
                                    Text("StdDev: \(String(format: "%.1f", file.playerStats.stdDev))ms")
                                        .font(.caption2)
                                    Text("Events: \(file.playerStats.eventCount)")
                                        .font(.caption2)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Stats Card View
struct StatsCardView: View {
    let stats: PlayerStats
    
    var body: some View {
        HStack(spacing: 20) {
            StatBox(title: "Avg Latency", value: String(format: "%.1fms", stats.avgLatency), color: .blue)
            StatBox(title: "Min", value: String(format: "%.1fms", stats.minLatency), color: .green)
            StatBox(title: "Max", value: String(format: "%.1fms", stats.maxLatency), color: .red)
            StatBox(title: "Std Dev", value: String(format: "%.1fms", stats.stdDev), color: .purple)
            StatBox(title: "Events", value: "\(stats.eventCount)", color: .orange)
        }
        .padding(.horizontal)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 80)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 2))
    }
}

// MARK: - App Entry Point
@main
struct LatencyAnalyzerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
