import AudioToolbox

struct AudioRenderMetrics: Equatable {
    let completedBlocks: UInt64
    let deadlineMisses: UInt64
    let maximumProcessingMicroseconds: Double
    let lastDeadlineMicroseconds: Double

    init?(parameterTree: AUParameterTree) {
        func value(_ address: AUParameterAddress) -> Float? {
            parameterTree.parameter(withAddress: address)?.value
        }
        guard let blocks = value(MobileEQ.renderBlocksAddress),
              let misses = value(MobileEQ.deadlineMissesAddress),
              let maximum = value(MobileEQ.maximumProcessingMicrosecondsAddress),
              let deadline = value(MobileEQ.lastDeadlineMicrosecondsAddress) else { return nil }
        completedBlocks = UInt64(max(0, blocks).rounded(.down))
        deadlineMisses = UInt64(max(0, misses).rounded(.down))
        maximumProcessingMicroseconds = Double(maximum)
        lastDeadlineMicroseconds = Double(deadline)
    }
}
