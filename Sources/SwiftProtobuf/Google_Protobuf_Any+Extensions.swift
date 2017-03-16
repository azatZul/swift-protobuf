// Sources/SwiftProtobuf/Google_Protobuf_Any+Extensions.swift - Well-known Any type
//
// Copyright (c) 2014 - 2017 Apple Inc. and the project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information:
// https://github.com/apple/swift-protobuf/blob/master/LICENSE.txt
//
// -----------------------------------------------------------------------------
///
/// Extends the Google_Protobuf_Any and Message structs with various
/// custom behaviors.
///
// -----------------------------------------------------------------------------

import Foundation


internal let defaultTypePrefix: String = "type.googleapis.com"

internal func typeName(fromMessage message: Message) -> String {
  let messageType = type(of: message)
  return messageType.protoMessageName
}

internal func buildTypeURL(forMessage message: Message, typePrefix: String) -> String {
  var url = typePrefix
  if typePrefix.isEmpty || typePrefix.characters.last != "/" {
    url += "/"
  }
  return url + typeName(fromMessage: message)
}


public extension Message {
  /// Initialize this message from the provided `google.protobuf.Any`
  /// well-known type.
  ///
  /// This corresponds to the `unpack` method in the Google C++ API.
  ///
  /// If the Any object was decoded from Protobuf Binary or JSON
  /// format, then the enclosed field data was stored and is not
  /// fully decoded until you unpack the Any object into a message.
  /// As such, this method will typically need to perform a full
  /// deserialization of the enclosed data and can fail for any
  /// reason that deserialization can fail.
  ///
  /// See `Google_Protobuf_Any.unpackTo()` for more discussion.
  ///
  /// - Parameter unpackingAny: the message to decode.
  /// - Throws: an instance of `AnyUnpackError`, `JSONDecodingError`, or
  ///   `BinaryDecodingError` on failure.
  public init(unpackingAny: Google_Protobuf_Any) throws {
    self.init()
    try unpackingAny.unpackTo(target: &self)
  }
}


public extension Google_Protobuf_Any {

  /// Initialize an Any object from the provided message.
  ///
  /// This corresponds to the `pack` operation in the C++ API.
  ///
  /// Unlike the C++ implementation, the message is not immediately
  /// serialized; it is merely stored until the Any object itself
  /// needs to be serialized.  This design avoids unnecessary
  /// decoding/recoding when writing JSON format.
  ///
  public init(message: Message, typePrefix: String = defaultTypePrefix) {
    self.init()
    _storage._message = message
    typeURL = buildTypeURL(forMessage:message, typePrefix: typePrefix)
  }


  /// Decode an Any object from Protobuf Text Format.
  public init(textFormatString: String, extensions: ExtensionSet? = nil) throws {
    self.init()
    var textDecoder = try TextFormatDecoder(messageType: Google_Protobuf_Any.self,
                                            text: textFormatString,
                                            extensions: extensions)
    try decodeTextFormat(decoder: &textDecoder)
    if !textDecoder.complete {
      throw TextFormatDecodingError.trailingGarbage
    }
  }

  ///
  /// Update the provided object from the data in the Any container.
  /// This is essentially just a deferred deserialization; the Any
  /// may hold protobuf bytes or JSON fields depending on how the Any
  /// was itself deserialized.
  ///
  public func unpackTo<M: Message>(target: inout M) throws {
    try _storage.unpackTo(target: &target)
  }

  public var hashValue: Int {
    return _storage.hashValue
  }

}


extension Google_Protobuf_Any: _CustomJSONCodable {

  // _value is computed be on demand conversions.
  public var _value: Data? {
    get {
      if let value = _storage._valueData {
        return value
      } else if let message = _storage._message {
        do {
          return try message.serializedData()
        } catch {
          return nil
        }
      } else if _storage._contentJSON != nil && !_storage._typeURL.isEmpty {
        // Transcode JSON-to-protobuf by decoding/recoding:
        // Well-known types are always available:
        let encodedTypeName = typeName(fromURL: _storage._typeURL)
        if let messageType = Google_Protobuf_Any.lookupMessageType(forMessageName: encodedTypeName) {
          do {
            let m = try messageType.init(unpackingAny: self)
            return try m.serializedData()
          } catch {
            return nil
          }
        }
        // TODO: Google spec requires a lot more work in the general case:
        // let encodedType = ... fetch google.protobuf.Type based on typeURL ...
        // let type = Google_Protobuf_Type(protobuf: encodedType)
        // return ProtobufDynamic(type: type, any: self)?.serializeProtobuf()

        // See the comments in serializeJSON() above for more discussion of what would be needed to fully implement this.
        return nil
      } else {
        return nil
      }
    }
    set {
      _ = _uniqueStorage()
      _storage._valueData = newValue
      _storage._message = nil
      _storage._contentJSON = nil
    }
  }

  // Custom text format decoding support for Any objects.
  // (Note: This is not a part of any protocol; it's invoked
  // directly from TextFormatDecoder whenever it sees an attempt
  // to decode an Any object)
  internal mutating func decodeTextFormat(decoder: inout TextFormatDecoder) throws {
    // First, check if this uses the "verbose" Any encoding.
    // If it does, and we have the type available, we can
    // eagerly decode the contained Message object.
    if let url = try decoder.scanner.nextOptionalAnyURL() {
      try _uniqueStorage().decodeTextFormat(typeURL: url, decoder: &decoder)
    } else {
      // This is not using the specialized encoding, so we can use the
      // standard path to decode the binary value.
      try decodeMessage(decoder: &decoder)
    }
  }

  internal func encodedJSONString() throws -> String {
    return try _storage.encodedJSONString()
  }

  internal mutating func decodeJSON(from decoder: inout JSONDecoder) throws {
    try _uniqueStorage().decodeJSON(from: &decoder)
  }

}
