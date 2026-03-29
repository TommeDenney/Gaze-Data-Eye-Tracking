import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Data Models
struct FrameData {
    let frameIndex: Int
    let duration: Double
    let action: Int
    let gazeX: Double
    let gazeY: Double
}

struct LatencyEvent: Identifiable {
    let id = UUID()
    let frameIndex: Int
    let latency: Double
    let gamePhase: String
}

struct FileData: Identifiable {
    let id = UUID()
    let fileName: String
    let latencyEvents: [LatencyEvent]
    let avgLatency: Double
    let minLatency: Double
    let maxLatency: Double
    let totalFrames: Int
}

enum VisualizationType: String, CaseIterable {
    case histogram = "Latency Distribution"
    case overTime = "Latency Over Game"
}

// MARK: - Main View
struct ContentView: View {
    @State private var files: [FileData] = []
    @State private var selectedFileId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedViz: VisualizationType = .histogram
    
    var selectedFile: FileData? {
        files.first { $0.id == selectedFileId }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerSection
            controlsSection
            
            if let error = errorMessage {
                Text(error).foregroundColor(.red).padding()
            }
            
            if isLoading {
                ProgressView("Analyzing data...")
            }
            
            if !files.isEmpty {
                fileTabsSection
                
                if let file = selectedFile {
                    statsSection(file: file)
                    vizPickerSection
                    visualizationSection(file: file)
                }
            } else {
                emptyStateView
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 700, minHeight: 600)
    }
    
    var headerSection: some View {
        VStack(spacing: 4) {
            Text("Gaze-Action Latency Analyzer")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Measures time between looking at something and taking action")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    var controlsSection: some View {
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
    }
    
    var fileTabsSection: some View {
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
    }
    
    func statsSection(file: FileData) -> some View {
        HStack(spacing: 20) {
            StatCard(title: "Avg Latency", value: String(format: "%.0fms", file.avgLatency), color: .blue)
            StatCard(title: "Min", value: String(format: "%.0fms", file.minLatency), color: .green)
            StatCard(title: "Max", value: String(format: "%.0fms", file.maxLatency), color: .red)
            StatCard(title: "Reactions", value: "\(file.latencyEvents.count)", color: .purple)
        }
        .padding(.horizontal)
    }
    
    var vizPickerSection: some View {
        Picker("Visualization", selection: $selectedViz) {
            ForEach(VisualizationType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
    }
    
    func visualizationSection(file: FileData) -> some View {
        Group {
            switch selectedViz {
            case .histogram:
                HistogramView(file: file)
            case .overTime:
                LatencyOverTimeView(file: file)
            }
        }
        .frame(minHeight: 300)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
        .padding(.horizontal)
    }
    
    var emptyStateView: some View {
        VStack {
            Spacer()
            Text("Add data files to analyze gaze-action latency")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
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
                    let fileData = analyzeFile(content: content, fileName: url.lastPathComponent)
                    newFiles.append(fileData)
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error: \(error.localizedDescription)"
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
    
    func analyzeFile(content: String, fileName: String) -> FileData {
        let lines = content.components(separatedBy: .newlines)
        var frames: [FrameData] = []
        
        // Parse all frames
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let duration = Double(values[3].trimmingCharacters(in: .whitespaces)) ?? 0
            let action = Int(values[5].trimmingCharacters(in: .whitespaces)) ?? 0
            
            // Get first gaze point for this frame
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let gazeX = gazeValues.count >= 2 ? gazeValues[0] : 0
            let gazeY = gazeValues.count >= 2 ? gazeValues[1] : 0
            
            frames.append(FrameData(
                frameIndex: frames.count,
                duration: duration,
                action: action,
                gazeX: gazeX,
                gazeY: gazeY
            ))
        }
        
        // Calculate latency events
        var latencyEvents: [LatencyEvent] = []
        let totalFrames = frames.count
        
        for i in 1..<frames.count {
            let curr = frames[i]
            let prev = frames[i - 1]
            
            // Detect action change (player made an input)
            if curr.action != prev.action && curr.action != 0 {
                // Look back to find when gaze shifted
                var latency: Double = 0
                let lookbackLimit = min(i, 15)
                
                for j in stride(from: i - 1, through: max(0, i - lookbackLimit), by: -1) {
                    let frame = frames[j]
                    latency += frame.duration
                    
                    // Check for significant gaze shift
                    if j > 0 {
                        let prevFrame = frames[j - 1]
                        let gazeDist = sqrt(pow(frame.gazeX - prevFrame.gazeX, 2) + pow(frame.gazeY - prevFrame.gazeY, 2))
                        if gazeDist > 0.5 {
                            break
                        }
                    }
                }
                
                // Determine game phase
                let progress = Double(i) / Double(totalFrames)
                let phase: String
                if progress < 0.33 {
                    phase = "Early"
                } else if progress < 0.66 {
                    phase = "Mid"
                } else {
                    phase = "Late"
                }
                
                latencyEvents.append(LatencyEvent(
                    frameIndex: i,
                    latency: latency,
                    gamePhase: phase
                ))
            }
        }
        
        // Calculate stats
        let latencies = latencyEvents.map { $0.latency }
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let minVal = latencies.min() ?? 0
        let maxVal = latencies.max() ?? 0
        
        return FileData(
            fileName: fileName,
            latencyEvents: latencyEvents,
            avgLatency: avg,
            minLatency: minVal,
            maxLatency: maxVal,
            totalFrames: totalFrames
        )
    }
}

// MARK: - File Tab
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

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 2))
    }
}

// MARK: - Histogram View
struct HistogramView: View {
    let file: FileData
    
    var buckets: [(range: String, count: Int)] {
        let ranges = [(0, 100), (100, 200), (200, 300), (300, 500), (500, 1000), (1000, 2000)]
        var result: [(range: String, count: Int)] = []
        
        for (low, high) in ranges {
            let count = file.latencyEvents.filter { $0.latency >= Double(low) && $0.latency < Double(high) }.count
            let label = high >= 1000 ? "\(low/1000)s+" : "\(low)-\(high)ms"
            result.append((range: label, count: count))
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reaction Time Distribution")
                .font(.headline)
            
            Text("How quickly does the player react after looking at something?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            chartView
                .frame(height: 220)
            
            interpretationText
        }
    }
    
    var chartView: some View {
        Chart {
            ForEach(buckets, id: \.range) { bucket in
                BarMark(
                    x: .value("Latency", bucket.range),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(6)
            }
        }
        .chartYAxisLabel("Number of Reactions")
    }
    
    var interpretationText: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            Text("Lower values = faster reactions. Most human reactions are 150-300ms.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
    }
}

// MARK: - Latency Over Time View
struct LatencyOverTimeView: View {
    let file: FileData
    
    var phaseAverages: [(phase: String, avg: Double)] {
        let phases = ["Early", "Mid", "Late"]
        var result: [(phase: String, avg: Double)] = []
        
        for phase in phases {
            let events = file.latencyEvents.filter { $0.gamePhase == phase }
            let avg = events.isEmpty ? 0 : events.map { $0.latency }.reduce(0, +) / Double(events.count)
            result.append((phase: phase, avg: avg))
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latency Across Game Phases")
                .font(.headline)
            
            Text("Does reaction time change as the game progresses?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            phaseChart
                .frame(height: 200)
            
            trendInterpretation
        }
    }
    
    var phaseChart: some View {
        Chart {
            ForEach(phaseAverages, id: \.phase) { item in
                BarMark(
                    x: .value("Phase", item.phase),
                    y: .value("Avg Latency", item.avg)
                )
                .foregroundStyle(phaseColor(item.phase).gradient)
                .cornerRadius(6)
            }
        }
        .chartYAxisLabel("Avg Latency (ms)")
    }
    
    var trendInterpretation: some View {
        HStack {
            Image(systemName: trendIcon)
                .foregroundColor(trendColor)
            Text(trendText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(trendColor.opacity(0.1)))
    }
    
    func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "Early": return .green
        case "Mid": return .yellow
        case "Late": return .red
        default: return .gray
        }
    }
    
    var trendIcon: String {
        let early = phaseAverages.first { $0.phase == "Early" }?.avg ?? 0
        let late = phaseAverages.first { $0.phase == "Late" }?.avg ?? 0
        
        if late < early * 0.9 {
            return "arrow.down.circle.fill"
        } else if late > early * 1.1 {
            return "arrow.up.circle.fill"
        } else {
            return "equal.circle.fill"
        }
    }
    
    var trendColor: Color {
        let early = phaseAverages.first { $0.phase == "Early" }?.avg ?? 0
        let late = phaseAverages.first { $0.phase == "Late" }?.avg ?? 0
        
        if late < early * 0.9 {
            return .green
        } else if late > early * 1.1 {
            return .red
        } else {
            return .gray
        }
    }
    
    var trendText: String {
        let early = phaseAverages.first { $0.phase == "Early" }?.avg ?? 0
        let late = phaseAverages.first { $0.phase == "Late" }?.avg ?? 0
        
        if late < early * 0.9 {
            return "Player reactions got FASTER as the game progressed (improving)"
        } else if late > early * 1.1 {
            return "Player reactions got SLOWER as the game progressed (fatigue or difficulty)"
        } else {
            return "Player reaction time stayed relatively CONSISTENT throughout"
        }
    }
}

// MARK: - App Entry
@main
struct LatencyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
