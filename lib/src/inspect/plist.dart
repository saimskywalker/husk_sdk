import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Parses a property list in XML or binary (`bplist00`) form.
///
/// Returns Dart values: `Map<String, Object?>`, `List<Object?>`, `String`,
/// `int`, `double`, `bool`, `DateTime` and `Uint8List`. Throws
/// [FormatException] for anything malformed, including cyclic or deeply
/// nested binary lists, so a crafted file cannot hang or crash the caller.
Object? parsePlist(Uint8List bytes) {
  if (bytes.length >= 8 &&
      ascii.decode(bytes.sublist(0, 6), allowInvalid: true) == 'bplist') {
    return _BinaryPlist(bytes).parse();
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const FormatException('property list is neither XML nor binary');
  }
  return _parseXml(text);
}

Object? _parseXml(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw FormatException('invalid XML property list: ${e.message}');
  }
  final root = doc.rootElement;
  if (root.name.local != 'plist') {
    throw const FormatException('XML root element is not <plist>');
  }
  final values = root.childElements.toList();
  if (values.length != 1) {
    throw const FormatException('<plist> must contain exactly one value');
  }
  return _xmlValue(values.single, 0);
}

Object? _xmlValue(XmlElement e, int depth) {
  if (depth > 64) throw const FormatException('property list nested too deep');
  return switch (e.name.local) {
    'dict' => _xmlDict(e, depth),
    'array' => [for (final c in e.childElements) _xmlValue(c, depth + 1)],
    'string' => e.innerText,
    'integer' =>
      int.tryParse(e.innerText.trim()) ??
          (throw FormatException('bad <integer> "${e.innerText}"')),
    'real' =>
      double.tryParse(e.innerText.trim()) ??
          (throw FormatException('bad <real> "${e.innerText}"')),
    'true' => true,
    'false' => false,
    'date' =>
      DateTime.tryParse(e.innerText.trim()) ??
          (throw FormatException('bad <date> "${e.innerText}"')),
    'data' => _base64(e.innerText),
    final other => throw FormatException(
      'unknown property list element <$other>',
    ),
  };
}

Map<String, Object?> _xmlDict(XmlElement e, int depth) {
  final children = e.childElements.toList();
  if (children.length.isOdd) {
    throw const FormatException('<dict> has a key without a value');
  }
  final map = <String, Object?>{};
  for (var i = 0; i < children.length; i += 2) {
    if (children[i].name.local != 'key') {
      throw const FormatException('<dict> entry does not start with <key>');
    }
    map[children[i].innerText] = _xmlValue(children[i + 1], depth + 1);
  }
  return map;
}

Uint8List _base64(String text) {
  try {
    return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    throw const FormatException('bad <data> payload');
  }
}

/// Reader for Apple's binary property list format, version 00.
class _BinaryPlist {
  _BinaryPlist(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  late final int _offsetSize;
  late final int _refSize;
  late final int _objectCount;
  late final int _offsetTable;
  final Set<int> _active = {};

  Object? parse() {
    if (bytes.length < 40) {
      throw const FormatException('binary plist too short');
    }
    final t = bytes.length - 32;
    _offsetSize = bytes[t + 6];
    _refSize = bytes[t + 7];
    _objectCount = _uint(t + 8, 8);
    final top = _uint(t + 16, 8);
    _offsetTable = _uint(t + 24, 8);
    if (_offsetSize < 1 ||
        _offsetSize > 8 ||
        _refSize < 1 ||
        _refSize > 8 ||
        _objectCount < 1 ||
        top >= _objectCount ||
        _offsetTable + _objectCount * _offsetSize > t) {
      throw const FormatException('binary plist trailer is inconsistent');
    }
    return _object(top, 0);
  }

  int _uint(int at, int size) {
    if (at < 0 || at + size > bytes.length) {
      throw const FormatException('binary plist offset out of range');
    }
    var v = 0;
    for (var i = 0; i < size; i++) {
      v = (v << 8) | bytes[at + i];
    }
    if (v < 0) throw const FormatException('binary plist integer too large');
    return v;
  }

  Object? _object(int ref, int depth) {
    if (ref >= _objectCount) {
      throw const FormatException('bad object reference');
    }
    if (depth > 64) {
      throw const FormatException('property list nested too deep');
    }
    if (!_active.add(ref)) throw const FormatException('cyclic property list');
    try {
      return _decode(
        _uint(_offsetTable + ref * _offsetSize, _offsetSize),
        depth,
      );
    } finally {
      _active.remove(ref);
    }
  }

  Object? _decode(int at, int depth) {
    if (at >= bytes.length - 32) {
      throw const FormatException('binary plist object out of range');
    }
    final marker = bytes[at];
    final info = marker & 0x0f;
    switch (marker >> 4) {
      case 0x0:
        return switch (info) {
          0x8 => false,
          0x9 => true,
          0x0 => null,
          _ => throw const FormatException('unsupported binary plist marker'),
        };
      case 0x1:
        final size = 1 << info;
        if (size > 8) throw const FormatException('integer too large');
        if (size < 8) return _uint(at + 1, size);
        _uint(at + 1, 8); // bounds check
        return data.getInt64(at + 1);
      case 0x2 when info == 2:
        _uint(at + 1, 4);
        return data.getFloat32(at + 1).toDouble();
      case 0x2 when info == 3:
        _uint(at + 1, 8);
        return data.getFloat64(at + 1);
      case 0x2:
        throw const FormatException('unsupported real size');
      case 0x3:
        _uint(at + 1, 8);
        final seconds = data.getFloat64(at + 1);
        return DateTime.utc(
          2001,
        ).add(Duration(microseconds: (seconds * 1000000).round()));
      case 0x4:
        final (len, start) = _length(info, at);
        _checkEnd(start + len, 'data');
        return Uint8List.fromList(bytes.sublist(start, start + len));
      case 0x5:
        final (len, start) = _length(info, at);
        _checkEnd(start + len, 'string');
        return latin1.decode(bytes.sublist(start, start + len));
      case 0x6:
        final (len, start) = _length(info, at);
        _checkEnd(start + len * 2, 'string');
        return String.fromCharCodes([
          for (var i = 0; i < len; i++) data.getUint16(start + i * 2),
        ]);
      case 0xA:
        final (len, start) = _length(info, at);
        _checkRefs(start, len);
        return [for (var i = 0; i < len; i++) _ref(start, i, depth)];
      case 0xD:
        final (len, start) = _length(info, at);
        _checkRefs(start, len * 2);
        final map = <String, Object?>{};
        for (var i = 0; i < len; i++) {
          final key = _ref(start, i, depth);
          if (key is! String) {
            throw const FormatException('dictionary key is not a string');
          }
          map[key] = _ref(start, len + i, depth);
        }
        return map;
      case final type:
        throw FormatException(
          'unsupported binary plist type 0x${type.toRadixString(16)}',
        );
    }
  }

  /// The object that the [i]th reference of a collection at [start] names.
  Object? _ref(int start, int i, int depth) =>
      _object(_uint(start + i * _refSize, _refSize), depth + 1);

  void _checkEnd(int end, String what) {
    if (end > bytes.length) throw FormatException('$what out of range');
  }

  void _checkRefs(int start, int count) {
    if (count > _objectCount * 2 || start + count * _refSize > bytes.length) {
      throw const FormatException('collection out of range');
    }
  }

  /// Returns (length, offset of the payload).
  (int, int) _length(int info, int at) {
    if (info != 0x0f) return (info, at + 1);
    final marker = bytes[at + 1];
    if (marker >> 4 != 0x1) throw const FormatException('bad length marker');
    final size = 1 << (marker & 0x0f);
    if (size > 8) throw const FormatException('length too large');
    return (_uint(at + 2, size), at + 2 + size);
  }
}
