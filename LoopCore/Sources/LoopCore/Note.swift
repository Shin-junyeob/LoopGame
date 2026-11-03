/// pitch: MIDI number for pitched roles, pad index for drums. Time in ticks (PPQ 480).
public struct Note: Codable, Equatable, Sendable {
    public var tick: Int64
    public var duration: Int64
    public var pitch: Int
    public var velocity: Int
    public init(tick: Int64, duration: Int64 = 120, pitch: Int, velocity: Int = 100) {
        self.tick = tick; self.duration = duration; self.pitch = pitch; self.velocity = velocity
    }
}
