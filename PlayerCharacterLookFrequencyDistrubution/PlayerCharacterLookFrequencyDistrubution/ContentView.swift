import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Data Models
struct GazePoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let frameIndex: Int
    let isLookingAtCharacter: Bool
    let timestamp: Double // cumulative ms
}

struct FileData: Identifiable {
    let id = UUID()
    let fileName: String
    let gazePoints: [GazePoint]
    let characterGazePercent: Double
    let lookEventCount: Int
    let finalScore: Int
    let totalDuration: Double
    let xRange: (min: Double, max: Double)
    let yRange: (min: Double, max: Double)
}

enum VisualizationType: String, CaseIterable {
    case scanPath = "Scan Path"
    case timeline = "Gaze Timeline"
}

// MARK: - Main View
struct ContentView: View {
    @State private var files: [FileData] = []
    @State private var selectedFileId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedViz: VisualizationType = .scanPath
    
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
        .frame(minWidth: 800, minHeight: 700)
    }
    
    var headerSection: some View {
        VStack(spacing: 4) {
            Text("Character Gaze Visualizer")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("When and how often do players look at their controlled character?")
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
        HStack(spacing: 16) {
            StatCard(title: "Character Gaze", value: String(format: "%.1f%%", file.characterGazePercent), color: .orange)
            StatCard(title: "Look Events", value: "\(file.lookEventCount)", color: .purple)
            StatCard(title: "Final Score", value: "\(file.finalScore)", color: .green)
            StatCard(title: "Duration", value: String(format: "%.0fs", file.totalDuration / 1000), color: .blue)
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
            case .scanPath:
                ScanPathView(file: file)
            case .timeline:
                TimelineView(file: file)
            }
        }
        .frame(minHeight: 400)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
        .padding(.horizontal)
    }
    
    var emptyStateView: some View {
        VStack {
            Spacer()
            Text("Add gaze data files to visualize character-looking behavior")
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
        var gazePoints: [GazePoint] = []
        var allX: [Double] = []
        var allY: [Double] = []
        var cumulativeTime: Double = 0
        var finalScore = 0
        
        // First pass: collect all coordinates
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            var j = 0
            while j < gazeValues.count - 1 {
                allX.append(gazeValues[j])
                allY.append(gazeValues[j + 1])
                j += 2
            }
        }
        
        let xMin = allX.min() ?? 0
        let xMax = allX.max() ?? 1
        let yMin = allY.min() ?? 0
        let yMax = allY.max() ?? 1
        let xSpan = xMax - xMin
        let ySpan = yMax - yMin
        
        // Character region: center 30% of screen (for Pac-Man style games)
        let xCenterMin = xMin + xSpan * 0.35
        let xCenterMax = xMin + xSpan * 0.65
        let yCenterMin = yMin + ySpan * 0.35
        let yCenterMax = yMin + ySpan * 0.65
        
        // Second pass: create gaze points
        var frameIndex = 0
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let score = Int(values[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let duration = Double(values[3].trimmingCharacters(in: .whitespaces)) ?? 0
            finalScore = score
            
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard gazeValues.count >= 2 else { continue }
            
            // Take first gaze point of frame (to avoid too many points)
            let x = gazeValues[0]
            let y = gazeValues[1]
            
            let isLookingAtCharacter = x >= xCenterMin && x <= xCenterMax && y >= yCenterMin && y <= yCenterMax
            
            gazePoints.append(GazePoint(
                x: x,
                y: y,
                frameIndex: frameIndex,
                isLookingAtCharacter: isLookingAtCharacter,
                timestamp: cumulativeTime
            ))
            
            cumulativeTime += duration
            frameIndex += 1
        }
        
        // Calculate stats
        let totalDuration = cumulativeTime
        let characterPoints = gazePoints.filter { $0.isLookingAtCharacter }.count
        let characterPercent = gazePoints.isEmpty ? 0 : (Double(characterPoints) / Double(gazePoints.count)) * 100
        
        // Count look events
        var lookEvents = 0
        var wasLooking = false
        for point in gazePoints {
            if point.isLookingAtCharacter && !wasLooking {
                lookEvents += 1
            }
            wasLooking = point.isLookingAtCharacter
        }
        
        return FileData(
            fileName: fileName,
            gazePoints: gazePoints,
            characterGazePercent: characterPercent,
            lookEventCount: lookEvents,
            finalScore: finalScore,
            totalDuration: totalDuration,
            xRange: (xMin, xMax),
            yRange: (yMin, yMax)
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

// MARK: - Scan Path View
struct ScanPathView: View {
    let file: FileData
    @State private var pointsToShow: Double = 500
    
    var displayPoints: [GazePoint] {
        let step = max(1, file.gazePoints.count / Int(pointsToShow))
        return stride(from: 0, to: file.gazePoints.count, by: step).map { file.gazePoints[$0] }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gaze Scan Path")
                .font(.headline)
            
            Text("Eye movement trajectory — Orange = looking at character, Blue = looking elsewhere")
                .font(.caption)
                .foregroundColor(.secondary)
            
            sliderSection
            
            canvasSection
            
            legendSection
        }
    }
    
    var sliderSection: some View {
        HStack {
            Text("Points: \(Int(pointsToShow))")
                .font(.caption)
            Slider(value: $pointsToShow, in: 100...min(2000, Double(file.gazePoints.count)), step: 100)
        }
    }
    
    var canvasSection: some View {
        GeometryReader { geo in
            let xSpan = file.xRange.max - file.xRange.min
            let ySpan = file.yRange.max - file.yRange.min
            
            ZStack {
                // Background with character region highlighted
                characterRegionOverlay(geo: geo)
                
                // Draw lines connecting points
                pathLines(geo: geo, xSpan: xSpan, ySpan: ySpan)
                
                // Draw points
                pathPoints(geo: geo, xSpan: xSpan, ySpan: ySpan)
                
                // Start and end markers
                startEndMarkers(geo: geo, xSpan: xSpan, ySpan: ySpan)
            }
        }
        .frame(height: 280)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }
    
    func characterRegionOverlay(geo: GeometryProxy) -> some View {
        // Center 30% region
        let regionWidth = geo.size.width * 0.3
        let regionHeight = geo.size.height * 0.3
        let regionX = (geo.size.width - regionWidth) / 2
        let regionY = (geo.size.height - regionHeight) / 2
        
        return Rectangle()
            .fill(Color.orange.opacity(0.15))
            .frame(width: regionWidth, height: regionHeight)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .overlay(
                Text("CHARACTER\nREGION")
                    .font(.caption2)
                    .foregroundColor(.orange.opacity(0.5))
                    .multilineTextAlignment(.center)
            )
    }
    
    func pathLines(geo: GeometryProxy, xSpan: Double, ySpan: Double) -> some View {
        Path { path in
            for (i, point) in displayPoints.enumerated() {
                let x = CGFloat((point.x - file.xRange.min) / xSpan) * geo.size.width
                let y = CGFloat((point.y - file.yRange.min) / ySpan) * geo.size.height
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
    }
    
    func pathPoints(geo: GeometryProxy, xSpan: Double, ySpan: Double) -> some View {
        ForEach(displayPoints) { point in
            let x = CGFloat((point.x - file.xRange.min) / xSpan) * geo.size.width
            let y = CGFloat((point.y - file.yRange.min) / ySpan) * geo.size.height
            
            Circle()
                .fill(point.isLookingAtCharacter ? Color.orange : Color.blue)
                .frame(width: 4, height: 4)
                .position(x: x, y: y)
        }
    }
    
    func startEndMarkers(geo: GeometryProxy, xSpan: Double, ySpan: Double) -> some View {
        let firstPoint = displayPoints.first
        let lastPoint = displayPoints.last
        
        return ZStack {
            if let first = firstPoint {
                let x = CGFloat((first.x - file.xRange.min) / xSpan) * geo.size.width
                let y = CGFloat((first.y - file.yRange.min) / ySpan) * geo.size.height
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 14, height: 14)
                    .overlay(Text("S").font(.system(size: 8)).foregroundColor(.white))
                    .position(x: x, y: y)
            }
            
            if let last = lastPoint, displayPoints.count > 1 {
                let x = CGFloat((last.x - file.xRange.min) / xSpan) * geo.size.width
                let y = CGFloat((last.y - file.yRange.min) / ySpan) * geo.size.height
                
                Circle()
                    .fill(Color.red)
                    .frame(width: 14, height: 14)
                    .overlay(Text("E").font(.system(size: 8)).foregroundColor(.white))
                    .position(x: x, y: y)
            }
        }
    }
    
    var legendSection: some View {
        HStack(spacing: 20) {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 10, height: 10)
                Text("Start").font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Text("End").font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 10, height: 10)
                Text("Looking at Character").font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 10, height: 10)
                Text("Looking Elsewhere").font(.caption2)
            }
        }
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    let file: FileData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gaze Timeline")
                .font(.headline)
            
            Text("When during gameplay did the player look at their character?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            timelineBar
            
            timeLabels
            
            statsBreakdown
            
            interpretationSection
        }
    }
    
    var timelineBar: some View {
        GeometryReader { geo in
            let totalPoints = file.gazePoints.count
            
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.3))
                
                // Character gaze segments
                ForEach(getCharacterSegments(), id: \.start) { segment in
                    let startX = CGFloat(segment.start) / CGFloat(totalPoints) * geo.size.width
                    let width = CGFloat(segment.end - segment.start) / CGFloat(totalPoints) * geo.size.width
                    
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: max(2, width))
                        .offset(x: startX)
                }
            }
        }
        .frame(height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    var timeLabels: some View {
        HStack {
            Text("Start")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.0fs", file.totalDuration / 2000))
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.0fs", file.totalDuration / 1000))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    var statsBreakdown: some View {
        HStack(spacing: 30) {
            VStack {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.orange).frame(width: 20, height: 12).cornerRadius(2)
                    Text("Character").font(.caption)
                }
                Text(String(format: "%.1f%%", file.characterGazePercent))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
            
            VStack {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.blue.opacity(0.5)).frame(width: 20, height: 12).cornerRadius(2)
                    Text("Elsewhere").font(.caption)
                }
                Text(String(format: "%.1f%%", 100 - file.characterGazePercent))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            VStack {
                Text("Look Events").font(.caption)
                Text("\(file.lookEventCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
    }
    
    var interpretationSection: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            Text(interpretationText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
    }
    
    var interpretationText: String {
        if file.characterGazePercent < 5 {
            return "Player rarely looks at their character (<5%), relying on peripheral vision for position awareness."
        } else if file.characterGazePercent < 15 {
            return "Player occasionally glances at character (\(file.lookEventCount) times), likely during critical moments or repositioning."
        } else {
            return "Player frequently monitors their character (\(String(format: "%.0f%%", file.characterGazePercent))), actively tracking their position."
        }
    }
    
    func getCharacterSegments() -> [(start: Int, end: Int)] {
        var segments: [(start: Int, end: Int)] = []
        var segmentStart: Int? = nil
        
        for (i, point) in file.gazePoints.enumerated() {
            if point.isLookingAtCharacter {
                if segmentStart == nil {
                    segmentStart = i
                }
            } else {
                if let start = segmentStart {
                    segments.append((start: start, end: i))
                    segmentStart = nil
                }
            }
        }
        
        if let start = segmentStart {
            segments.append((start: start, end: file.gazePoints.count))
        }
        
        return segments
    }
}

// MARK: - App Entry
@main
struct CharacterGazeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
