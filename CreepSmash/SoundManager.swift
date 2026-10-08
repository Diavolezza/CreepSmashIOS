import AVFoundation
import SwiftUI
import CreepSmashCore

/// Sound effects (our own, tools/sounds/sfx.py). Mapping as in the original: shots per tower type, a
/// death sound per creep tier, a warning for incoming creeps, sounds for creeps that break through,
/// upgrade, victory and defeat.
///
/// Effects and music play through one audio engine (`AudioOutput`) whose output passes a peak limiter:
/// many sounds at once (end of the game, big waves) no longer add up beyond full scale, which crackled.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    enum Key {
        static let enabled = "soundEnabled"
        static let shots = "soundShots"
        static let volume = "soundVolume"
        static let music = "musicEnabled"
        static let musicVolume = "musicVolume"
    }

    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [String: CFTimeInterval] = [:]
    private var sessionReady = false
    /// True once the audio session is active; the engine starts only then (starting it earlier would
    /// activate the session on the main thread, which iOS warns about).
    private(set) var sessionActive = false

    private var defaults: UserDefaults { .standard }
    var enabled: Bool { defaults.object(forKey: Key.enabled) as? Bool ?? true }
    var shotsEnabled: Bool { defaults.object(forKey: Key.shots) as? Bool ?? true }
    var volume: Float { Float(defaults.object(forKey: Key.volume) as? Double ?? 0.7) }

    private init() {}

    /// Plays a sound at most every `spacing` seconds (otherwise it gets too loud with many towers).
    func play(_ name: String, spacing: CFTimeInterval = 0.08, gain: Float = 1) {
        guard enabled else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < spacing { return }
        lastPlayed[name] = now
        prepareSession()
        guard let buffer = buffer(for: name) else { return }
        AudioOutput.shared.play(buffer, volume: volume * gain)
    }

    /// Maps the events of a tick to sounds (only those that concern the local player).
    func handle(_ events: [GameEvent], game: Game, me: Int) {
        guard enabled else { return }
        for event in events {
            switch event {
            case let .laserShot(player, towerId, _, _) where player == me && shotsEnabled:
                if let tower = game.players[player].tower(id: towerId) { play(shotSound(tower), spacing: 0.12, gain: 0.5) }
            case let .rocketLaunched(player, _) where player == me && shotsEnabled:
                play("shoot4", spacing: 0.15, gain: 0.6)
            case let .creepKilled(player, _, type, _, _, _) where player == me:
                play("dead\(min(type.rawValue, 5))", spacing: 0.1, gain: 0.7)
            case let .creepsSent(_, to, _, _) where to == me:
                play("warn", spacing: 1.5, gain: 0.6)
            case let .creepEscaped(player, _, _, _) where player == me:
                play("dcloak", spacing: 0.3)
            case let .towerUpgraded(player, _, _) where player == me:
                play("holy", spacing: 0.3, gain: 0.6)
            case let .gameFinished(winner):
                play(winner == me ? "won" : "fin", spacing: 0)
            case let .playerDied(player, _) where player == me:
                play("fin", spacing: 0)
            default:
                break
            }
        }
    }

    private func shotSound(_ tower: Tower) -> String {
        switch tower.kind {
        case .basic: tower.level == 1 ? "shoot1" : "shoot2"
        case .slow: tower.level == 1 ? "laser1" : "laser2"
        case .splash: tower.level == 1 ? "shoot3" : "laser3"
        case .rocket: "shoot4"
        case .speed: "shoot5"
        case .ultimate: "shoot6"
        }
    }

    private func buffer(for name: String) -> AVAudioPCMBuffer? {
        if let buffer = buffers[name] { return buffer }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == AudioOutput.effectFormat.sampleRate,
              file.processingFormat.channelCount == AudioOutput.effectFormat.channelCount,
              let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: pcm)) != nil else { return nil }
        buffers[name] = pcm
        return pcm
    }

    /// Sets up the audio session once, off the main thread (activating it can block for a moment,
    /// which iOS reports as a warning). Called at app start, so the session is ready before the first sound.
    func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        DispatchQueue.global(qos: .userInitiated).async {
            // .ambient: mixes with music from other apps and stays silent with the silent switch on.
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            try? AVAudioSession.sharedInstance().setActive(true)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    SoundManager.shared.sessionActive = true
                    MusicPlayer.shared.update()
                }
            }
        }
    }
}

/// The one audio engine of the app: a few voices for the effects and a node for the music, mixed and
/// then passed through Apple's peak limiter. After a change of the output (headphones or a USB device
/// plugged in or out, a call) the engine stops; it is started again and the music fades back in.
@MainActor
final class AudioOutput {
    static let shared = AudioOutput()

    /// All effect files have this format (tools/sounds/sfx.py writes 44.1 kHz mono).
    static let effectFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private static let voiceCount = 10

    let engine = AVAudioEngine()
    let musicNode = AVAudioPlayerNode()
    private let effects = AVAudioMixerNode()
    private var voices: [AVAudioPlayerNode] = []
    private var started: [CFTimeInterval]
    private var observer: NSObjectProtocol?
    /// Called after the engine was restarted (the music schedules its loop again).
    var onRestart: (() -> Void)?

    private init() {
        started = Array(repeating: 0, count: Self.voiceCount)
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        engine.attach(effects)
        engine.attach(musicNode)
        engine.attach(limiter)
        for _ in 0..<Self.voiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: effects, format: Self.effectFormat)
            voices.append(voice)
        }
        engine.connect(effects, to: engine.mainMixerNode, format: nil)
        engine.connect(musicNode, to: engine.mainMixerNode, format: nil)
        let output = engine.outputNode.inputFormat(forBus: 0)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(engine.mainMixerNode, to: limiter, format: output)
        engine.connect(limiter, to: engine.outputNode, format: output)
        engine.prepare()
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { AudioOutput.shared.restart() }
        }
    }

    @discardableResult
    func run() -> Bool {
        if engine.isRunning { return true }
        guard SoundManager.shared.sessionActive else { return false }
        do { try engine.start() } catch { return false }
        return true
    }

    /// Plays a buffer on a free voice; if all are busy, the one playing longest is taken over.
    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard run() else { return }
        let now = CACurrentMediaTime()
        let index = voices.indices.first { !voices[$0].isPlaying }
            ?? started.indices.min { started[$0] < started[$1] }!
        let voice = voices[index]
        voice.stop()
        voice.volume = volume
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voice.play()
        started[index] = now
    }

    private func restart() {
        voices.forEach { $0.stop() }
        // Give the new output a moment to settle, then start again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                guard AudioOutput.shared.run() else { return }
                AudioOutput.shared.onRestart?()
            }
        }
    }
}

/// Background music: our own calm loop (tools/music/compose.py), played quietly and without a gap
/// at the loop point (the whole file is decoded once and looped sample-exactly).
@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()

    /// The slider goes up to this level only, so the music always stays in the background.
    private static let maxLevel: Float = 0.35

    private var node: AVAudioPlayerNode { AudioOutput.shared.musicNode }
    private var buffer: AVAudioPCMBuffer?
    private var fade: Timer?

    private var defaults: UserDefaults { .standard }
    /// On unless switched off (also "-musicEnabled NO" as launch argument, used by build.sh for screenshots).
    var enabled: Bool {
        defaults.object(forKey: SoundManager.Key.music) == nil ? true : defaults.bool(forKey: SoundManager.Key.music)
    }
    var level: Float { Float(defaults.object(forKey: SoundManager.Key.musicVolume) as? Double ?? 0.5) }

    private init() {
        AudioOutput.shared.onRestart = { MusicPlayer.shared.restart() }
    }

    /// Starts or stops the music according to the options; call after changes and when the app becomes active.
    func update() {
        guard enabled else { return stop() }
        if node.isPlaying {
            fade?.invalidate()
            node.volume = level * Self.maxLevel
            return
        }
        start()
    }

    func stop() {
        fade?.invalidate()
        node.stop()
    }

    private func start() {
        if buffer == nil {
            guard let url = Bundle.main.url(forResource: "music", withExtension: "m4a"),
                  let file = try? AVAudioFile(forReading: url),
                  let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: pcm)) != nil else { return }
            buffer = pcm
        }
        guard let buffer else { return }
        SoundManager.shared.prepareSession()
        guard AudioOutput.shared.run() else { return }
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.volume = 0
        node.play()
        fadeIn()
    }

    /// Fades in over about a second, so a (re)start never begins with a hard edge.
    private func fadeIn() {
        fade?.invalidate()
        let target = level * Self.maxLevel
        fade = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            MainActor.assumeIsolated {
                let node = AudioOutput.shared.musicNode
                node.volume = min(target, node.volume + target / 20)
                if node.volume >= target { timer.invalidate() }
            }
        }
    }

    private func restart() {
        node.stop()
        update()
    }
}

/// Options: name, sounds on/off, shot sounds, volume, music.
struct OptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SoundManager.Key.enabled) private var enabled = true
    @AppStorage(SoundManager.Key.shots) private var shots = true
    @AppStorage(SoundManager.Key.volume) private var volume: Double = 0.7
    @AppStorage(SoundManager.Key.music) private var music = true
    @AppStorage(SoundManager.Key.musicVolume) private var musicVolume: Double = 0.5
    @AppStorage("playerName") private var playerName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Player")) {
                    TextField(L("Your name"), text: $playerName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section(L("Sound")) {
                    Toggle(L("Sounds"), isOn: $enabled)
                    Toggle(L("Shot sounds"), isOn: $shots)
                        .disabled(!enabled)
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.gray)
                        Slider(value: $volume, in: 0...1, onEditingChanged: { editing in
                            if !editing { SoundManager.shared.play("shoot2", spacing: 0) }
                        })
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.gray)
                    }
                    .disabled(!enabled)
                }
                Section(L("Music")) {
                    Toggle(L("Background music"), isOn: $music)
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(.gray)
                        Slider(value: $musicVolume, in: 0...1)
                        Image(systemName: "music.note.list").foregroundStyle(.gray)
                    }
                    .disabled(!music)
                }
                .onChange(of: music) { MusicPlayer.shared.update() }
                .onChange(of: musicVolume) { MusicPlayer.shared.update() }
                Section {
                    Text(L("In silent mode the game stays quiet."))
                        .font(Theme.mono(15))
                        .foregroundStyle(.gray)
                }
            }
            .font(Theme.mono(15))
            .navigationTitle(L("Options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .pageSizedSheet()
    }
}
