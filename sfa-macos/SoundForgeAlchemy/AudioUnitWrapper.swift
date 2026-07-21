import AudioToolbox
import AVFoundation
import AppKit

// MARK: - Audio Unit v3 wrapper (US-A06)
// Exposes the bundled SFA processing chain as an Audio Unit component.
// Full DSP wiring is implemented behind native processing contracts; this
// registration shell lets DAW hosts discover the component.

final class SFAAudioUnit: AUAudioUnit {

    // Component description — registered in Info.plist under NSExtension
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x73666165, // 'sfae'
        componentManufacturer: 0x6C67746D, // 'lgtm'
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _outputBusArray: AUAudioUnitBusArray!

    override var inputBusses: AUAudioUnitBusArray { _inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        _inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources()
    }

    // Pass-through render block while the native DSP graph is being ported.
    override var internalRenderBlock: AUInternalRenderBlock {
        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            return pullInputBlock(actionFlags, timestamp, frameCount, 0, outputData)
        }
    }

    // MARK: - Registration

    /// Register the AUv3 component with the system
    static func register() {
        AUAudioUnit.registerSubclass(
            SFAAudioUnit.self,
            as: componentDescription,
            name: "Sound Forge Alchemy",
            version: 0x00010000
        )
    }
}

// MARK: - SFA Audio Unit Manager

final class AudioUnitManager: NSObject {
    static let shared = AudioUnitManager()

    private override init() {}

    func registerIfNeeded() {
        SFAAudioUnit.register()
    }

    /// Notify the native runtime that an AU session has started.
    func notifyAUSessionStarted(sampleRate: Double, channels: Int) {
        DispatchQueue.main.async {
            NativeCommandCenter.shared.runPipeline(
                "au-session-started sampleRate=\(sampleRate) channels=\(channels)"
            )
        }
    }
}
