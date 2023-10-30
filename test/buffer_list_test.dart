import 'package:buffer_list/buffer_list.dart';
import 'package:magic_buffer_copy/magic_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('single bytes from single buffer', () {
    final bl = BufferList();

    bl.append(Buffer.from('abcd'));

    equals(bl.length, 4);
    equals(bl.get(-1), -1);
    equals(bl.get(0), 97);
    equals(bl.get(1), 98);
    equals(bl.get(2), 99);
    equals(bl.get(3), 100);
    equals(bl.get(4), -1);
  });
}
