import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/notifications/notifications.dart';

void main() {
  group('FCM message to local notification mapping:', () {
    final displayable = <(RemoteMessage, Type)>[
      (
        const RemoteMessage(data: {'lichess.type': 'newMessage', 'lichess.threadId': 'thethread'}),
        NewMessageNotification,
      ),
      (
        const RemoteMessage(data: {'lichess.type': 'gameMove', 'lichess.fullId': '9wlmxmibr9gh'}),
        CorresGameUpdateNotification,
      ),
      (
        const RemoteMessage(
          data: {'lichess.type': 'challengeCreate', 'lichess.challengeId': 'challenging'},
        ),
        CorresChallengeCreatedNotification,
      ),
      (
        const RemoteMessage(
          data: {
            'lichess.type': 'challengeAccept',
            'lichess.challengeId': 'challenging',
            'lichess.fullId': '9wlmxmibr9gh',
          },
        ),
        CorresChallengeAcceptedNotification,
      ),
    ];

    test('each displayable message maps to its local notification', () {
      for (final (message, expectedType) in displayable) {
        expect(
          FcmMessage.fromRemoteMessage(message).toLocalNotification().runtimeType,
          expectedType,
          reason: 'for $message',
        );
      }
    });

    test('unhandled and malformed messages have no local notification', () {
      final messages = <FcmMessage>[
        FcmMessage.fromRemoteMessage(const RemoteMessage(data: {'lichess.type': 'unknown'})),
        FcmMessage.fromRemoteMessage(const RemoteMessage(data: {})),
        // a correspondence update without a game id cannot be parsed
        FcmMessage.fromRemoteMessage(const RemoteMessage(data: {'lichess.type': 'gameMove'})),
      ];

      for (final message in messages) {
        expect(message.toLocalNotification(), isNull, reason: 'for $message');
      }
    });
  });
}
