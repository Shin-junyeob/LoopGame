import CAtomic
import Testing
@testable import LoopCore

private final class FreeLog {
    var freed: [UnsafeMutableRawPointer] = []
}

private func makeSwap() -> (StateSwap, FreeLog) {
    let log = FreeLog()
    return (StateSwap { log.freed.append($0) }, log)
}

nonisolated(unsafe) private let a = UnsafeMutableRawPointer(bitPattern: 0x1000)!
nonisolated(unsafe) private let b = UnsafeMutableRawPointer(bitPattern: 0x2000)!

@Test func oldStateFreedOnlyAtEpochCPlus2() {
    let (swap, log) = makeSwap()
    swap.swap(to: a, engineRunning: true)
    swap.swap(to: b, engineRunning: true)  // retires a at epoch C
    catomic_epoch_increment(swap.slot)      // C+1
    swap.collect()
    #expect(log.freed.isEmpty)
    catomic_epoch_increment(swap.slot)      // C+2
    swap.collect()
    #expect(log.freed == [a])
}

@Test func renderReadingOldPointerAcrossSwapKeepsItAlive() {
    let (swap, log) = makeSwap()
    swap.swap(to: a, engineRunning: true)
    let seen = catomic_load(swap.slot)          // render callback start: reads old pointer
    swap.swap(to: b, engineRunning: true)       // main: exchange, then read C
    catomic_epoch_increment(swap.slot)          // that callback ends: C+1
    swap.collect()
    #expect(seen == a)
    #expect(log.freed.isEmpty)
    #expect(swap.pendingCount == 1)
    #expect(catomic_load(swap.slot) == b)       // next callback sees new state
    catomic_epoch_increment(swap.slot)          // C+2
    swap.collect()
    #expect(log.freed == [a])
}

@Test func engineStoppedSwapFreesImmediately() {
    let (swap, log) = makeSwap()
    swap.swap(to: a, engineRunning: false)
    swap.swap(to: b, engineRunning: false)
    #expect(log.freed == [a])
    #expect(swap.pendingCount == 0)
}
