---
title: ADR-002: Python Integration
nav_order: 2
parent: Decisions
---
# ADR-002: Erlang Ports over NIFs and Microservices for Python ML Integration

**Status**: Accepted
**Date**: 2025-12-16
**Deciders**: Project Lead
**Context**: Sound Forge Alchemy requires Python libraries (librosa, demucs) for audio analysis and stem separation

## Context

Sound Forge Alchemy requires two Python machine learning libraries that have no Elixir equivalents:

1. **librosa**: Audio feature extraction (tempo/BPM detection, key detection, spectral analysis, MFCCs, chromagram). The Node.js version used a Python subprocess for this.
2. **demucs** (Meta/Facebook Research): Neural network-based audio source separation (vocals, drums, bass, other). The Node.js version used a Python subprocess for this.

Both libraries depend on NumPy, SciPy, and PyTorch -- large C/Fortran/CUDA native extensions that cannot be ported to Elixir. The decision concerns how the BEAM VM communicates with these Python processes.

## Decision

Use **Erlang Ports** with a JSON-over-stdio protocol. Each Port interaction spawns a Python process, sends arguments via command-line args, receives JSON output on stdout, and detects completion via exit status.

The implementation is in `SoundForge.Audio.AnalyzerPort` (for librosa) and `SoundForge.Audio.DemucsPort` (for demucs), both managed as GenServers.

## Rationale

### 1. Process Isolation (Crash Safety)

Erlang Ports run Python in a separate OS process. If Python segfaults (common with native extensions like PyTorch, NumPy FFI, or corrupt audio input), the BEAM VM is unaffected. The Port's GenServer receives `{port, {:exit_status, code}}` and handles the failure gracefully.

This is the primary reason for choosing Ports. Audio processing involves untrusted user input (arbitrary audio files) and complex native code. Crashes are not hypothetical -- they are expected.

### 2. No GIL Contention

Python's Global Interpreter Lock (GIL) limits true parallelism within a single Python process. With Erlang Ports, each analysis or stem separation job runs in its own Python process. The BEAM's scheduler and Oban's queue concurrency (`analysis: 2`, `processing: 2`) control parallelism at the OS process level, bypassing the GIL entirely.

### 3. Simple Protocol

The Port protocol is intentionally minimal:

- **Input**: Command-line arguments to the Python script (audio path, feature list, output format)
- **Output**: A single JSON object on stdout
- **Errors**: A JSON error object on stdout, non-zero exit code
- **Completion**: Exit status 0 (success) or non-zero (failure)

No persistent connection, no message framing, no protocol versioning. The Python scripts are stateless -- they read a file, compute results, write JSON, and exit.

### 4. Deployment Simplicity

The Python scripts live in `priv/python/` inside the Elixir release. Deployment requires Python 3 with pip dependencies (librosa, demucs, numpy) installed on the host. There is no separate service to deploy, monitor, or scale. The Elixir release is a single deployable unit.

### 5. Direct Port from Node.js

The Node.js version used `child_process.spawn()` to call Python scripts with command-line arguments and parse JSON output. Erlang Ports are semantically identical -- the same Python scripts work with minimal modification. This reduced porting risk and preserved the tested Python analysis code.

## Alternatives Considered

### Alternative 1: NIFs (Erlang Native Implemented Functions)

**What it offers**: Direct function calls between Elixir and native code. Libraries like `Rustler` (for Rust) or `erlport`/`Pyrlang` (for Python) enable in-process communication.

**Why rejected**:

- **Crash propagation**: A segfault in a NIF crashes the entire BEAM VM. Audio processing with native ML libraries (PyTorch, NumPy C extensions) involves complex native code that can and does segfault on malformed input. One bad audio file would take down all connected users.
- **Scheduler blocking**: NIFs that run for more than 1ms without yielding block the BEAM scheduler. Audio analysis takes 30-120 seconds. Even with dirty schedulers, long-running NIFs degrade the entire system's responsiveness.
- **GIL complications**: Python NIFs via erlport still contend with the GIL. Running librosa analysis in a NIF does not provide true parallelism.
- **Complexity**: Bridging Python's C extensions (NumPy, SciPy, PyTorch) through a NIF layer adds substantial build complexity (shared library linking, ABI compatibility, cross-platform builds).

### Alternative 2: Microservices (HTTP/gRPC)

**What it offers**: Python runs as a separate service (Flask, FastAPI, gRPC) that the Elixir application calls over HTTP or gRPC.

**Why rejected**:

- **Operational complexity**: A separate Python service requires its own deployment, monitoring, scaling, health checks, and log aggregation. This doubles the operational surface area.
- **Single-release goal**: The project goal is a single deployable Elixir release with Python as a local dependency, not a distributed system. Microservices violate this.
- **Latency**: HTTP/gRPC adds serialization overhead, network round-trips (even on localhost), and connection management. For large audio file paths and JSON result payloads, this is unnecessary overhead compared to stdio pipes.
- **State management**: A microservice needs its own mechanism for job queuing, retries, and progress reporting. With Ports, Oban handles all of this on the Elixir side.
- **Resource contention**: A separate service competes for CPU and memory on the same host. With Ports, Oban's queue concurrency limits (`processing: 2`) directly control how many Python processes run simultaneously.

### Alternative 3: Pure Elixir ML Libraries (Nx, Scholar, Bumblebee)

**What it offers**: Native Elixir numerical computing (Nx), traditional ML (Scholar), and pre-trained model inference (Bumblebee/Axon).

**Why rejected**:

- **No librosa equivalent**: Librosa's audio feature extraction (onset detection, beat tracking, pitch estimation, HPSS, chroma CQT) has no Elixir equivalent. Nx provides tensor operations, but the high-level audio analysis algorithms are not implemented.
- **No demucs equivalent**: Demucs is a specific pre-trained neural network architecture from Meta Research. While Bumblebee supports some model architectures (Whisper, BERT), demucs is not among them. Porting the model weights and architecture to Axon would be a multi-month effort with no guarantee of equivalent quality.
- **Maturity gap**: The Python audio ML ecosystem (librosa, essentia, madmom, demucs, spleeter) has been developed over 10+ years with extensive academic validation. The Elixir ML ecosystem is young and focused on different domains (NLP, computer vision).

## Consequences

### Positive

- BEAM VM is completely isolated from Python crashes
- Parallel Python processes bypass the GIL naturally
- Same Python scripts from the Node.js version work with minimal changes
- Single deployable release (Elixir + Python scripts in priv/)
- Oban controls concurrency at the Elixir level
- Simple, debuggable protocol (JSON on stdio)

### Negative

- Process spawn overhead (~100ms per Port open) -- acceptable for jobs that run 30s-10min
- No persistent Python process (cold start each time) -- acceptable because analysis is stateless
- Python environment must be installed on the host (not bundled in the release)
- Debugging requires inspecting both Elixir logs and Python stderr
- Large result payloads (spectral data, MFCCs) are serialized through JSON over stdio

### Neutral

- Migration to microservices is straightforward if scaling requires it: replace Port calls with HTTP calls to a Python service
- Migration to NIFs could be explored for lightweight, crash-safe operations (e.g., simple FFT) if performance demands it
- The Python scripts remain independently testable (`python3 analyzer.py audio.mp3 --features tempo,key`)

## Port Protocol Specification

### AnalyzerPort (librosa)

```
Command: python3 priv/python/analyzer.py <audio_path> --features <feature_list> --output json
Input:   Command-line arguments only
Output:  JSON object on stdout
Exit 0:  {"tempo": 120.5, "key": {"key": "C", "mode": "major"}, ...}
Exit !0: {"error": "type", "message": "description"}
```

### DemucsPort (demucs)

```
Command: python3 priv/python/demucs_separate.py <audio_path> --output-dir <dir> --model htdemucs
Input:   Command-line arguments only
Output:  JSON object on stdout with stem file paths
Exit 0:  {"stems": {"vocals": "/path/vocals.wav", "drums": "/path/drums.wav", ...}}
Exit !0: {"error": "type", "message": "description"}
```
