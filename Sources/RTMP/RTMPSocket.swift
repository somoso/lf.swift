import Foundation

protocol RTMPSocketCompatible: class {
    var timeout:Int64 { get set }
    var connected:Bool { get }
    var timestamp:TimeInterval { get }
    var chunkSizeC:Int { get set }
    var chunkSizeS:Int { get set }
    var totalBytesIn:Int64 { get }
    var totalBytesOut:Int64 { get }
    var queueBytesOut:Int64 { get }
    var inputBuffer:Data { get set }
    var securityLevel:StreamSocketSecurityLevel { get set }
    weak var delegate:RTMPSocketDelegate? { get set }

    @discardableResult
    func doOutput(chunk:RTMPChunk, locked:UnsafeMutablePointer<UInt32>?) -> Int
    func close(isDisconnected:Bool)
    func connect(withName:String, port:Int)
    func deinitConnection(isDisconnected:Bool)
}

// MARK: -
protocol RTMPSocketDelegate: IEventDispatcher {
    func listen()
    func didSetReadyState(_ readyState:RTMPSocket.ReadyState)
    func didSetTotalBytesIn(_ totalBytesIn:Int64)
}

// MARK: -
final class RTMPSocket: NetSocket, RTMPSocketCompatible {
    enum ReadyState: UInt8 {
        case uninitialized = 0
        case versionSent   = 1
        case ackSent       = 2
        case handshakeDone = 3
        case closing       = 4
        case closed        = 5
    }

    var readyState:ReadyState = .uninitialized {
        didSet {
            delegate?.didSetReadyState(readyState)
        }
    }
    var timestamp:TimeInterval {
        return handshake.timestamp
    }
    var chunkSizeC:Int = RTMPChunk.defaultSize
    var chunkSizeS:Int = RTMPChunk.defaultSize
    weak var delegate:RTMPSocketDelegate? = nil
    override var totalBytesIn: Int64 {
        didSet {
            delegate?.didSetTotalBytesIn(totalBytesIn)
        }
    }

    override var connected:Bool {
        didSet {
            if (connected) {
                doOutput(bytes: handshake.c0c1packet)
                readyState = .versionSent
                return
            }
            readyState = .closed
            for event in events {
                delegate?.dispatch(event: event)
            }
            events.removeAll()
        }
    }

    private var events:[Event] = []
    private var handshake:RTMPHandshake = RTMPHandshake()

    @discardableResult
    func doOutput(chunk:RTMPChunk, locked:UnsafeMutablePointer<UInt32>? = nil) -> Int {
        let chunks:[Data] = chunk.split(chunkSizeS)
        for i in 0..<chunks.count - 1 {
            doOutput(data: chunks[i])
        }
        doOutput(data: chunks.last!, locked: locked)
        if (logger.isEnabledFor(level: .verbose)) {
            logger.verbose(chunk)
        }
        return chunk.message!.length
    }

    func connect(withName:String, port:Int) {
        networkQueue.async {
            Stream.getStreamsToHost(
                withName: withName,
                port: port,
                inputStream: &self.inputStream,
                outputStream: &self.outputStream
            )
            self.initConnection()
        }
    }

    override func listen() {
//        logger.info("Calling listen")
        var count: Int = 0
        RTMPConnection.mutex.sync(execute: {
            count = inputBuffer.count
        })
        switch readyState {
        case .versionSent:
            if (count < RTMPHandshake.sigSize + 1) {
                break
            }
            doOutput(bytes: handshake.c2packet(inputBuffer.bytes))
            RTMPConnection.mutex.sync(execute: {
                inputBuffer.removeSubrange(0...RTMPHandshake.sigSize)
            })

            readyState = .ackSent
            if (RTMPHandshake.sigSize <= count) {
//                logger.info("RTMP Handshake sigSize: \(RTMPHandshake.sigSize) - IB Count: \(inputBuffer.count)")
                listen()
            }
        case .ackSent:
            if (count < RTMPHandshake.sigSize) {
                break
            }
            RTMPConnection.mutex.sync(execute: {
                inputBuffer.removeAll()
            })
            readyState = .handshakeDone
        case .handshakeDone:
            if (count == 0){
                break
            }
            delegate?.listen()
        default:
            break
        }
    }

    override func initConnection() {
        handshake.clear()
        readyState = .uninitialized
        chunkSizeS = RTMPChunk.defaultSize
        chunkSizeC = RTMPChunk.defaultSize
        super.initConnection()
    }

    override func deinitConnection(isDisconnected:Bool) {
        if (isDisconnected) {
            let data:ASObject = (readyState == .handshakeDone) ?
                RTMPConnection.Code.connectClosed.data("") : RTMPConnection.Code.connectFailed.data("")
            events.append(Event(type: Event.RTMP_STATUS, bubbles: false, data: data))
        }
        readyState = .closing
        super.deinitConnection(isDisconnected: isDisconnected)
    }

    override func didTimeout() {
        deinitConnection(isDisconnected: false)
        delegate?.dispatch(Event.IO_ERROR, bubbles: false, data: nil)
        logger.warning("connection timedout")
    }
}
