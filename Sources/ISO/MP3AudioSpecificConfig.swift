import Foundation
import AVFoundation

/**
 The Audio Specific Config is the global header for MPEG-4 Audio
 
 - seealse:
  - http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Audio_Specific_Config
  - http://wiki.multimedia.cx/?title=Understanding_AAC
 */
struct MP3AudioSpecificConfig {
    static let ADTSHeaderSize:Int = 0

    var frequency:SamplingFrequency
    var channel:ChannelConfiguration
    var frameLengthFlag:Bool = false

    var bytes:[UInt8] {
        var bytes:[UInt8] = [UInt8](repeating: 0, count: 2)
        bytes[0] = (0 << 3) | (frequency.rawValue >> 1 & 0x3)
        bytes[1] = (frequency.rawValue & 0x1) << 7 | (channel.rawValue & 0xF) << 3
        return bytes
    }

    init?(bytes:[UInt8]) {
        print("Init MP3AudioSpecificConfig #")
        guard let
            let frequency:SamplingFrequency = SamplingFrequency(rawValue: (bytes[0] & 0b00000111) << 1 | (bytes[1] >> 7)),
            let channel:ChannelConfiguration = ChannelConfiguration(rawValue: (bytes[1] & 0b01111000) >> 3) else {
            return nil
        }
        self.frequency = frequency
        self.channel = channel
    }

    init(frequency:SamplingFrequency, channel:ChannelConfiguration) {
        print("Init MP3AudioSpecificConfig #2")
        self.frequency = frequency
        self.channel = channel
    }

    init(formatDescription: CMFormatDescription) {
        print("Init MP3AudioSpecificConfig #1")
        let asbd:AudioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)!.pointee
        frequency = SamplingFrequency(sampleRate: asbd.mSampleRate)
        channel = ChannelConfiguration(rawValue: UInt8(asbd.mChannelsPerFrame))!
    }

    func createAudioStreamBasicDescription() -> AudioStreamBasicDescription {
        print("Creating MP3 audio stream")
        var asbd:AudioStreamBasicDescription = AudioStreamBasicDescription()
        asbd.mSampleRate = frequency.sampleRate
        asbd.mFormatID = kAudioFormatMPEGLayer3
        asbd.mFormatFlags = 0
        asbd.mBytesPerPacket = 0
        asbd.mFramesPerPacket = frameLengthFlag ? 960 : 1024
        asbd.mBytesPerFrame = 0
        asbd.mChannelsPerFrame = UInt32(channel.rawValue)
        asbd.mBitsPerChannel = 0
        asbd.mReserved = 0
        return asbd
    }
}

extension MP3AudioSpecificConfig: CustomStringConvertible {
    // MARK: CustomStringConvertible
    var description:String {
        return Mirror(reflecting: self).description
    }
}

// MARK: -