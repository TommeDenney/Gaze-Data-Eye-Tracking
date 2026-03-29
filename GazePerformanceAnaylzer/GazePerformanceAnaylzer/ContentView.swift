import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Data Models
struct FrameData: Identifiable {
    let id = UUID()
    let frameId: String
    let duration: Double
    let gazePoints: [CGPoint]
    let score: Int
    let frameIndex: Int
    let isLookingAtCharacter: Bool
}

struct CharacterLookEvent: Identifiable {
    let id = UUID()
    let startFrame: Int
    let endFrame: Int
    let duration: Double // ms
    let scoreAtStart: Int
    let scoreAtEnd: Int
}

struct PerformanceCorrelation: Identifiable {
    let id = UUID()
    let gazePercentage: Double // % time looking at character
    let scoreChange: Double
    let segment: String
}

struct FileData: Identifiable {
    let id = UUID()
    let fileName: String
    var frames: [FrameData]
    var lookEvents: [CharacterLookEvent]
    var totalGazeTime: Double
    var characterGazeTime: Double
    var characterGazePercentage: Double
    var correlationData: [PerformanceCorrelation]
    var avgScore: Double
    var finalScore: Int
}

enum VisualizationType: String, CaseIterable {
    case gazeFrequency = "Gaze Frequency"
    case gazeTimeline = "Gaze Timeline"
    case performanceCorrelation = "Performance Correlation"
}

// MARK: - Main View
struct ContentView: View {
    @State private var files: [FileData] = []
    @State private var selectedFileId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedViz: VisualizationType = .gazeFrequency
    
    // Character region configuration (adjustable)
    @State private var characterYMin: Double = 85
    @State private var characterYMax: Double = 100
    
    var selectedFile: FileData? {
        files.first { $0.id == selectedFileId }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Character Gaze & Performance Analysis")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("When do players look at their controlled character and how does it affect performance?")
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
                
                // Stats summary
                if let file = selectedFile {
                    SummaryCardsView(file: file)
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
                    case .gazeFrequency:
                        GazeFrequencyView(files: files)
                    case .gazeTimeline:
                        if let file = selectedFile {
                            GazeTimelineView(file: file)
                        }
                    case .performanceCorrelation:
                        PerformanceCorrelationView(files: files)
                    }
                }
                .frame(minHeight: 350)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                .padding(.horizontal)
                
            } else {
                Spacer()
                Text("Add one or more data files to analyze character gaze patterns")
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
                    let fileData = analyzeFile(content: content, fileName: url.lastPathComponent)
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
    
    func analyzeFile(content: String, fileName: String) -> FileData {
        let lines = content.components(separatedBy: .newlines)
        var frames: [FrameData] = []
        var allYValues: [Double] = []
        
        // First pass: collect all Y values to determine range
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            var j = 0
            while j < gazeValues.count - 1 {
                allYValues.append(gazeValues[j + 1])
                j += 2
            }
        }
        
        let yMin = allYValues.min() ?? 0
        let yMax = allYValues.max() ?? 1
        let ySpan = yMax - yMin
        
        // Character region: bottom 15% of screen (paddle area)
        let characterThreshold = yMin + (ySpan * 0.85)
        
        // Second pass: parse frames and detect character looks
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let frameId = values[0]
            let score = Int(values[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let duration = Double(values[3].trimmingCharacters(in: .whitespaces)) ?? 0
            
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            var gazePoints: [CGPoint] = []
            var isLookingAtCharacter = false
            
            var j = 0
            while j < gazeValues.count - 1 {
                let point = CGPoint(x: gazeValues[j], y: gazeValues[j + 1])
                gazePoints.append(point)
                
                // Check if looking at character (bottom region)
                if point.y >= characterThreshold {
                    isLookingAtCharacter = true
                }
                j += 2
            }
            
            frames.append(FrameData(
                frameId: frameId,
                duration: duration,
                gazePoints: gazePoints,
                score: score,
                frameIndex: frames.count,
                isLookingAtCharacter: isLookingAtCharacter
            ))
        }
        
        // Calculate look events (consecutive frames looking at character)
        var lookEvents: [CharacterLookEvent] = []
        var eventStart: Int? = nil
        var eventDuration: Double = 0
        var startScore = 0
        
        for (index, frame) in frames.enumerated() {
            if frame.isLookingAtCharacter {
                if eventStart == nil {
                    eventStart = index
                    startScore = frame.score
                    eventDuration = 0
                }
                eventDuration += frame.duration
            } else {
                if let start = eventStart {
                    lookEvents.append(CharacterLookEvent(
                        startFrame: start,
                        endFrame: index - 1,
                        duration: eventDuration,
                        scoreAtStart: startScore,
                        scoreAtEnd: frames[index - 1].score
                    ))
                    eventStart = nil
                }
            }
        }
        
        // Calculate totals
        let totalGazeTime = frames.map { $0.duration }.reduce(0, +)
        let characterGazeTime = frames.filter { $0.isLookingAtCharacter }.map { $0.duration }.reduce(0, +)
        let characterGazePercentage = totalGazeTime > 0 ? (characterGazeTime / totalGazeTime) * 100 : 0
        
        // Calculate correlation data (divide game into segments)
        var correlationData: [PerformanceCorrelation] = []
        let segmentSize = max(1, frames.count / 5)
        
        for i in 0..<5 {
            let startIdx = i * segmentSize
            let endIdx = min((i + 1) * segmentSize, frames.count)
            guard startIdx < frames.count else { break }
            
            let segmentFrames = Array(frames[startIdx..<endIdx])
            let segmentCharacterTime = segmentFrames.filter { $0.isLookingAtCharacter }.map { $0.duration }.reduce(0, +)
            let segmentTotalTime = segmentFrames.map { $0.duration }.reduce(0, +)
            let gazePercent = segmentTotalTime > 0 ? (segmentCharacterTime / segmentTotalTime) * 100 : 0
            
            let scoreChange = Double((segmentFrames.last?.score ?? 0) - (segmentFrames.first?.score ?? 0))
            
            correlationData.append(PerformanceCorrelation(
                gazePercentage: gazePercent,
                scoreChange: scoreChange,
                segment: "Seg \(i + 1)"
            ))
        }
        
        let avgScore = frames.isEmpty ? 0 : Double(frames.map { $0.score }.reduce(0, +)) / Double(frames.count)
        let finalScore = frames.last?.score ?? 0
        
        return FileData(
            fileName: fileName,
            frames: frames,
            lookEvents: lookEvents,
            totalGazeTime: totalGazeTime,
            characterGazeTime: characterGazeTime,
            characterGazePercentage: characterGazePercentage,
            correlationData: correlationData,
            avgScore: avgScore,
            finalScore: finalScore
        )
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

// MARK: - Summary Cards View
struct SummaryCardsView: View {
    let file: FileData
    
    var body: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "Character Gaze",
                value: String(format: "%.1f%%", file.characterGazePercentage),
                subtitle: "of total time",
                color: .blue
            )
            SummaryCard(
                title: "Look Events",
                value: "\(file.lookEvents.count)",
                subtitle: "times looked",
                color: .purple
            )
            SummaryCard(
                title: "Avg Event Duration",
                value: String(format: "%.0fms", file.lookEvents.isEmpty ? 0 : file.lookEvents.map { $0.duration }.reduce(0, +) / Double(file.lookEvents.count)),
                subtitle: "per look",
                color: .orange
            )
            SummaryCard(
                title: "Final Score",
                value: "\(file.finalScore)",
                subtitle: "points",
                color: .green
            )
        }
        .padding(.horizontal)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 2))
    }
}

// MARK: - Gaze Frequency View
struct GazeFrequencyView: View {
    let files: [FileData]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Character Gaze Frequency Across Players")
                .font(.headline)
            
            Text("Percentage of time each player spent looking at their controlled character")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Chart(files) { file in
                BarMark(
                    x: .value("Player", file.fileName),
                    y: .value("Gaze %", file.characterGazePercentage)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(8)
                .annotation(position: .top) {
                    Text(String(format: "%.1f%%", file.characterGazePercentage))
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .chartYScale(domain: 0...max(10, (files.map { $0.characterGazePercentage }.max() ?? 10) * 1.2))
            .chartYAxisLabel("Time Looking at Character (%)")
            
            // Frequency breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Look Event Breakdown")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.top)
                
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(files) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.fileName)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                Text("\(file.lookEvents.count) look events")
                                    .font(.caption2)
                                Text(String(format: "%.0fms avg duration", file.lookEvents.isEmpty ? 0 : file.lookEvents.map { $0.duration }.reduce(0, +) / Double(file.lookEvents.count)))
                                    .font(.caption2)
                                Text("Score: \(file.finalScore)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
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

// MARK: - Gaze Timeline View
struct GazeTimelineView: View {
    let file: FileData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Character Gaze Timeline")
                .font(.headline)
            
            Text("When during gameplay did the player look at their character?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            GeometryReader { geo in
                let totalFrames = file.frames.count
                
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 60)
                    
                    // Character look events
                    ForEach(file.lookEvents) { event in
                        let startX = CGFloat(event.startFrame) / CGFloat(totalFrames) * geo.size.width
                        let width = CGFloat(event.endFrame - event.startFrame + 1) / CGFloat(totalFrames) * geo.size.width
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: max(2, width), height: 60)
                            .offset(x: startX)
                    }
                }
                .frame(height: 60)
            }
            .frame(height: 60)
            
            // Timeline labels
            HStack {
                Text("Game Start")
                    .font(.caption2)
                Spacer()
                Text("Game End")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            
            // Score progression with character looks overlay
            Text("Score Progression & Character Looks")
                .font(.subheadline)
                .fontWeight(.bold)
                .padding(.top)
            
            Chart {
                ForEach(file.frames.enumerated().filter { $0.offset % 10 == 0 }.map { $0 }, id: \.element.id) { index, frame in
                    LineMark(
                        x: .value("Frame", index),
                        y: .value("Score", frame.score)
                    )
                    .foregroundStyle(Color.green)
                }
                
                // Mark character look events
                ForEach(file.lookEvents) { event in
                    RectangleMark(
                        xStart: .value("Start", event.startFrame),
                        xEnd: .value("End", event.endFrame),
                        yStart: .value("Bottom", 0),
                        yEnd: .value("Top", file.frames.map { $0.score }.max() ?? 100)
                    )
                    .foregroundStyle(Color.blue.opacity(0.2))
                }
            }
            .chartXAxisLabel("Frame")
            .chartYAxisLabel("Score")
            .frame(height: 150)
            
            HStack {
                Circle().fill(Color.green).frame(width: 10, height: 10)
                Text("Score").font(.caption2)
                Spacer().frame(width: 20)
                Rectangle().fill(Color.blue.opacity(0.3)).frame(width: 20, height: 10)
                Text("Looking at Character").font(.caption2)
            }
        }
    }
}

// MARK: - Performance Correlation View
struct PerformanceCorrelationView: View {
    let files: [FileData]
    
    var allCorrelationPoints: [(gazePercent: Double, scoreChange: Double, fileName: String)] {
        files.flatMap { file in
            file.correlationData.map { (gazePercent: $0.gazePercentage, scoreChange: $0.scoreChange, fileName: file.fileName) }
        }
    }
    
    var correlation: Double {
        let points = allCorrelationPoints
        guard points.count > 1 else { return 0 }
        
        let n = Double(points.count)
        let sumX = points.map { $0.gazePercent }.reduce(0, +)
        let sumY = points.map { $0.scoreChange }.reduce(0, +)
        let sumXY = points.map { $0.gazePercent * $0.scoreChange }.reduce(0, +)
        let sumX2 = points.map { $0.gazePercent * $0.gazePercent }.reduce(0, +)
        let sumY2 = points.map { $0.scoreChange * $0.scoreChange }.reduce(0, +)
        
        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))
        
        return denominator == 0 ? 0 : numerator / denominator
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Performance Correlation")
                .font(.headline)
            
            Text("Is looking at your character correlated with better or worse performance?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Scatter plot
            Chart {
                ForEach(files) { file in
                    ForEach(file.correlationData) { point in
                        PointMark(
                            x: .value("Character Gaze %", point.gazePercentage),
                            y: .value("Score Change", point.scoreChange)
                        )
                        .foregroundStyle(by: .value("Player", file.fileName))
                    }
                }
            }
            .chartXAxisLabel("Time Looking at Character (%)")
            .chartYAxisLabel("Score Change")
            .frame(height: 200)
            
            // Correlation coefficient
            HStack {
                Text("Correlation Coefficient (r):")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(String(format: "%.3f", correlation))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(correlationColor)
                
                Spacer()
                
                Text(correlationInterpretation)
                    .font(.caption)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2)))
            }
            .padding(.top)
            
            // Summary table
            VStack(alignment: .leading, spacing: 8) {
                Text("Player Summary")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.top)
                
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(files) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.fileName)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                Text(String(format: "Gaze: %.1f%%", file.characterGazePercentage))
                                    .font(.caption2)
                                Text("Final Score: \(file.finalScore)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.1)))
                        }
                    }
                }
            }
        }
    }
    
    var correlationInterpretation: String {
        let r = abs(correlation)
        let direction = correlation >= 0 ? "positive" : "negative"
        
        if r < 0.1 {
            return "No correlation"
        } else if r < 0.3 {
            return "Weak \(direction) correlation"
        } else if r < 0.5 {
            return "Moderate \(direction) correlation"
        } else if r < 0.7 {
            return "Strong \(direction) correlation"
        } else {
            return "Very strong \(direction) correlation"
        }
    }
    
    var correlationColor: Color {
        if correlation > 0 {
            return .green
        } else if correlation < 0 {
            return .red
        } else {
            return .gray
        }
    }
}

// MARK: - App Entry Point
@main
struct CharacterGazeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
