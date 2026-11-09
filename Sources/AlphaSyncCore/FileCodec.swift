import Foundation

public enum FileCodec {
    public static func text(_ data: Data, applet: NeoApplet) throws -> String {
        switch applet.id {
        case NeoApplet.alphaWord: return try AlphaWordCodec.decode(data)
        case NeoApplet.dictionary: return try DictionaryCodec.decode(data)
        default:
            let digits = Array("0123456789abcdef".utf8)
            var encoded = Data(capacity: data.count * 2)
            for byte in data { encoded.append(digits[Int(byte >> 4)]); encoded.append(digits[Int(byte & 15)]) }
            let hex = String(decoding: encoded, as: UTF8.self)
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <alphasync>
            <appletID>0x\(String(format: "%04x", applet.id))</appletID>
            <appletVersionMajor>\(applet.major)</appletVersionMajor>
            <appletVersionMinor>\(applet.minor)</appletVersionMinor>
            <data>\(hex)</data>
            </alphasync>
            """
        }
    }
    public static func converted(_ text: String, applet: UInt16, limits: NeoFileLimits, dictionaryConsent: String? = nil) throws -> Data {
        switch applet {
        case NeoApplet.alphaWord: return try AlphaWordCodec.encode(text, limits: limits)
        case NeoApplet.dictionary:
            let conversion = try DictionaryCodec.convert(text)
            guard text.isEmpty || conversion.report.acceptedWords > 0 else {
                throw NeoError.device("This text contains no dictionary words the Neo can store. Edit the text, or use Clear File if you intend to empty the dictionary.")
            }
            let result = conversion.data
            guard result.count <= limits.maximum else { throw NeoError.tooLarge(required: result.count, maximum: limits.maximum) }
            if conversion.report.omittedWords > 0 && dictionaryConsent != text {
                throw DictionaryImportWarning(sourceText: text, report: conversion.report)
            }
            return result
        default: throw NeoError.device("This applet’s file format is read-only. Its files can be backed up as lossless XML.")
        }
    }
    public static func fileExtension(applet: UInt16) -> String {
        applet == NeoApplet.alphaWord || applet == NeoApplet.dictionary ? "txt" : "xml"
    }
}
