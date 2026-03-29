import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Data Models
struct GazePoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let frameId: String
    let index: Int
}

struct RegionStats: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Double
    let color: Color
}

struct HeatmapCell: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let count: Int
    let intensity: Double
}

struct FileData: Identifiable {
    let id = UUID()
    let fileName: String
    var gazePoints: [GazePoint]
    var regionStats: [RegionStats]
    var heatmapCells: [HeatmapCell]
    var xRange: (min: Double, max: Double)
    var yRange: (min: Double, max: Double)
    var totalPoints: Int
}

enum GazeRegion: String, CaseIterable {
    case bricks = "Bricks"
    case ballArea = "Ball Area"
    case paddle = "Paddle"
    
    var color: Color {
        switch self {
        case .bricks: return .red
        case .ballArea: return .blue
        case .paddle: return .green
        }
    }
}

enum VisualizationType: String, CaseIterable {
    case heatmap = "Heat Map"
    case scanpath = "Scan Path"
}

// MARK: - Main View
struct ContentView: View {
    @State private var files: [FileData] = []
    @State private var selectedFileId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var selectedFile: FileData? {
        files.first { $0.id == selectedFileId }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Breakout Eye-Tracking Analysis")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // File controls
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
                
                // Selected file content
                if let file = selectedFile {
                    FileContentView(file: file)
                }
            } else {
                Spacer()
                Text("Add one or more text files to begin analysis")
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 750, minHeight: 700)
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
                    let result = parseCSV(content)
                    let heatmap = generateHeatmap(points: result.points, xRange: result.xRange, yRange: result.yRange)
                    
                    let fileData = FileData(
                        fileName: url.lastPathComponent,
                        gazePoints: result.points,
                        regionStats: result.stats,
                        heatmapCells: heatmap,
                        xRange: result.xRange,
                        yRange: result.yRange,
                        totalPoints: result.points.count
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
    
    func parseCSV(_ content: String) -> (points: [GazePoint], stats: [RegionStats], xRange: (min: Double, max: Double), yRange: (min: Double, max: Double)) {
        let lines = content.components(separatedBy: .newlines)
        var points: [GazePoint] = []
        var pointIndex = 0
        
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
            guard values.count > 7 else { continue }
            
            let frameId = values[0]
            let gazeValues = values[6...].compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            
            var j = 0
            while j < gazeValues.count - 1 {
                points.append(GazePoint(x: gazeValues[j], y: gazeValues[j + 1], frameId: frameId, index: pointIndex))
                pointIndex += 1
                j += 2
            }
        }
        
        guard !points.isEmpty else {
            return ([], [], (0, 1), (0, 1))
        }
        
        let xValues = points.map { $0.x }
        let yValues = points.map { $0.y }
        let xMin = xValues.min() ?? 0
        let xMax = xValues.max() ?? 1
        let yMin = yValues.min() ?? 0
        let yMax = yValues.max() ?? 1
        
        var counts: [GazeRegion: Int] = [.bricks: 0, .ballArea: 0, .paddle: 0]
        
        for point in points {
            let normalized = (point.y - yMin) / (yMax - yMin) * 100
            if normalized <= 33 {
                counts[.bricks, default: 0] += 1
            } else if normalized <= 85 {
                counts[.ballArea, default: 0] += 1
            } else {
                counts[.paddle, default: 0] += 1
            }
        }
        
        let total = Double(points.count)
        let stats = GazeRegion.allCases.map { region in
            RegionStats(
                name: region.rawValue,
                percentage: Double(counts[region] ?? 0) / total * 100,
                color: region.color
            )
        }
        
        return (points, stats, (xMin, xMax), (yMin, yMax))
    }
    
    func generateHeatmap(points: [GazePoint], xRange: (min: Double, max: Double), yRange: (min: Double, max: Double), gridSize: Int = 25) -> [HeatmapCell] {
        var grid = [[Int]](repeating: [Int](repeating: 0, count: gridSize), count: gridSize)
        
        let xSpan = xRange.max - xRange.min
        let ySpan = yRange.max - yRange.min
        
        for point in points {
            let col = min(gridSize - 1, max(0, Int(((point.x - xRange.min) / xSpan) * Double(gridSize))))
            let row = min(gridSize - 1, max(0, Int(((point.y - yRange.min) / ySpan) * Double(gridSize))))
            grid[row][col] += 1
        }
        
        let maxCount = grid.flatMap { $0 }.max() ?? 1
        
        var cells: [HeatmapCell] = []
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let count = grid[row][col]
                if count > 0 {
                    cells.append(HeatmapCell(
                        row: row,
                        col: col,
                        count: count,
                        intensity: Double(count) / Double(maxCount)
                    ))
                }
            }
        }
        
        return cells
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

// MARK: - File Content View
struct FileContentView: View {
    let file: FileData
    @State private var selectedViz: VisualizationType = .heatmap
    
    var body: some View {
        VStack(spacing: 16) {
            // Stats cards
            HStack(spacing: 20) {
                ForEach(file.regionStats) { stat in
                    StatCard(stat: stat)
                }
            }
            .padding(.horizontal)
            
            // Visualization picker
            Picker("Visualization", selection: $selectedViz) {
                ForEach(VisualizationType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type as VisualizationType)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Selected visualization
            Group {
                switch selectedViz {
                case .heatmap:
                    HeatmapView(cells: file.heatmapCells)
                case .scanpath:
                    ScanpathView(points: file.gazePoints, xRange: file.xRange, yRange: file.yRange)
                }
            }
            .frame(height: 350)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
            .padding(.horizontal)
            
            // Summary
            VStack(spacing: 8) {
                Text("Total gaze points analyzed: \(file.totalPoints)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let maxRegion = file.regionStats.max(by: { $0.percentage < $1.percentage }) {
                    Text("Players spend most time looking at the **\(maxRegion.name)** (\(String(format: "%.1f", maxRegion.percentage))%)")
                        .font(.headline)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.2)))
                }
            }
        }
    }
}

// MARK: - Heatmap View
struct HeatmapView: View {
    let cells: [HeatmapCell]
    let gridSize = 25
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Gaze Heatmap")
                .font(.headline)
            
            HStack(spacing: 4) {
                GeometryReader { geo in
                    let cellWidth = geo.size.width / CGFloat(gridSize)
                    let cellHeight = geo.size.height / CGFloat(gridSize)
                    
                    ZStack {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.red.opacity(0.1))
                                .frame(height: geo.size.height * 0.33)
                                .overlay(Text("BRICKS").font(.caption).foregroundColor(.red.opacity(0.5)))
                            Rectangle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: geo.size.height * 0.52)
                                .overlay(Text("BALL AREA").font(.caption).foregroundColor(.blue.opacity(0.5)))
                            Rectangle()
                                .fill(Color.green.opacity(0.1))
                                .frame(height: geo.size.height * 0.15)
                                .overlay(Text("PADDLE").font(.caption).foregroundColor(.green.opacity(0.5)))
                        }
                        
                        ForEach(cells) { cell in
                            Rectangle()
                                .fill(heatColor(intensity: cell.intensity))
                                .frame(width: cellWidth, height: cellHeight)
                                .position(
                                    x: CGFloat(cell.col) * cellWidth + cellWidth / 2,
                                    y: CGFloat(cell.row) * cellHeight + cellHeight / 2
                                )
                        }
                    }
                }
                .border(Color.gray.opacity(0.5))
                
                VStack {
                    Text("High").font(.caption2)
                    LinearGradient(
                        colors: [.red, .yellow, .green, .blue.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 20, height: 150)
                    .cornerRadius(4)
                    Text("Low").font(.caption2)
                }
                .padding(.leading, 8)
            }
        }
    }
    
    func heatColor(intensity: Double) -> Color {
        if intensity > 0.75 {
            return Color.red.opacity(0.9)
        } else if intensity > 0.5 {
            return Color.orange.opacity(0.8)
        } else if intensity > 0.25 {
            return Color.yellow.opacity(0.7)
        } else {
            return Color.blue.opacity(0.3 + intensity)
        }
    }
}

// MARK: - Scanpath View
struct ScanpathView: View {
    let points: [GazePoint]
    let xRange: (min: Double, max: Double)
    let yRange: (min: Double, max: Double)
    @State private var showPoints = true
    @State private var showLines = true
    @State private var pointLimit = 500
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Scan Path (Eye Movement Over Time)")
                    .font(.headline)
                Spacer()
                Toggle("Points", isOn: $showPoints)
                Toggle("Lines", isOn: $showLines)
            }
            
            HStack {
                Text("Points to display: \(pointLimit)")
                    .font(.caption)
                Slider(value: Binding(
                    get: { Double(pointLimit) },
                    set: { pointLimit = Int($0) }
                ), in: 100...min(5000, Double(points.count)), step: 100)
            }
            
            GeometryReader { geo in
                let limitedPoints = Array(points.prefix(pointLimit))
                let xSpan = xRange.max - xRange.min
                let ySpan = yRange.max - yRange.min
                
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.red.opacity(0.1))
                            .frame(height: geo.size.height * 0.33)
                        Rectangle().fill(Color.blue.opacity(0.1))
                            .frame(height: geo.size.height * 0.52)
                        Rectangle().fill(Color.green.opacity(0.1))
                            .frame(height: geo.size.height * 0.15)
                    }
                    
                    if showLines {
                        Path { path in
                            for (i, point) in limitedPoints.enumerated() {
                                let x = CGFloat((point.x - xRange.min) / xSpan) * geo.size.width
                                let y = CGFloat((point.y - yRange.min) / ySpan) * geo.size.height
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                        .opacity(0.6)
                    }
                    
                    if showPoints {
                        ForEach(Array(limitedPoints.enumerated()), id: \.element.id) { index, point in
                            let x = CGFloat((point.x - xRange.min) / xSpan) * geo.size.width
                            let y = CGFloat((point.y - yRange.min) / ySpan) * geo.size.height
                            let progress = Double(index) / Double(limitedPoints.count)
                            
                            Circle()
                                .fill(timeColor(progress: progress))
                                .frame(width: 4, height: 4)
                                .position(x: x, y: y)
                        }
                    }
                    
                    if let first = limitedPoints.first {
                        let x = CGFloat((first.x - xRange.min) / xSpan) * geo.size.width
                        let y = CGFloat((first.y - yRange.min) / ySpan) * geo.size.height
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Text("S").font(.system(size: 8)).foregroundColor(.white))
                            .position(x: x, y: y)
                    }
                    
                    if let last = limitedPoints.last, limitedPoints.count > 1 {
                        let x = CGFloat((last.x - xRange.min) / xSpan) * geo.size.width
                        let y = CGFloat((last.y - yRange.min) / ySpan) * geo.size.height
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .overlay(Text("E").font(.system(size: 8)).foregroundColor(.white))
                            .position(x: x, y: y)
                    }
                }
                .border(Color.gray.opacity(0.5))
            }
            
            HStack {
                Circle().fill(Color.green).frame(width: 10, height: 10)
                Text("Start").font(.caption2)
                Spacer().frame(width: 20)
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Text("End").font(.caption2)
                Spacer().frame(width: 20)
                Text("Color: Blue → Purple → Red (time progression)").font(.caption2)
            }
        }
    }
    
    func timeColor(progress: Double) -> Color {
        if progress < 0.33 {
            return .blue
        } else if progress < 0.66 {
            return .purple
        } else {
            return .red
        }
    }
}

// MARK: - Stat Card View
struct StatCard: View {
    let stat: RegionStats
    
    var body: some View {
        VStack {
            Text(String(format: "%.1f%%", stat.percentage))
                .font(.title)
                .fontWeight(.bold)
            Text(stat.name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 120)
        .background(RoundedRectangle(cornerRadius: 12).fill(stat.color.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stat.color, lineWidth: 2))
    }
}

// MARK: - App Entry Point
@main
struct BreakoutGazeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
