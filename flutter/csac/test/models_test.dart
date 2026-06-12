import 'package:flutter_test/flutter_test.dart';

import 'package:hgsc/src/api_client.dart';
import 'package:hgsc/src/models.dart';

void main() {
  test('message accepts numeric zero timestamps', () {
    final message = ChatMessage.fromJson({
      'id': 14,
      'uid': 4,
      'nickname': 'Wansheng',
      'content': 'hello',
      'add_time': '2026-04-29 18:48:35',
      'created_at': 0,
    });

    expect(message.id, 14);
    expect(message.senderId, 4);
    expect(message.time, '2026-04-29 18:48:35');
  });

  test('friend display name prefers remark', () {
    final friend = Friend.fromJson({
      'uid': 25,
      'friend_id': 25,
      'nickname': 'Leon',
      'remark': 'Work',
      'unread_count': 3,
    });

    expect(friend.name, 'Work');
    expect(friend.unreadCount, 3);
  });

  test('friend uid accepts friend id aliases', () {
    final byFriendUid = Friend.fromJson({
      'friend_uid': 42,
      'nickname': 'Alice',
    });
    final byFriendId = Friend.fromJson({'friend_id': 43, 'nickname': 'Bob'});

    expect(byFriendUid.uid, 42);
    expect(byFriendId.uid, 43);
  });

  test('message accepts read status aliases', () {
    final readByStatus = ChatMessage.fromJson({
      'id': 15,
      'from_uid': 4,
      'nickname': 'Leon',
      'content': 'hello',
      'read_status': 1,
    });
    final readByTime = ChatMessage.fromJson({
      'id': 16,
      'from_uid': 4,
      'nickname': 'Leon',
      'content': 'hello',
      'read_at': '2026-05-30 12:00:00',
    });

    expect(readByStatus.isRead, isTrue);
    expect(readByTime.isRead, isTrue);
  });

  test('server URL accepts bare host and host with port', () {
    expect(CsacApiClient.defaultBaseUrl, 'http://hgsc.happygray.work/rpc/UniCsAC.php');
    expect(
      CsacApiClient.normalizeServerUrl('192.168.1.10'),
      'http://192.168.1.10/rpc/UniCsAC.php',
    );
    expect(
      CsacApiClient.normalizeServerUrl('192.168.1.10:8080'),
      'http://192.168.1.10:8080/rpc/UniCsAC.php',
    );
  });

  test('relative media URLs follow configured API origin', () {
    configureApiAssetBaseUrl('http://192.168.1.10:8080/rpc/UniCsAC.php');

    expect(
      normalizeApiUrl('/uploads/avatar.png'),
      'http://192.168.1.10:8080/uploads/avatar.png',
    );

    configureApiAssetBaseUrl(CsacApiClient.defaultBaseUrl);
  });

}
