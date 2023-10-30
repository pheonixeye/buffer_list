import 'dart:typed_data';

import 'package:magic_buffer_copy/magic_buffer.dart';

class BufferList {
  List<Buffer> _bufs = [];
  int length = 0;

  BufferList([Buffer? buf]) {
    if (buf != null) {
      append(buf);
    }
  }

  static isBufferList(b) {
    return b != null && b is BufferList;
  }

  BufferList _new([dynamic buf]) {
    return BufferList(buf);
  }

  List<int>? _offset(int offset) {
    if (offset == 0) {
      return [0, 0];
    }

    int tot = 0;

    for (int i = 0; i < _bufs.length; i++) {
      final _t = tot + _bufs[i].length;
      if (offset < _t || i == _bufs.length - 1) {
        return [i, offset - tot];
      }
      tot = _t;
    }
    return null;
  }

  int _reverseOffset(blOffset) {
    final bufferId = blOffset[0];
    int offset = blOffset[1];

    for (int i = 0; i < bufferId; i++) {
      offset += _bufs[i].length;
    }

    return offset;
  }

  int get(int index) {
    if (index > length || index < 0) {
      return -1;
    }
    try {
      final offset = _offset(index)!;
      return _bufs[offset[0]][offset[1]];
    } catch (e) {
      rethrow;
    }
  }

  slice(int start, int end) {
    if (start < 0) {
      start += length;
    }

    if (end < 0) {
      end += length;
    }

    return copy(null, 0, start, end);
  }

  copy(Buffer? dst, [int? dstStart = 0, int srcStart = 0, int? srcEnd]) {
    if (srcStart < 0) {
      srcStart = 0;
    }

    if (srcEnd == null || srcEnd > length) {
      srcEnd = length;
    }

    if (srcStart >= length) {
      return dst ?? Buffer.alloc(0);
    }

    if (srcEnd <= 0) {
      return dst ?? Buffer.alloc(0);
    }

    final copy = dst == null;
    final off = _offset(srcStart)!;
    final len = srcEnd - srcStart;
    int bytes = len;
    int bufoff = (copy && dstStart != null) == true ? dstStart! : 0;
    int start = off[1];

    // copy/slice everything
    if (srcStart == 0 && srcEnd == length) {
      if (!copy) {
        // slice, but full concat if multiple buffers
        return _bufs.length == 1 ? _bufs[0] : Buffer.concat(_bufs, length);
      }

      // copy, need to copy individual buffers
      for (int i = 0; i < _bufs.length; i++) {
        _bufs[i].copy(dst!, bufoff);
        bufoff += _bufs[i].length;
      }

      return dst;
    }

    // easy, cheap case where it's a subset of one of the buffers
    if (bytes <= _bufs[off[0]].length - start) {
      return copy
          ? _bufs[off[0]].copy(dst!, dstStart!, start, start + bytes)
          : _bufs[off[0]].slice(start, start + bytes);
    }

    if (!copy) {
      // a slice, we need something to copy in to
      dst = Buffer.allocUnsafe(len);
    }

    for (int i = off[0]; i < _bufs.length; i++) {
      final l = _bufs[i].length - start;

      if (bytes > l) {
        _bufs[i].copy(dst!, bufoff, start);
        bufoff += l;
      } else {
        _bufs[i].copy(dst!, bufoff, start, start + bytes);
        bufoff += l;
        break;
      }

      bytes -= l;

      //TODO
      if (start > 0) {
        start = 0;
      }
    }

    // safeguard so that we don't return uninitialized memory
    if (dst!.length > bufoff) return dst.slice(0, bufoff);

    return dst;
  }

  shallowSlice([int start = 0, int? end]) {
    end = end ?? length;

    if (start < 0) {
      start += length;
    }

    if (end < 0) {
      end += length;
    }

    if (start == end) {
      return _new();
    }

    final startOffset = _offset(start)!;
    final endOffset = _offset(end)!;
    final buffers = _bufs.sublist(startOffset[0], endOffset[0] + 1);

    if (endOffset[1] == 0) {
      buffers.removeLast();
    } else {
      buffers[buffers.length - 1] =
          buffers[buffers.length - 1].slice(0, endOffset[1]);
    }

    if (startOffset[1] != 0) {
      buffers[0] = buffers[0].slice(startOffset[1]);
    }

    return _new(buffers);
  }

  toString_(encoding, start, end) {
    return (slice(start, end) as Buffer).toString_({"encoding": encoding});
  }

  BufferList consume(int bytes) {
    // first, normalize the argument, in accordance with how Buffer does it
    bytes = bytes.truncate();
    // do nothing if not a positive number
    if (bytes <= 0) return this;

    while (_bufs.isNotEmpty) {
      if (bytes >= _bufs[0].length) {
        bytes -= _bufs[0].length;
        length -= _bufs[0].length;
        _bufs.removeAt(0);
      } else {
        _bufs[0] = _bufs[0].slice(bytes);
        length -= bytes;
        break;
      }
    }

    return this;
  }

  BufferList duplicate() {
    final copy = _new();

    for (int i = 0; i < _bufs.length; i++) {
      copy.append(_bufs[i]);
    }

    return copy;
  }

  BufferList append([dynamic buf]) {
    if (buf == null) {
      return this;
    }

    if (buf is Buffer) {
      // append a view of the underlying ArrayBuffer
      _appendBuffer(Buffer.from(buf.buffer, buf.offset, buf.length));
    } else if (buf is List || buf is Uint8List) {
      for (int i = 0; i < buf.length; i++) {
        append(buf[i]);
      }
    } else if (BufferList.isBufferList(buf)) {
      // unwrap argument into individual BufferLists
      for (int i = 0; i < buf._bufs.length; i++) {
        append(buf._bufs[i]);
      }
    } else {
      // coerce number arguments to strings, since Buffer(number) does
      // uninitialized memory allocation
      if (buf is int) {
        buf = buf.toString();
      }

      _appendBuffer(Buffer.from(buf));
    }

    return this;
  }

  void _appendBuffer(Buffer buf) {
    _bufs.add(buf);
    length += buf.length;
  }

  int indexOf(dynamic search, [int? offset, String? encoding]) {
    if (search is Function) {
      throw ArgumentError.value(
          'The "value" argument must be one of type string, Buffer, BufferList, or Uint8Array.');
    } else if (search is int) {
      search = Buffer.from([search]);
    } else if (search is String) {
      search = Buffer.from(search, 0, 0, encoding!);
    } else if (isBufferList(search)) {
      search = (search as BufferList).slice(0, 0);
    } else if (search is Buffer) {
      search = Buffer.from(search.buffer, search.offset, search.length);
    } else if (!Buffer.isBuffer(search)) {
      search = Buffer.from(search);
    }

    offset = offset ?? 0;

    if (offset < 0) {
      offset = length + offset;
    }

    if (offset < 0) {
      offset = 0;
    }

    if (search.length == 0) {
      return offset > length ? length : offset;
    }

    final blOffset = _offset(offset)!;
    int blIndex =
        blOffset[0]; // index of which internal buffer we're working on
    int buffOffset =
        blOffset[1]; // offset of the internal buffer we're working on

    // scan over each buffer
    for (; blIndex < _bufs.length; blIndex++) {
      final buff = _bufs[blIndex];

      while (buffOffset < buff.length) {
        final availableWindow = buff.length - buffOffset;

        if (availableWindow >= search.length) {
          final nativeSearchResult = buff.indexOf(search, buffOffset);

          if (nativeSearchResult != -1) {
            return _reverseOffset([blIndex, nativeSearchResult]);
          }

          buffOffset = buff.length - search.length + 1
              as int; // end of native search window
        } else {
          final revOffset = _reverseOffset([blIndex, buffOffset]);

          if (_match(revOffset, search)) {
            return revOffset;
          }

          buffOffset++;
        }
      }

      buffOffset = 0;
    }

    return -1;
  }

  bool _match(int offset, Buffer search) {
    if (length - offset < search.length) {
      return false;
    }

    for (int searchOffset = 0; searchOffset < search.length; searchOffset++) {
      if (get(offset + searchOffset) != search[searchOffset]) {
        return false;
      }
    }
    return true;
  }

  read([int offset = 0, int byteLength = 0]) {
    return slice(offset, offset + byteLength);
  }

  readDoubleBE([int offset = 0]) {
    return slice(offset, offset + 8);
  }

  readDoubleLE([int offset = 0]) {
    return slice(offset, offset + 8);
  }

  readFloatBE([int offset = 0]) {
    return slice(offset, offset + 4);
  }

  readFloatLE([int offset = 0]) {
    return slice(offset, offset + 4);
  }

  readInt32BE([int offset = 0]) {
    return slice(offset, offset + 4);
  }

  readInt32LE([int offset = 0]) {
    return slice(offset, offset + 4);
  }

  readUInt32BE([int offset = 0]) {
    return slice(offset, offset + 4);
  }

  readUInt32LE([int offset = 0]) {
    return slice(offset, offset + 4);
  }

  readInt16BE([int offset = 0]) {
    return slice(offset, offset + 2);
  }

  readInt16LE([int offset = 0]) {
    return slice(offset, offset + 2);
  }

  readUInt16BE([int offset = 0]) {
    return slice(offset, offset + 2);
  }

  readUInt16LE([int offset = 0]) {
    return slice(offset, offset + 2);
  }

  readInt8([int offset = 0]) {
    return slice(offset, offset + 1);
  }

  readUInt8([int offset = 0]) {
    return slice(offset, offset + 1);
  }

  readIntBE([int offset = 0]) {
    throw UnimplementedError();
  }

  readIntLE([int offset = 0]) {
    throw UnimplementedError();
  }

  readUIntBE([int offset = 0]) {
    throw UnimplementedError();
  }

  readUIntLE([int offset = 0]) {
    throw UnimplementedError();
  }
}
