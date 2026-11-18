import CoreVideo
import Foundation
import VideoToolbox

final class PixelConverter {
    private let session: VTPixelTransferSession
    private let convertsTransferFunction: Bool

    init(toBT709TransferFunction transferFunction: CFString? = nil) throws {
        var session: VTPixelTransferSession?
        let status = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &session)
        guard status == noErr, let session else { throw MotionWallError.sessionCreate(status) }
        self.session = session
        convertsTransferFunction = transferFunction != nil
        if let transferFunction {
            VTSessionSetProperty(
                session, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                value: kCVImageBufferColorPrimaries_ITU_R_709_2)
            VTSessionSetProperty(
                session, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: transferFunction)
        }
    }

    deinit {
        VTPixelTransferSessionInvalidate(session)
    }

    func convert(_ buffer: CVPixelBuffer, using pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        let target = try makeBuffer(from: pool)
        let status = VTPixelTransferSessionTransferImage(session, from: buffer, to: target)
        guard status == noErr else {
            throw MotionWallError.frameProcessingFailed("converting a frame failed with status \(status)")
        }
        if !convertsTransferFunction {
            CVBufferPropagateAttachments(buffer, target)
        }
        return target
    }
}

func tagAsBT709IfUntagged(_ buffer: CVPixelBuffer, transferFunction: CFString = kCVImageBufferTransferFunction_ITU_R_709_2) {
    let tags = [
        (kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2),
        (kCVImageBufferTransferFunctionKey, transferFunction),
    ]
    for (key, value) in tags where CVBufferCopyAttachment(buffer, key, nil) == nil {
        CVBufferSetAttachment(buffer, key, value, .shouldPropagate)
    }
}

func makeBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
    guard let buffer else { throw MotionWallError.pixelBufferAllocation }
    return buffer
}

func createPixelBufferPool(_ attributes: [String: Any]) throws -> CVPixelBufferPool {
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    guard let pool else { throw MotionWallError.pixelBufferAllocation }
    return pool
}

func createPixelBufferPool(
    _ attributes: [String: Any], format: OSType, width: Int, height: Int
) throws -> CVPixelBufferPool {
    var attributes = attributes
    attributes[kCVPixelBufferPixelFormatTypeKey as String] = format
    attributes[kCVPixelBufferWidthKey as String] = width
    attributes[kCVPixelBufferHeightKey as String] = height
    return try createPixelBufferPool(attributes)
}

@available(macOS 15.4, *)
extension VTFrameProcessor {
    func start(_ configuration: VTFrameProcessorConfiguration) throws {
        do {
            try startSession(configuration: configuration)
        } catch {
            throw MotionWallError.frameProcessingFailed(error.localizedDescription)
        }
    }

    func processAndWait(_ parameters: VTFrameProcessorParameters) throws {
        let finished = DispatchSemaphore(value: 0)
        var failure: Error?
        process(parameters: parameters) { _, error in
            failure = error
            finished.signal()
        }
        finished.wait()
        if let failure { throw MotionWallError.frameProcessingFailed(failure.localizedDescription) }
    }
}
