import Foundation

/**
 flash.net.Responder for Swift
 */
open class Responder: NSObject {

    public typealias Handler = (_ data:[Any?]) -> Void

    private var result:Handler
    private var status:Handler?

    public init(result:@escaping Handler, status:Handler? = nil) {
        self.result = result
        self.status = status
    }

    final func on(result:[Any?]) {
        self.result(result)
    }

    final func on(status:[Any?]) {
        self.status?(status)
        self.status = nil
    }
}

// MARK: -
/**
 flash.net.NetConnection for Swift
 */
open class RTMPConnection: EventDispatcher {
    static public let defaultWindowSizeS:Int64 = 250000
    static public let supportedProtocols:[String] = ["rtmp", "rtmps", "rtmpt"]
    static public let defaultPort:Int = 1935
    static public let defaultFlashVer:String = "FMLE/3.0 (compatible; FMSc/1.0)"
    static public let defaultChunkSizeS:Int = 1024 * 8
    static public let defaultCapabilities:Int = 239
    static public let defaultObjectEncoding:UInt8 = 0x00

    static public let mutex = PThreadMutex()
    fileprivate var currentlyListening: Bool = false
    fileprivate let connectionLock:DispatchQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.RTMPConnection.lock")
    /**
     NetStatusEvent#info.code for NetConnection
     */
    public enum Code: String {
        case callBadVersion       = "NetConnection.Call.BadVersion"
        case callFailed           = "NetConnection.Call.Failed"
        case callProhibited       = "NetConnection.Call.Prohibited"
        case connectAppshutdown   = "NetConnection.Connect.AppShutdown"
        case connectClosed        = "NetConnection.Connect.Closed"
        case connectFailed        = "NetConnection.Connect.Failed"
        case connectIdleTimeOut   = "NetConnection.Connect.IdleTimeOut"
        case conenctInvalidApp    = "NetConnection.Connect.InvalidApp"
        case connectNetworkChange = "NetConnection.Connect.NetworkChange"
        case connectRejected      = "NetConnection.Connect.Rejected"
        case connectSuccess       = "NetConnection.Connect.Success"

        public var level:String {
            switch self {
            case .callBadVersion:
                return "error"
            case .callFailed:
                return "error"
            case .callProhibited:
                return "error"
            case .connectAppshutdown:
                return "status"
            case .connectClosed:
                return "status"
            case .connectFailed:
                return "error"
            case .connectIdleTimeOut:
                return "status"
            case .conenctInvalidApp:
                return "error"
            case .connectNetworkChange:
                return "status"
            case .connectRejected:
                return "status"
            case .connectSuccess:
                return "status"
            }
        }

        func data(_ description:String) -> ASObject {
            return [
                "code": rawValue,
                "level": level,
                "description": description,
            ]
        }
    }

    struct Support {
        enum Video: UInt16 {
            case unused    = 0x0001
            case jpeg      = 0x0002
            case sorenson  = 0x0004
            case homebrew  = 0x0008
            case vp6       = 0x0010
            case vp6Alpha  = 0x0020
            case homebrewv = 0x0040
            case h264      = 0x0080
            case all       = 0x00FF
        }

        enum Sound: UInt16 {
            case none    = 0x0001
            case adpcm   = 0x0002
            case mp3     = 0x0004
            case intel   = 0x0008
            case unused  = 0x0010
            case nelly8  = 0x0020
            case nelly   = 0x0040
            case g711A   = 0x0080
            case g711U   = 0x0100
            case nelly16 = 0x0200
            case aac     = 0x0400
            case speex   = 0x0800
            case all     = 0x0FFF
        }
    }


    enum VideoFunction: UInt8 {
        case clientSeek = 1
    }

    fileprivate static func createSanJoseAuthCommand(_ url:URL, description:String) -> String {
        var command:String = url.absoluteString

        guard let index:String.CharacterView.Index = description.characters.index(of: "?") else {
            return command
        }

        let query:String = description.substring(from: description.characters.index(index, offsetBy: 1))
        let challenge:String = String(format: "%08x", arc4random())
        let dictionary:[String:String] = URL(string: "http://localhost?" + query)!.dictionaryFromQuery()

        var response:String = MD5.base64("\(url.user!)\(dictionary["salt"]!)\(url.password!)")
        if let opaque:String = dictionary["opaque"] {
            command += "&opaque=\(opaque)"
            response += opaque
        } else if let challenge:String = dictionary["challenge"] {
            response += challenge
        }

        response = MD5.base64("\(response)\(challenge)")
        command += "&challenge=\(challenge)&response=\(response)"

        return command
    }

    /// The URL of .swf.
    open var swfUrl:String? = nil
    /// The URL of an HTTP referer.
    open var pageUrl:String? = nil
    /// The time to wait for TCP/IP Handshake done.
    open var timeout:Int64 {
        get { return socket.timeout }
        set { socket.timeout = newValue }
    }
    /// The name of application.
    open var flashVer:String = RTMPConnection.defaultFlashVer
    /// The outgoing RTMPChunkSize.
    open var chunkSize:Int = RTMPConnection.defaultChunkSizeS
    /// The URI passed to the RTMPConnection.connect() method.
    open fileprivate(set) var uri:URL? = nil
    /// This instance connected to server(true) or not(false).
    open fileprivate(set) var connected:Bool = false
    /// The object encoding for this RTMPConnection instance.
    open var objectEncoding:UInt8 = RTMPConnection.defaultObjectEncoding
    /// The statistics of total incoming bytes.
    open var totalBytesIn:Int64 {
        return socket.totalBytesIn
    }
    /// The statistics of total outgoing bytes.
    open var totalBytesOut:Int64 {
        return socket.totalBytesOut
    }
    /// The statistics of total RTMPStream counts.
    open var totalStreamsCount:Int {
        return streams.count
    }
    /// The statistics of outgoing queue bytes per second.
    dynamic open fileprivate(set) var previousQueueBytesOut:[Int64] = []
    /// The statistics of incoming bytes per second.
    dynamic open fileprivate(set) var currentBytesInPerSecond:Int32 = 0
    /// The statistics of outgoing bytes per second.
    dynamic open fileprivate(set) var currentBytesOutPerSecond:Int32 = 0

    var socket:RTMPSocketCompatible!
    var streams:[UInt32: RTMPStream] = [:]
    var sequence:Int64 = 0
    var bandWidth:UInt32 = 0
    var streamsmap:[UInt16: UInt32] = [:]
    var operations:[Int: Responder] = [:]
    var windowSizeC:Int64 = RTMPConnection.defaultWindowSizeS {
        didSet {
            guard socket.connected else {
                return
            }
            socket.doOutput(chunk: RTMPChunk(
                    type: .zero,
                    streamId: RTMPChunk.StreamID.control.rawValue,
                    message: RTMPWindowAcknowledgementSizeMessage(UInt32(windowSizeC))
            ), locked: nil)
        }
    }
    var windowSizeS:Int64 = RTMPConnection.defaultWindowSizeS
    var currentTransactionId:Int = 0

    fileprivate var timer:Timer? {
        didSet {
            if let oldValue:Timer = oldValue {
                oldValue.invalidate()
            }
            if let timer:Timer = timer {
                RunLoop.main.add(timer, forMode: .commonModes)
            }
        }
    }
    fileprivate var messages:[UInt16:RTMPMessage] = [:]
    fileprivate var arguments:[Any?] = []
    fileprivate var currentChunk:RTMPChunk? = nil
    fileprivate var measureInterval:Int = 3
    fileprivate var fragmentedChunks:[UInt16:RTMPChunk] = [:]
    fileprivate var previousTotalBytesIn:Int64 = 0
    fileprivate var previousTotalBytesOut:Int64 = 0

    override public init() {
        super.init()
        addEventListener(Event.RTMP_STATUS, selector: #selector(RTMPConnection.on(status:)))
        currentlyListening = true
        keepOnListening()
    }

    deinit {
        currentlyListening = false
        timer = nil
        streams.removeAll()
        removeEventListener(Event.RTMP_STATUS, selector: #selector(RTMPConnection.on(status:)))
    }

    open func call(_ commandName:String, responder:Responder?, arguments:Any?...) {
        guard connected else {
            return
        }
        currentTransactionId += 1
        let message:RTMPCommandMessage = RTMPCommandMessage(
                streamId: 0,
                transactionId: currentTransactionId,
                objectEncoding: objectEncoding,
                commandName: commandName,
                commandObject: nil,
                arguments: arguments
        )
        if (responder != nil) {
            operations[message.transactionId] = responder
        }
        socket.doOutput(chunk: RTMPChunk(message: message), locked: nil)
    }

    @available(iOS 8.0, *)
    open func connect(_ command:String) {
        connect(command, arguments: nil)
    }

    open func connect(_ command:String, arguments:Any?...) {
        guard let uri:URL = URL(string: command), let scheme:String = uri.scheme, !connected && RTMPConnection.supportedProtocols.contains(scheme) else {
            return
        }
        self.uri = uri
        self.arguments = arguments
        timer = Timer(timeInterval: 1.0, target: self, selector: #selector(RTMPConnection.on(timer:)), userInfo: nil, repeats: true)
        switch scheme {
        case "rtmpt":
            socket = socket is RTMPTSocket ? socket : RTMPTSocket()
        default:
            socket = socket is RTMPSocket ? socket : RTMPSocket()
        }
        socket.delegate = self
        socket.securityLevel = uri.scheme == "rtmps" ? .negotiatedSSL : .none
        socket.connect(withName: uri.host!, port: uri.port ?? RTMPConnection.defaultPort)

    }

    open func close() {
        close(isDisconnected: false)
    }

    func close(isDisconnected:Bool) {
        guard connected || isDisconnected else {
            return
        }
        if (!isDisconnected) {
            uri = nil
        }
        for (id, stream) in streams {
            stream.close()
            streams.removeValue(forKey: id)
        }
        socket.close(isDisconnected: false)
        timer = nil
    }

    func createStream(_ stream: RTMPStream) {
        logger.info("Trying to create stream")
        let responder:Responder = Responder(result: { (data) -> Void in
            let id:Any? = data[0]
            if let id:Double = id as? Double {
                logger.info("Creating stream")
                stream.id = UInt32(id)
                logger.info("Stream ID: \(stream.id)")
                self.streams[stream.id] = stream
                stream.readyState = .open
            } else {
                logger.warning("Could not convert \(id) to Double")
            }
        })
        call("createStream", responder: responder)
    }

    func on(status:Notification) {
        let e:Event = Event.from(status)

        guard
                let data:ASObject = e.data as? ASObject,
                let code:String = data["code"] as? String else {
            return
        }

        switch code {
        case Code.connectSuccess.rawValue:
            connected = true
            socket.chunkSizeS = chunkSize
            socket.doOutput(chunk: RTMPChunk(
                    type: .one,
                    streamId: RTMPChunk.StreamID.control.rawValue,
                    message: RTMPSetChunkSizeMessage(UInt32(socket.chunkSizeS))
            ), locked: nil)

        case Code.connectRejected.rawValue:
            guard
                    let uri:URL = uri,
                    let user:String = uri.user,
                    let password:String = uri.password,
                    let description:String = data["description"] as? String else {
                break
            }
            socket.deinitConnection(isDisconnected: false)
            switch true {
            case description.contains("reason=nosuchuser"):
                break
            case description.contains("reason=authfailed"):
                break
            case description.contains("reason=needauth"):
                let command:String = RTMPConnection.createSanJoseAuthCommand(uri, description: description)
                connect(command, arguments: arguments)
            case description.contains("authmod=adobe"):
                if (user == "" || password == "") {
                    close(isDisconnected: true)
                    break
                }
                let query:String = uri.query ?? ""
                let command:String = uri.absoluteString + (query == "" ? "?" : "&") + "authmod=adobe&user=\(user)"
                connect(command, arguments: arguments)
            default:
                break
            }
        case Code.connectClosed.rawValue:
            close(isDisconnected: true)
        default:
            break
        }
    }

    fileprivate func createConnectionChunk() -> RTMPChunk? {
        guard let uri:URL = uri else {
            return nil
        }

        var app:String = uri.path.substring(from: uri.path.characters.index(uri.path.startIndex, offsetBy: 1))
        if let query:String = uri.query {
            app += "?" + query
        }

        currentTransactionId += 1

        let message:RTMPCommandMessage = RTMPCommandMessage(
                streamId: 0,
                transactionId: currentTransactionId,
                // "connect" must be a objectEncoding = 0
                objectEncoding: 0,
                commandName: "connect",
                commandObject: [
                    "app": app,
                    "flashVer": flashVer,
                    "swfUrl": swfUrl,
                    "tcUrl": uri.absoluteWithoutAuthenticationString,
                    "fpad": false,
                    "capabilities": RTMPConnection.defaultCapabilities,
                    "audioCodecs": Support.Sound.mp3.rawValue,
                    "videoCodecs": Support.Video.h264.rawValue,
                    "videoFunction": VideoFunction.clientSeek.rawValue,
                    "pageUrl": pageUrl,
                    "objectEncoding": objectEncoding
                ],
                arguments: arguments
        )

        return RTMPChunk(message: message)
    }

    @objc private func on(timer:Timer) {
        let totalBytesIn:Int64 = self.totalBytesIn
        let totalBytesOut:Int64 = self.totalBytesOut
        currentBytesInPerSecond = Int32(totalBytesIn - previousTotalBytesIn)
        currentBytesOutPerSecond = Int32(totalBytesOut - previousTotalBytesOut)
        previousTotalBytesIn = totalBytesIn
        previousTotalBytesOut = totalBytesOut
        previousQueueBytesOut.append(socket.queueBytesOut)
        for (_, stream) in streams {
            stream.on(timer: timer)
        }
        if (measureInterval <= previousQueueBytesOut.count) {
            var count:Int = 0
            for i in 0..<previousQueueBytesOut.count - 1 {
                if (previousQueueBytesOut[i] < previousQueueBytesOut[i + 1]) {
                    count += 1
                }
            }
            if (count == measureInterval - 1) {
                for (_, stream) in streams {
                    stream.qosDelagate?.didPublishInsufficientBW(stream, withConnection: self)
                }
            }
            previousQueueBytesOut.removeFirst()
        }
    }
}

extension String {
    func substring(start: Int, end: Int) -> String {
        let sIndex = self.index(self.startIndex, offsetBy: start)
        let eIndex = self.index(self.startIndex, offsetBy: end)

        return self.substring(with: sIndex..<eIndex)
    }
}

extension RTMPConnection: RTMPSocketDelegate {
    // MARK: RTMPSocketDelegate


    func didSetReadyState(_ readyState: RTMPSocket.ReadyState) {
        switch readyState {
        case .handshakeDone:
            guard let chunk:RTMPChunk = createConnectionChunk() else {
                close()
                break
            }
            socket.doOutput(chunk: chunk, locked: nil)
        case .closed:
            connected = false
            sequence = 0
            currentChunk = nil
            currentTransactionId = 0
            previousTotalBytesIn = 0
            previousTotalBytesOut = 0
            messages.removeAll()
            operations.removeAll()
            fragmentedChunks.removeAll()
        default:
            break
        }
    }

    func didSetTotalBytesIn(_ totalBytesIn: Int64) {
        guard windowSizeS * (sequence + 1) <= totalBytesIn else {
            return
        }
        socket.doOutput(chunk: RTMPChunk(
                type: sequence == 0 ? .zero : .one,
                streamId: RTMPChunk.StreamID.control.rawValue,
                message: RTMPAcknowledgementMessage(UInt32(totalBytesIn))
        ), locked: nil)
        sequence += 1
    }


    func listen() {
        var d = Data()
        if (socket == nil) {
            return
        }
        RTMPConnection.mutex.sync(execute: {
            d.append(contentsOf: socket.inputBuffer)
        })
        if (d.count == 0) {
            return
        }
        let size = RTMPConnection.getSize(d)
        let header = RTMPConnection.getHeaderSize(d)

        if (d.count > 0 && (size + header) <= d.count) {

            logger.info("Data: \(d.hexEncodedString())\n\nData Size: \(d.count)\nExpected Size: \(size)\nHeader: \(header)")
            let singleChunk = d.subdata(in: 0..<size + header)
            if (singleChunk.count < (size + header)) {
                logger.warning("Chunk incomplete")
                self.socket.inputBuffer.append(d)
                return
            }
            logger.info("Single Chunk: \(singleChunk.hexEncodedString()) Size: \(singleChunk.count)")

            guard let chunk: RTMPChunk = RTMPChunk(singleChunk, size: size) else {
                logger.warning("Failed to chunk")
                self.socket.inputBuffer.append(d)
                return
            }

            if let message: RTMPMessage = chunk.message, chunk.ready {
                if (logger.isEnabledFor(level: .verbose)) {
                    logger.verbose(chunk.description)
                }
                switch chunk.type {
                case .zero:
                    logger.info("Chunk type zero - assigning stream id \(message.streamId)")
                    self.streamsmap[chunk.streamId] = message.streamId
                case .one:
                    logger.info("Chunk type one - getting streamsmap \(String(describing: self.streamsmap[chunk.streamId]))")
                    if let streamId = self.streamsmap[chunk.streamId] {
                        message.streamId = streamId
                    }
                case .two:
                    logger.info("Chunk type two - ignoring")
                    break
                case .three:
                    logger.info("Chunk type three - ignoring")
                    break
                }
                DispatchQueue.main.async {
                    message.execute(self)
                    self.messages[chunk.streamId] = message
                }

            }

//            logger.info("Advancing \(d.hexEncodedString())\nWith: \(singleChunk.hexEncodedString())")
//            d = d.subdata(in: singleChunk.count..<d.count)
//            if (d.count > 0) {
//                size = RTMPConnection.getSize(d)
//                header = RTMPConnection.getHeaderSize(d)
//            }
        }
        if (d.count > 0) {
            self.socket.inputBuffer.append(d)
        }




    }

    static func getHeaderSize(_ data: Data) -> Int {
        var header: Int = 12;

        if (data.bytes[0] & 0b11000000 == 0b00000000) {
            header = 12
        } else if (data.bytes[0] & 0b11000000 == 0b01000000) {
            header = 8
        } else if (data.bytes[0] & 0b11000000 == 0b10000000) {
            header = 4
        }
        return header
    }

    static func getSize(_ chunks: Data) -> Int {
        if (!(chunks.count >= 7)) {
            return 0;
        }
        let subset = chunks.subdata(in: 4..<7)
//        logger.info("Subset: \(subset.hexEncodedString())")
        let size: Int = Int(subset.hexEncodedString(), radix: 16)!
        let headerSize = getHeaderSize(chunks);
        return (size < chunks.count - headerSize) ? size : chunks.count - headerSize
    }
    
    func keepOnListening() {
        self.connectionLock.async {
            logger.info("Starting to listen")
            while (self.currentlyListening) {
                self.listen()
            }
            logger.info("Not listening anymore")
        }
    }
}
