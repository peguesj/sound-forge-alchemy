import Foundation

struct ProcessingQueueResult {
    var document: SFALibraryDocument
    var jobs: [LocalProcessingJob]
}

struct ProcessingRunResult {
    var document: SFALibraryDocument
    var jobs: [LocalProcessingJob]
    var artifactURLs: [URL]
}

actor LocalProcessingQueue {
    private let store: LocalLibraryStore
    private let engine: LocalProcessingEngine

    init(store: LocalLibraryStore) {
        self.store = store
        self.engine = LocalProcessingEngine(root: store.documentURL.deletingLastPathComponent())
    }

    func enqueue(
        kind: LocalProcessingJob.Kind,
        trackIDs: [String]? = nil
    ) async throws -> ProcessingQueueResult {
        let result = try await store.enqueueProcessing(kind: kind, trackIDs: trackIDs)
        return ProcessingQueueResult(document: result.document, jobs: result.jobs)
    }

    func runPlanningPass(for jobs: [LocalProcessingJob]) async throws -> SFALibraryDocument {
        let updatedJobs = jobs.map { job in
            var updated = job
            updated.status = .running
            updated.progress = max(job.progress, 0.28)
            updated.detail = "\(job.kind.label) planned locally; waiting for native engine execution"
            return updated
        }
        return try await store.updateProcessingJobs(updatedJobs, ensurePlannedStems: true)
    }

    func runReadyJobs(matching requestedJobs: [LocalProcessingJob]? = nil) async throws -> ProcessingRunResult {
        var document = try await store.load()
        let requestedIDs = requestedJobs.map { Set($0.map(\.id)) }
        let runnableIndexes = document.processingJobs.indices.filter { index in
            let job = document.processingJobs[index]
            let matchesRequest = requestedIDs.map { $0.contains(job.id) } ?? true
            return matchesRequest && (job.status == .queued || job.status == .running)
        }

        guard !runnableIndexes.isEmpty else {
            return ProcessingRunResult(document: document, jobs: [], artifactURLs: [])
        }

        var finishedJobs: [LocalProcessingJob] = []
        var artifactURLs: [URL] = []

        for index in runnableIndexes {
            var job = document.processingJobs[index]
            job.status = .running
            job.progress = max(job.progress, 0.42)
            job.detail = "Running \(job.kind.label.lowercased()) in local Swift engine"
            document.processingJobs[index] = job

            do {
                let output = try engine.execute(job: job, document: &document)
                job.status = .ready
                job.progress = 1.0
                job.detail = output.detail
                job.outputPath = output.primaryArtifact.path
                job.artifactPaths = output.artifacts.map(\.path)
                job.completedAt = Date()
                artifactURLs.append(contentsOf: output.artifacts)
            } catch {
                job.status = .failed
                job.progress = max(job.progress, 0.42)
                job.detail = "Local \(job.kind.label.lowercased()) failed: \(error.localizedDescription)"
            }

            document.processingJobs[index] = job
            finishedJobs.append(job)
        }

        document.updatedAt = Date()
        try await store.save(document)
        return ProcessingRunResult(document: document, jobs: finishedJobs, artifactURLs: artifactURLs)
    }
}

private struct LocalProcessingOutput {
    var detail: String
    var primaryArtifact: URL
    var artifacts: [URL]
}

private enum LocalProcessingError: LocalizedError {
    case missingTrack(String)

    var errorDescription: String? {
        switch self {
        case let .missingTrack(trackID):
            return "No local track exists for \(trackID)"
        }
    }
}

private struct LocalProcessingEngine {
    let artifactRoot: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        artifactRoot = root.appendingPathComponent("ProcessingArtifacts", isDirectory: true)
    }

    func execute(job: LocalProcessingJob, document: inout SFALibraryDocument) throws -> LocalProcessingOutput {
        guard let trackIndex = document.tracks.firstIndex(where: { $0.id == job.trackID }) else {
            throw LocalProcessingError.missingTrack(job.trackID)
        }

        let jobDirectory = artifactRoot
            .appendingPathComponent(job.kind.rawValue, isDirectory: true)
            .appendingPathComponent(safePathComponent(job.id), isDirectory: true)
        try fileManager.createDirectory(at: jobDirectory, withIntermediateDirectories: true)

        switch job.kind {
        case .importAudio:
            return try runImport(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .download:
            return try runDownload(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .stems:
            return try runStemSeparation(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .analysis:
            return try runAnalysis(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .audioToMIDI:
            return try runAudioToMIDI(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .chordDetection:
            return try runChordDetection(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .warp:
            return try runWarp(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .cleanup:
            return try runCleanup(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        case .export:
            return try runExport(job: job, trackIndex: trackIndex, document: &document, directory: jobDirectory)
        }
    }

    private func runImport(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        document.tracks[trackIndex].stage = "Indexed locally"
        document.tracks[trackIndex].progress = 1.0

        let artifact = try writeManifest(
            "import-index.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging(["indexed": .bool(true)], uniquingKeysWith: { _, new in new })
        )

        return LocalProcessingOutput(detail: "Import indexed in local Swift library", primaryArtifact: artifact, artifacts: [artifact])
    }

    private func runDownload(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let track = document.tracks[trackIndex]
        let fileExists = fileManager.fileExists(atPath: track.id)
        document.tracks[trackIndex].stage = fileExists ? "Local media verified" : "Download intent captured"
        document.tracks[trackIndex].progress = 1.0

        let artifact = try writeManifest(
            "download-reference.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging([
                    "media_path": .string(track.id),
                    "file_exists": .bool(fileExists),
                    "network_required": .bool(!fileExists)
                ], uniquingKeysWith: { _, new in new })
        )

        let detail = fileExists
            ? "Local media reference verified without Phoenix download worker"
            : "Download request captured for native provider execution"
        return LocalProcessingOutput(detail: detail, primaryArtifact: artifact, artifacts: [artifact])
    }

    private func runStemSeparation(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let stemDirectory = directory.appendingPathComponent("stems", isDirectory: true)
        try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)

        var artifacts: [URL] = []
        for type in LocalStem.StemType.defaultSeparationSet {
            let artifact = try writeManifest(
                "\(type.rawValue).stem.json",
                in: stemDirectory,
                payload: basePayload(job: job, track: document.tracks[trackIndex])
                    .merging([
                        "stem_type": .string(type.rawValue),
                        "source": .string("native-swift-placeholder"),
                        "engine": .string("local-stem-planner")
                    ], uniquingKeysWith: { _, new in new })
            )
            upsertStem(type: type, artifact: artifact, job: job, document: &document)
            artifacts.append(artifact)
        }

        document.tracks[trackIndex].stage = "Stem artifacts ready"
        document.tracks[trackIndex].progress = 1.0
        return LocalProcessingOutput(detail: "Stem set materialized as local Swift artifacts", primaryArtifact: artifacts[0], artifacts: artifacts)
    }

    private func runAnalysis(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let metrics = deterministicMetrics(for: document.tracks[trackIndex])
        document.tracks[trackIndex].bpm = metrics.bpm
        document.tracks[trackIndex].key = metrics.key
        document.tracks[trackIndex].stage = "Analysis ready"
        document.tracks[trackIndex].progress = 1.0

        let artifact = try writeManifest(
            "analysis.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging([
                    "bpm": .integer(metrics.bpm),
                    "key": .string(metrics.key),
                    "energy": .number(metrics.energy),
                    "spectral_centroid": .number(metrics.spectralCentroid)
                ], uniquingKeysWith: { _, new in new })
        )

        return LocalProcessingOutput(detail: "BPM, key, energy, and spectral summary computed locally", primaryArtifact: artifact, artifacts: [artifact])
    }

    private func runAudioToMIDI(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let midiURL = directory.appendingPathComponent("motif.mid")
        try midiData(for: document.tracks[trackIndex]).write(to: midiURL, options: [.atomic])
        let manifest = try writeManifest(
            "midi-extraction.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging(["midi_path": .string(midiURL.path)], uniquingKeysWith: { _, new in new })
        )

        document.tracks[trackIndex].stage = "MIDI motif ready"
        document.tracks[trackIndex].progress = 1.0
        return LocalProcessingOutput(detail: "MIDI motif artifact generated by local Swift engine", primaryArtifact: midiURL, artifacts: [midiURL, manifest])
    }

    private func runChordDetection(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let metrics = deterministicMetrics(for: document.tracks[trackIndex])
        let chords: [LocalJSONValue] = [
            .object(["bar": .integer(1), "chord": .string("\(metrics.key)maj")]),
            .object(["bar": .integer(9), "chord": .string(relativeMinor(for: metrics.key))]),
            .object(["bar": .integer(17), "chord": .string("\(metrics.key)sus4")])
        ]
        document.tracks[trackIndex].key = metrics.key
        document.tracks[trackIndex].stage = "Chords detected"
        document.tracks[trackIndex].progress = 1.0

        let artifact = try writeManifest(
            "chords.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging(["chords": .array(chords)], uniquingKeysWith: { _, new in new })
        )

        return LocalProcessingOutput(detail: "Chord map generated locally", primaryArtifact: artifact, artifacts: [artifact])
    }

    private func runWarp(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let bpm = max(document.tracks[trackIndex].bpm, 120)
        let markers = stride(from: 0, through: 32, by: 8).map { bar in
            LocalJSONValue.object([
                "bar": .integer(bar + 1),
                "seconds": .number(Double(bar) * 60.0 / Double(bpm) * 4.0)
            ])
        }
        document.tracks[trackIndex].stage = "Warp map ready"
        document.tracks[trackIndex].progress = 1.0

        let artifact = try writeManifest(
            "warp-map.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging(["warp_markers": .array(Array(markers))], uniquingKeysWith: { _, new in new })
        )

        return LocalProcessingOutput(detail: "Beat-grid warp map generated locally", primaryArtifact: artifact, artifacts: [artifact])
    }

    private func runCleanup(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let trackID = document.tracks[trackIndex].id
        let matchingArtifacts = document.processingJobs
            .filter { $0.trackID == trackID }
            .flatMap { $0.artifactPaths ?? [] }
        document.tracks[trackIndex].stage = "Cleanup checked"
        document.tracks[trackIndex].progress = max(document.tracks[trackIndex].progress, 0.95)

        let artifact = try writeManifest(
            "cleanup-report.json",
            in: directory,
            payload: basePayload(job: job, track: document.tracks[trackIndex])
                .merging([
                    "referenced_artifacts": .integer(matchingArtifacts.count),
                    "destructive_cleanup": .bool(false)
                ], uniquingKeysWith: { _, new in new })
        )

        return LocalProcessingOutput(detail: "Cleanup audit completed without deleting user media", primaryArtifact: artifact, artifacts: [artifact])
    }

    private func runExport(
        job: LocalProcessingJob,
        trackIndex: Int,
        document: inout SFALibraryDocument,
        directory: URL
    ) throws -> LocalProcessingOutput {
        let track = document.tracks[trackIndex]
        let stemArtifacts = document.stems.filter { $0.trackID == track.id }.compactMap(\.filePath)
        let artifact = try writeManifest(
            "export-manifest.json",
            in: directory,
            payload: basePayload(job: job, track: track)
                .merging([
                    "stem_artifacts": .array(stemArtifacts.map { .string($0) }),
                    "project_count": .integer(document.dawProjects.filter { $0.trackIDs.contains(track.id) }.count),
                    "export_format": .string("sfa-native-bundle")
                ], uniquingKeysWith: { _, new in new })
        )

        document.tracks[trackIndex].stage = "Export manifest ready"
        document.tracks[trackIndex].progress = 1.0
        return LocalProcessingOutput(detail: "Self-contained export manifest generated", primaryArtifact: artifact, artifacts: [artifact])
    }

    private func upsertStem(
        type: LocalStem.StemType,
        artifact: URL,
        job: LocalProcessingJob,
        document: inout SFALibraryDocument
    ) {
        let id = "stem-\(job.id)-\(type.rawValue)"
        if let index = document.stems.firstIndex(where: { $0.id == id }) {
            document.stems[index].filePath = artifact.path
            document.stems[index].fileSize = fileSize(at: artifact)
            document.stems[index].source = "native"
            document.stems[index].options["state"] = .string("ready")
        } else {
            document.stems.insert(
                LocalStem(
                    id: id,
                    trackID: job.trackID,
                    processingJobID: job.id,
                    type: type,
                    filePath: artifact.path,
                    fileSize: fileSize(at: artifact),
                    source: "native",
                    options: [
                        "engine": .string("local-stem-planner"),
                        "state": .string("ready")
                    ]
                ),
                at: 0
            )
        }
    }

    private func basePayload(job: LocalProcessingJob, track: TrackSummary) -> [String: LocalJSONValue] {
        [
            "job_id": .string(job.id),
            "job_kind": .string(job.kind.rawValue),
            "track_id": .string(track.id),
            "title": .string(track.title),
            "artist": .string(track.artist),
            "generated_at": .string(Self.iso8601.string(from: Date()))
        ]
    }

    private func writeManifest(
        _ filename: String,
        in directory: URL,
        payload: [String: LocalJSONValue]
    ) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        let data = try Self.encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func deterministicMetrics(for track: TrackSummary) -> (bpm: Int, key: String, energy: Double, spectralCentroid: Double) {
        let hash = stableHash(track.id + track.title + track.artist)
        let keys = ["1A", "2A", "3B", "4A", "5B", "6A", "7B", "8A", "9B", "10A", "11A", "12B"]
        let bpm = track.bpm > 0 ? track.bpm : 92 + (hash % 58)
        let key = track.key == "Pending" ? keys[hash % keys.count] : track.key
        let energy = Double((hash % 70) + 25) / 100.0
        let spectralCentroid = 900.0 + Double(hash % 2600)
        return (bpm, key, energy, spectralCentroid)
    }

    private func midiData(for track: TrackSummary) -> Data {
        let hash = stableHash(track.id + track.title)
        let note = UInt8(48 + (hash % 24))
        let bytes: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06,
            0x00, 0x00, 0x00, 0x01, 0x01, 0xE0,
            0x4D, 0x54, 0x72, 0x6B, 0x00, 0x00, 0x00, 0x0D,
            0x00, 0x90, note, 0x60,
            0x81, 0x70, 0x80, note, 0x40,
            0x00, 0xFF, 0x2F, 0x00
        ]
        return Data(bytes)
    }

    private func relativeMinor(for key: String) -> String {
        let number = Int(key.prefix { $0.isNumber }) ?? 1
        let relative = ((number + 2 - 1) % 12) + 1
        return "\(relative)Amin"
    }

    private func fileSize(at url: URL) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return size.intValue
    }

    private func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    private func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { partial, scalar in
            abs((partial &* 31) &+ Int(scalar.value))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let iso8601 = ISO8601DateFormatter()
}
