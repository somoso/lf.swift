import Foundation
import AVFoundation

class RTMPMessage {

    enum `Type`: UInt8 {
        case chunkSize   = 0x01
        case abort       = 0x02
        case ack         = 0x03
        case user        = 0x04
        case windowAck   = 0x05
        case bandwidth   = 0x06
        case audio       = 0x08
        case video       = 0x09
        case amf3Data    = 0x0F
        case amf3Shared  = 0x10
        case amf3Command = 0x11
        case amf0Data    = 0x12
        case amf0Shared  = 0x13
        case amf0Command = 0x14
        case aggregate   = 0x16
        case unknown     = 0xFF
    }

    static func create(_ value:UInt8) -> RTMPMessage? {
        switch value {
        case Type.chunkSize.rawValue:
            return RTMPSetChunkSizeMessage()
        case Type.abort.rawValue:
            return RTMPAbortMessge()
        case Type.ack.rawValue:
            return RTMPAcknowledgementMessage();
        case Type.user.rawValue:
            return RTMPUserControlMessage()
        case Type.windowAck.rawValue:
            return RTMPWindowAcknowledgementSizeMessage()
        case Type.bandwidth.rawValue:
            return RTMPSetPeerBandwidthMessage()
        case Type.audio.rawValue:
            return RTMPAudioMessage()
        case Type.video.rawValue:
            return RTMPVideoMessage()
        case Type.amf3Data.rawValue:
            return RTMPDataMessage(objectEncoding: 0x03)
        case Type.amf3Shared.rawValue:
            return RTMPSharedObjectMessage(objectEncoding: 0x03)
        case Type.amf3Command.rawValue:
            return RTMPCommandMessage(objectEncoding: 0x03)
        case Type.amf0Data.rawValue:
            return RTMPDataMessage(objectEncoding: 0x00)
        case Type.amf0Shared.rawValue:
            return RTMPSharedObjectMessage(objectEncoding: 0x00)
        case Type.amf0Command.rawValue:
            return RTMPCommandMessage(objectEncoding: 0x00)
        case Type.aggregate.rawValue:
            return RTMPAggregateMessage()
        default:
            guard let type:Type = Type(rawValue: value) else {
                logger.error("\(value)")
                return nil
            }
            return RTMPMessage(type: type)
        }
    }

    let type:Type
    var length:Int = 0
    var streamId:UInt32 = 0
    var timestamp:UInt32 = 0
    var payload:Data = Data()

    init(type:Type) {
        self.type = type
    }

    func execute(_ connection:RTMPConnection) {
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0)}.joined()
    }
}

extension RTMPMessage: CustomStringConvertible {
    // MARK: CustomStringConvertible
    var description:String {
        return Mirror(reflecting: self).description
    }
}

// MARK: -
/**
 5.4.1. Set Chunk Size (1)
 */
final class RTMPSetChunkSizeMessage: RTMPMessage {
    var size:UInt32 = 0

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            super.payload = size.bigEndian.data
            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }
            size = UInt32(data: newValue).bigEndian
            super.payload = newValue
        }
    }

    init() {
        super.init(type: .chunkSize)
    }

    init(_ size:UInt32) {
        super.init(type: .chunkSize)
        self.size = size
    }

    override func execute(_ connection:RTMPConnection) {
        connection.socket.chunkSizeC = Int(size)
    }
}

// MARK: -
/**
 5.4.2. Abort Message (2)
 */
final class RTMPAbortMessge: RTMPMessage {
    var chunkStreamId:UInt32 = 0

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            super.payload = chunkStreamId.bigEndian.data
            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }
            chunkStreamId = UInt32(data: newValue).bigEndian
            super.payload = newValue
        }
    }

    init() {
        super.init(type: .abort)
    }
}

// MARK: -
/**
 5.4.3. Acknowledgement (3)
 */
final class RTMPAcknowledgementMessage: RTMPMessage {
    var sequence:UInt32 = 0
    
    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            super.payload = sequence.bigEndian.data
            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }
            sequence = UInt32(data: newValue).bigEndian
            super.payload = newValue
        }
    }

    init() {
        super.init(type: .ack)
    }

    init(_ sequence:UInt32) {
        super.init(type: .ack)
        self.sequence = sequence
    }
}

// MARK: -
/**
 5.4.4. Window Acknowledgement Size (5)
 */
final class RTMPWindowAcknowledgementSizeMessage: RTMPMessage {
    var size:UInt32 = 0

    init() {
        super.init(type: .windowAck)
    }

    init(_ size:UInt32) {
        super.init(type: .windowAck)
        self.size = size
    }

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            super.payload = size.bigEndian.data
            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }
            size = UInt32(data: newValue).bigEndian
            super.payload = newValue
        }
    }

    override func execute(_ connection: RTMPConnection) {
        connection.windowSizeC = Int64(size)
        connection.windowSizeS = Int64(size)
    }
}

// MARK: -
/**
 5.4.5. Set Peer Bandwidth (6)
 */
final class RTMPSetPeerBandwidthMessage: RTMPMessage {

    enum Limit:UInt8 {
        case hard    = 0x00
        case soft    = 0x01
        case dynamic = 0x02
        case unknown = 0xFF
    }

    var size:UInt32 = 0
    var limit:Limit = .hard

    init() {
        super.init(type: .bandwidth)
    }

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            var payload:Data = Data()
            payload.append(size.bigEndian.data)
            payload.append(limit.rawValue)
            super.payload = payload
            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }
            size = UInt32(data: newValue[0..<4]).bigEndian
            limit = Limit(rawValue: newValue[4]) ?? .unknown
            super.payload = newValue
        }
    }

    override func execute(_ connection: RTMPConnection) {
        connection.bandWidth = size
    }
}

// MARK: -
/**
 7.1.1. Command Message (20, 17)
 */
final class RTMPCommandMessage: RTMPMessage {

    let objectEncoding:UInt8
    var commandName:String = ""
    var transactionId:Int = 0
    var commandObject:ASObject? = nil
    var arguments:[Any?] = []

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            if (type == .amf3Command) {
                serializer.writeUInt8(0)
            }
            serializer
                .serialize(commandName)
                .serialize(transactionId)
                .serialize(commandObject)
            for i in arguments {
                serializer.serialize(i)
            }
            super.payload = Data(serializer.bytes)
            serializer.clear()
            return super.payload
        }
        set {
            if (length == newValue.count) {
                serializer.writeBytes(newValue.bytes)
                serializer.position = 0
                do {
                    if (type == .amf3Command) {
                        serializer.position = 1
                    }
                    commandName = try serializer.deserialize()
                    transactionId = try serializer.deserialize()
                    commandObject = try serializer.deserialize()
                    arguments.removeAll()
                    if (0 < serializer.bytesAvailable) {
                        arguments.append(try serializer.deserialize())
                    }
                } catch {
                    logger.error("\(self.serializer)")
                }
                serializer.clear()
            }
            super.payload = newValue
        }
    }

    fileprivate var serializer:AMFSerializer = AMF0Serializer()

    init(objectEncoding:UInt8) {
        self.objectEncoding = objectEncoding
        super.init(type: objectEncoding == 0x00 ? .amf0Command : .amf3Command)
    }

    init(streamId:UInt32, transactionId:Int, objectEncoding:UInt8, commandName:String, commandObject: ASObject?, arguments:[Any?]) {
        self.transactionId = transactionId
        self.objectEncoding = objectEncoding
        self.commandName = commandName
        self.commandObject = commandObject
        self.arguments = arguments
        super.init(type: objectEncoding == 0x00 ? .amf0Command : .amf3Command)
        self.streamId = streamId
    }

    override func execute(_ connection: RTMPConnection) {

        guard let responder:Responder = connection.operations.removeValue(forKey: transactionId) else {
            switch commandName {
            case "close":
                connection.close()
            default:
                connection.dispatch(Event.RTMP_STATUS, bubbles: false, data: arguments.isEmpty ? nil : arguments[0])
            }
            return
        }

        switch commandName {
        case "_result":
            responder.on(result: arguments)
        case "_error":
            responder.on(status: arguments)
        default:
            break
        }
    }
}

// MARK: -
/**
 7.1.2. Data Message (18, 15)
 */
final class RTMPDataMessage: RTMPMessage {

    let objectEncoding:UInt8
    var handlerName:String = ""
    var arguments:[Any?] = []

    private var serializer:AMFSerializer = AMF0Serializer()

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }

            if (type == .amf3Data) {
                serializer.writeUInt8(0)
            }
            serializer.serialize(handlerName)
            for arg in arguments {
                serializer.serialize(arg)
            }
            super.payload = Data(serializer.bytes)
            serializer.clear()

            return super.payload
        }
        set {
            guard super.payload != newValue else {
                return
            }

            if (length == newValue.count) {
                serializer.writeBytes(newValue.bytes)
                serializer.position = 0
                if (type == .amf3Data) {
                    serializer.position = 1
                }
                do {
                    handlerName = try serializer.deserialize()
                    while (0 < serializer.bytesAvailable) {
                        arguments.append(try serializer.deserialize())
                    }
                } catch {
                    logger.error("\(self.serializer)")
                }
                serializer.clear()
            }

            super.payload = newValue
        }
    }

    init(objectEncoding:UInt8) {
        self.objectEncoding = objectEncoding
        super.init(type: objectEncoding == 0x00 ? .amf0Data : .amf3Data)
    }

    init(streamId:UInt32, objectEncoding:UInt8, handlerName:String, arguments:[Any?] = []) {
        self.objectEncoding = objectEncoding
        self.handlerName = handlerName
        self.arguments = arguments
        super.init(type: objectEncoding == 0x00 ? .amf0Data : .amf3Data)
        self.streamId = streamId
    }

    override func execute(_ connection: RTMPConnection) {
        guard let stream:RTMPStream = connection.streams[streamId] else {
            return
        }
        OSAtomicAdd64(Int64(payload.count), &stream.info.byteCount)
    }
}

// MARK: -
/**
 7.1.3. Shared Object Message (19, 16)
 */
final class RTMPSharedObjectMessage: RTMPMessage {

    let objectEncoding:UInt8
    var sharedObjectName:String = ""
    var currentVersion:UInt32 = 0
    var flags:[UInt8] = [UInt8](repeating: 0x00, count: 8)
    var events:[RTMPSharedObjectEvent] = []

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }

            if (type == .amf3Shared) {
                serializer.writeUInt8(0)
            }

            serializer
                .writeUInt16(UInt16(sharedObjectName.utf8.count))
                .writeUTF8Bytes(sharedObjectName)
                .writeUInt32(currentVersion)
                .writeBytes(flags)
            for event in events {
                event.serialize(&serializer)
            }
            super.payload = Data(serializer.bytes)
            serializer.clear()

            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }

            if (length == newValue.count) {
                serializer.writeBytes(newValue.bytes)
                serializer.position = 0
                if (type == .amf3Shared) {
                    serializer.position = 1
                }
                do {
                    sharedObjectName = try serializer.readUTF8()
                    currentVersion = try serializer.readUInt32()
                    flags = try serializer.readBytes(8)
                    while (0 < serializer.bytesAvailable) {
                        if let event:RTMPSharedObjectEvent = try RTMPSharedObjectEvent(serializer: &serializer) {
                            events.append(event)
                        }
                    }
                } catch {
                    logger.error("\(self.serializer)")
                }
                serializer.clear()
            }

            super.payload = newValue
        }
    }

    fileprivate var serializer:AMFSerializer = AMF0Serializer()

    init(objectEncoding:UInt8) {
        self.objectEncoding = objectEncoding
        super.init(type: objectEncoding == 0x00 ? .amf0Shared : .amf3Shared)
    }

    init(timestamp:UInt32, objectEncoding:UInt8, sharedObjectName:String, currentVersion:UInt32, flags:[UInt8], events:[RTMPSharedObjectEvent]) {
        self.objectEncoding = objectEncoding
        self.sharedObjectName = sharedObjectName
        self.currentVersion = currentVersion
        self.flags = flags
        self.events = events
        super.init(type: objectEncoding == 0x00 ? .amf0Shared : .amf3Shared)
        self.timestamp = timestamp
    }

    override func execute(_ connection:RTMPConnection) {
        let persistence:Bool = flags[0] == 0x01
        RTMPSharedObject.getRemote(withName: sharedObjectName, remotePath: connection.uri!.absoluteWithoutQueryString, persistence: persistence).on(message: self)
    }
}

// MARK: -
/**
 7.1.5. Audio Message (9)
 */
final class RTMPAudioMessage: RTMPMessage {
    var config:AudioSpecificConfig?

    private(set) var codec:FLVAudioCodec = .mp3
    private(set) var soundRate:FLVSoundRate = .kHz44
    private(set) var soundSize:FLVSoundSize = .snd8bit
    private(set) var soundType:FLVSoundType = .stereo

    var soundData:Data {
        let data:Data = payload.isEmpty ? Data() : payload//.advanced(by: codec.headerSize)
        guard let config:AudioSpecificConfig = config else {
            return data
        }
//        logger.info("RTMPAudioMessage: data \(data)\n config: \(config)")
        return data;
    }

    override var payload:Data {
        get {
            return super.payload
        }
        set {
//            logger.info("Payload: \(payload.hexEncodedString())\nSuper Payload: \(super.payload.hexEncodedString())\nNew Value: \(newValue)")
            if (super.payload == newValue) {
//                logger.info("super.payload == newValue")
                return
            }

//            logger.info("assigning newValue to super.payload")
            super.payload = newValue

//            logger.info("Payload: \(super.payload.hexEncodedString())")
            if (length == newValue.count && !newValue.isEmpty) {
//                logger.info("Getting essential values")
                guard let codec:FLVAudioCodec = FLVAudioCodec(rawValue: newValue[0] >> 4),
                    let soundRate:FLVSoundRate = FLVSoundRate(rawValue: (newValue[0] & 0b00001100) >> 2),
                    let soundSize:FLVSoundSize = FLVSoundSize(rawValue: (newValue[0] & 0b00000010) >> 1),
                    let soundType:FLVSoundType = FLVSoundType(rawValue: (newValue[0] & 0b00000001)) else {
//                    logger.info("Can't get values, returning early")
                    return
                }
                self.codec = codec
                self.soundRate = soundRate
                self.soundSize = soundSize
                self.soundType = soundType
//                logger.info("∂ info - Codec: \(self.codec)\nSound Rate: \(self.soundRate)\nSound Size: \(self.soundSize)\nSound Type: \(self.soundType)")
            }
        }
    }

    init() {
        super.init(type: .audio)
//        logger.info("Just a raw RTMP audio message...")
    }

    init(streamId: UInt32, timestamp: UInt32, payload:Data) {
        super.init(type: .audio)
        self.streamId = streamId
        self.timestamp = timestamp
        self.payload = payload
//        logger.info("Stream ID: \(self.streamId)\nTimestamp: \(timestamp)\nPayload: \(self.payload.hexEncodedString())")
    }

    override func execute(_ connection:RTMPConnection) {
        guard let stream:RTMPStream = connection.streams[streamId] else {
            return
        }
        OSAtomicAdd64(Int64(payload.count), &stream.info.byteCount)
        guard codec.isSupported else {
            return
        }
        if let config:AudioSpecificConfig = createAudioSpecificConfig() {
//            logger.info("Setting Audio Stream Playback configuration & file type hint")
            //AudioStreamPlayback call
            stream.mixer.audioIO.playback.fileTypeHint = kAudioFileMP3Type
            stream.mixer.audioIO.playback.config = config
//            return
        }
        self.config = stream.mixer.audioIO.playback.config
//        logger.info("Executing stream - " +
//                "codec: \(codec)\n" +
//                "config: \(config)" +
//                "\nsoundData: \(soundData.hexEncodedString())" +
//                "\nfileTypeHint: \(stream.mixer.audioIO.playback.fileTypeHint)" +
//                "\nstreamConfig: \(stream.mixer.audioIO.playback.config)")
//        logger.info("Sending bytes to AudioStreamPlayback object")
        //AudioStreamPlayback call
        stream.mixer.audioIO.playback.parseBytes(soundData.advanced(by: 1))
//        if let audioPlayer = try? AVAudioPlayer(data: soundData, fileTypeHint: "mp3") {
//            if (audioPlayer.prepareToPlay()) {
//                audioPlayer.play()
//            }
//        }


    }

    func createAudioSpecificConfig() -> AudioSpecificConfig? {
//        logger.info("Payload: \(payload.hexEncodedString())\ncodec:\(codec)")
        if (payload.isEmpty) {
//            logger.info("Returning nil - payload empty")
            return nil
        }

        guard codec == FLVAudioCodec.mp3_8k || codec == FLVAudioCodec.mp3 else {
//            logger.info("Returning nil - not mp3 codec")
            return nil
        }

//        logger.info("Payload packet type: \(payload[1])")
//        if (payload[1] == FLVMP3PacketType.seq.rawValue) {
//            logger.info("Payload packet type is MP3 type")
            if let config:AudioSpecificConfig = AudioSpecificConfig(bytes: Array<UInt8>(payload[codec.headerSize..<payload.count])) {
//                logger.info("Returning config")
                return config
            } else {
//                logger.info("Failed to get config")
            }
//        } else {
//            logger.info("Payload packet type is not MP3 type")
//        }


//        logger.info("Returning nil - failed all cases")
        return nil
    }
}

// MARK: -
/**
 7.1.5. Video Message (9)
 */
final class RTMPVideoMessage: RTMPMessage {
    private(set) var codec:FLVVideoCodec = .unknown
    private(set) var status:OSStatus = noErr

    init() {
        super.init(type: .video)
    }

    init(streamId: UInt32, timestamp: UInt32, payload:Data) {
        super.init(type: .video)
        self.streamId = streamId
        self.timestamp = timestamp
        self.payload = payload
    }

    override func execute(_ connection:RTMPConnection) {
        guard let stream:RTMPStream = connection.streams[streamId] else {
            return
        }
        OSAtomicAdd64(Int64(payload.count), &stream.info.byteCount)
        guard FLVTagType.video.headerSize < payload.count else {
            return
        }
        switch payload[1] {
        case FLVAVCPacketType.seq.rawValue:
            status = createFormatDescription(stream)
        case FLVAVCPacketType.nal.rawValue:
            enqueueSampleBuffer(stream)
        default:
            break
        }
    }

    func enqueueSampleBuffer(_ stream: RTMPStream) {
        logger.info("Enqueuing sample buffer")
        stream.videoTimestamp += Double(timestamp)

        convert(frame: payload.advanced(by: FLVTagType.video.headerSize), stream: stream)
//        var data:Data = payload.advanced(by: FLVTagType.video.headerSize)
//        data.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Void in
//            var blockBuffer:CMBlockBuffer?
//            let bbstate = CMBlockBufferCreateWithMemoryBlock(
//                    kCFAllocatorDefault, bytes, data.count, kCFAllocatorDefault, nil, 0, data.count, 0, &blockBuffer)
//            guard bbstate == kCMBlockBufferNoErr else {
//                logger.warning("Failing at the first hurdle :/ (\(bbstate))")
//                return
//            }
//            var sampleBuffer:CMSampleBuffer?
//            var sampleSizes:Int = data.count
//            let st = CMSampleBufferCreate(
//                    kCFAllocatorDefault, blockBuffer!, true, nil, nil, stream.mixer.videoIO.formatDescription, 1, 0, nil, 1, &sampleSizes, &sampleBuffer)
//            guard st == noErr else {
//                AudioStreamPlayback.printOSStatus(st)
//                logger.warning("Can't create sample buffer :'(")
//                return
//            }
//
//            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer!, true)
//            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
//            let displayImmediatelyKey = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
//            let trueValue = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
//            CFDictionarySetValue(dictionary, displayImmediatelyKey, trueValue)
//
//            guard let buffer:CMSampleBuffer = sampleBuffer else {
//                logger.warning("Buffer was nil")
//                return
//            }
//
//            //logger.info("Enqueueing this beatiful buffer: \(buffer)")
//            stream.mixer.videoIO.vidLayer?.enqueue(buffer)
//            status = noErr
//        }
    }

    private var formatDescription: CMFormatDescription?

    func convert(frame: Data, stream: RTMPStream) {
        guard frame.count > 4 else {
            return
        }

        func startCodeIndex(in data: Data, from: Data.Index = 0) -> Data.Index? {
            for i in from..<data.count - 5 {
                if frame[i] == 0x00 && frame[i + 1] == 0x00 && frame[i + 2] == 0x00 && frame[i + 3] == 0x01 {
                    return i
                }
            }

            return nil
        }

        var naluType = NALUnitType(rawValue: frame[4] & 0x1F) ?? .unspecified
        var spsRange: Range<Int>?
        var ppsRange: Range<Int>?

        if formatDescription == nil && naluType != .sps  {
            print("Error: formatDescription is nil and frame does not start from SPS")
            return
        }

        if naluType == .sps {
            guard let ppsSartIndex = startCodeIndex(in: frame, from: 4) else {
                print("Error: Can't find PPS start index")
                return
            }

            spsRange = 4..<ppsSartIndex
            naluType = NALUnitType(rawValue: frame[ppsSartIndex + 4] & 0x1F) ?? .unspecified
        }

        if naluType == .pps {
            guard let ppsStartIndex = spsRange?.upperBound,
                  let nextNaluPosition = startCodeIndex(in: frame, from: ppsStartIndex + 4) else {
                print("Error: Can't find next NALU after PPS to determine PPS length")
                return
            }

            ppsRange = ppsStartIndex + 4..<nextNaluPosition
            naluType = NALUnitType(rawValue: frame[nextNaluPosition + 4] & 0x1F) ?? .unspecified
        }

        if let spsRange = spsRange, let ppsRange = ppsRange {
            let spsSize = spsRange.upperBound - spsRange.lowerBound
            let ppsSize = ppsRange.upperBound - ppsRange.lowerBound

            formatDescription = nil

            let status = frame.withUnsafeBytes { (frame: UnsafePointer<UInt8>) -> OSStatus in
                var parameterSetPointers: [UnsafePointer<UInt8>] = [frame + spsRange.lowerBound, frame + ppsRange.lowerBound]
                var parameterSetSizes: [Int] = [spsSize, ppsSize]

                return CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                        2,
                        &parameterSetPointers,
                        &parameterSetSizes,
                        4,
                        &formatDescription)
            }

            guard formatDescription != nil else {
                print("Error: Can't create CMFormatDescription (OSStatus: \(status))")
                return
            }
        }

        var blockBuffer: CMBlockBuffer?

        if naluType == .idr {
            guard let ppsRange = ppsRange else {
                print("Error: Can't determine start of IDR")
                return
            }

            let idrRange: Range<Int> = ppsRange.upperBound..<frame.count
            let idrSize = idrRange.upperBound - idrRange.lowerBound

            let idr = UnsafeMutablePointer<UInt8>.allocate(capacity: idrSize)

            frame.copyBytes(to: idr, from: idrRange)

            idr.withMemoryRebound(to: UInt32.self, capacity: 1) { uint32Ptr in
                uint32Ptr.pointee = UInt32(idrSize - 4).bigEndian
            }

            guard CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                    idr, idrSize,
                    kCFAllocatorDefault,           // Cleanups our idr memory
                    nil, 0, idrSize, 0,
                    &blockBuffer) == kCMBlockBufferNoErr else {
                print("Error: Can't create CMBlockBuffer from IDR")
                return
            }
        }

        if naluType == .codedSlice {
            let codedSliceSize = frame.count

            let codedSlice = UnsafeMutablePointer<UInt8>.allocate(capacity: codedSliceSize)

            frame.copyBytes(to: codedSlice, count: codedSliceSize)

            codedSlice.withMemoryRebound(to: UInt32.self, capacity: 1) { uint32Ptr in
                uint32Ptr.pointee = UInt32(codedSliceSize - 4).bigEndian
            }

            guard CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                    codedSlice, codedSliceSize,
                    kCFAllocatorDefault,           // Cleanups our codedSlice memory
                    nil, 0, codedSliceSize, 0,
                    &blockBuffer) == kCMBlockBufferNoErr else {
                print("Error: Can't create CMBlockBuffer from coded slice")
                return
            }
        }

        guard let _ = blockBuffer else {
            print("Error: Reached end of the method without available blockBuffer")
            return
        }

        var sampleSize = frame.count
        var sampleBuffer: CMSampleBuffer?

        guard CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, true, nil, nil,
                formatDescription, 1, 0, nil, 1, &sampleSize, &sampleBuffer) == noErr else {
            print("Error: Failed to create CMSampleBuffer")
            return
        }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer!, true)
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        let displayImmediatelyKey = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
        let trueValue = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        CFDictionarySetValue(dictionary, displayImmediatelyKey, trueValue)

        stream.mixer.videoIO.vidLayer?.enqueue(sampleBuffer!)
        status = noErr
    }

    enum NALUnitType: UInt8, CustomStringConvertible {
        case unspecified = 0
        case codedSlice = 1
        case dataPartitionA = 2
        case dataPartitionB = 3
        case dataPartitionC = 4
        case idr = 5
        case sei = 6
        case sps = 7
        case pps = 8
        case accessUnitDelimiter = 9
        case endOfSequence = 10
        case endOfStream = 11
        case filterData = 12
        case spsExtension = 13
        case prefixNALU = 14
        case subsetSPS = 15
        case reserved16 = 16
        case reserved17 = 17
        case reserved18 = 18
        case csaPictureWoPartitioning = 19
        case cse = 20
        case cseDepthView = 21
        case reserved22 = 22
        case reserved23 = 23
        case stapa = 24
        case stapb = 25
        case mtap16 = 26
        case mtap24 = 27
        case fua = 28
        case fub = 29
        case unspecified30 = 30
        case unspecified31 = 31

        var description: String {
            switch self {
            case .unspecified:
                return "0: Unspecified (non-VCL)"
            case .codedSlice:
                return "1: Coded slice of a non-IDR picture (VCL)"
            case .dataPartitionA:
                return "2: Coded slice data partition A (VCL)"
            case .dataPartitionB:
                return "3: Coded slice data partition B (VCL)"
            case .dataPartitionC:
                return "4: Coded slice data partition C (VCL)"
            case .idr:
                return "5: Coded slice of an IDR picture (VCL)"
            case .sei:
                return "6: Supplemental enhancement information (SEI) (non-VCL)"
            case .sps:
                return "7: Sequence parameter set (non-VCL)"
            case .pps:
                return "8: Picture parameter set (non-VCL)"
            case .accessUnitDelimiter:
                return "9: Access unit delimiter (non-VCL)"
            case .endOfSequence:
                return "10: End of sequence (non-VCL)"
            case .endOfStream:
                return "11: End of stream (non-VCL)"
            case .filterData:
                return "12: Filler data (non-VCL)"
            case .spsExtension:
                return "13: Sequence parameter set extension (non-VCL)"
            case .prefixNALU:
                return "14: Prefix NAL unit (non-VCL)"
            case .subsetSPS:
                return "15: Subset sequence parameter set (non-VCL)"
            case .reserved16:
                return "16: Reserved (non-VCL)"
            case .reserved17:
                return "17: Reserved (non-VCL)"
            case .reserved18:
                return "18: Reserved (non-VCL)"
            case .csaPictureWoPartitioning:
                return "19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)"
            case .cse:
                return "20: Coded slice extension (non-VCL)"
            case .cseDepthView:
                return "21: Coded slice extension for depth view components (non-VCL)"
            case .reserved22:
                return "22: Reserved (non-VCL)"
            case .reserved23:
                return "23: Reserved (non-VCL)"
            case .stapa:
                return "24: STAP-A Single-time aggregation packet (non-VCL)"
            case .stapb:
                return "25: STAP-B Single-time aggregation packet (non-VCL)"
            case .mtap16:
                return "26: MTAP16 Multi-time aggregation packet (non-VCL)"
            case .mtap24:
                return "27: MTAP24 Multi-time aggregation packet (non-VCL)"
            case .fua:
                return "28: FU-A Fragmentation unit (non-VCL)"
            case .fub:
                return "29: FU-B Fragmentation unit (non-VCL)"
            case .unspecified30:
                return "30: Unspecified (non-VCL)"
            case .unspecified31:
                return "31: Unspecified (non-VCL)"
            }
        }
    }

    func createFormatDescription(_ stream: RTMPStream) -> OSStatus {
        var config:AVCConfigurationRecord = AVCConfigurationRecord()
        config.bytes = Array<UInt8>(payload[FLVTagType.video.headerSize..<payload.count])
        return config.createFormatDescription(&stream.mixer.videoIO.formatDescription)
    }
}

// MARK: -
/**
 7.1.6. Aggregate Message (22)
 */
final class RTMPAggregateMessage: RTMPMessage {
    init() {
        super.init(type: .aggregate)
    }
}

// MARK: -
/**
 7.1.7. User Control Message Events
 */
final class RTMPUserControlMessage: RTMPMessage {

    enum Event: UInt8 {
        case streamBegin = 0x00
        case streamEof   = 0x01
        case streamDry   = 0x02
        case setBuffer   = 0x03
        case recorded    = 0x04
        case ping        = 0x06
        case pong        = 0x07
        case bufferEmpty = 0x1F
        case bufferFull  = 0x20
        case unknown     = 0xFF

        var bytes:[UInt8] {
            return [0x00, rawValue]
        }
    }

    var event:Event = .unknown
    var value:Int32 = 0

    override var payload:Data {
        get {
            guard super.payload.isEmpty else {
                return super.payload
            }
            super.payload.removeAll()
            super.payload += event.bytes
            super.payload += value.bigEndian.bytes
            return super.payload
        }
        set {
            if (super.payload == newValue) {
                return
            }
            if (length == newValue.count) {
                if let event:Event = Event(rawValue: newValue[1]) {
                    self.event = event
                }
                value = Int32(bytes: Array<UInt8>(newValue[2..<newValue.count])).bigEndian
            }
            super.payload = newValue
        }
    }

    init() {
        super.init(type: .user)
    }

    init(event:Event, value:Int32) {
        super.init(type: .user)
        self.event = event
        self.value = value
    }

    override func execute(_ connection: RTMPConnection) {
        switch event {
        case .ping:
            connection.socket.doOutput(chunk: RTMPChunk(
                type: .zero,
                streamId: RTMPChunk.StreamID.control.rawValue,
                message: RTMPUserControlMessage(event: .pong, value: value)
            ), locked: nil)
        case .bufferEmpty, .bufferFull:
            connection.streams[UInt32(value)]?.dispatch("rtmpStatus", bubbles: false, data: [
                "level": "status",
                "code": description,
                "description": ""
            ])
        default:
            break
        }
    }
}
