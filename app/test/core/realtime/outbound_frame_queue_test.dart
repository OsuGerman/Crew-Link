import 'package:crew_link/core/realtime/outbound_frame_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutboundFrameQueue', () {
    test('starts empty', () {
      final queue = OutboundFrameQueue();
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
      expect(queue.drain(), isEmpty);
    });

    test('drain returns frames in original FIFO order and clears the queue',
        () {
      final queue = OutboundFrameQueue();
      queue.enqueue('hazard-1');
      queue.enqueue('hazard_remove-1');
      queue.enqueue('waypoint-1');

      expect(
        queue.drain(),
        ['hazard-1', 'hazard_remove-1', 'waypoint-1'],
        reason: 'kausal abhängige Frames müssen in Sendereihenfolge bleiben',
      );
      expect(queue.isEmpty, isTrue);
      expect(queue.drain(), isEmpty,
          reason: 'second drain must not replay old frames');
    });

    test('overflow drops the OLDEST frame (FIFO drop)', () {
      final queue = OutboundFrameQueue(maxLength: 3);
      queue.enqueue('a');
      queue.enqueue('b');
      queue.enqueue('c');
      queue.enqueue('d'); // overflow → 'a' fliegt raus

      expect(queue.length, 3);
      expect(queue.drain(), ['b', 'c', 'd']);
    });

    test('default capacity is the documented constant', () {
      final queue = OutboundFrameQueue();
      for (var i = 0; i < OutboundFrameQueue.defaultMaxLength + 5; i++) {
        queue.enqueue('frame-$i');
      }
      expect(queue.length, OutboundFrameQueue.defaultMaxLength);
      // Die ältesten 5 wurden verworfen — Frame 5 ist jetzt der älteste.
      expect(queue.drain().first, 'frame-5');
    });

    test('queue is reusable after drain', () {
      final queue = OutboundFrameQueue(maxLength: 2);
      queue.enqueue('a');
      queue.drain();
      queue.enqueue('b');
      queue.enqueue('c');
      expect(queue.drain(), ['b', 'c']);
    });
  });
}
