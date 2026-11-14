import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';

export 'chat_message.dart';

part 'chat.freezed.dart';

@immutable
sealed class const ChatOptions() {
  StringId get id;
  LightUser? get opponent;
  bool get isPublic;
  bool get writeable;

  @override
  String toString() =>
      'ChatOptions(id: $id, opponent: $opponent, isPublic: $isPublic, writeable: $writeable)';
}

@freezed
abstract class const GameChatOptions._() extends ChatOptions with _$GameChatOptions {
  const factory({required GameFullId id, required LightUser? opponent}) = _GameChatOptions;

  @override
  bool get isPublic => false;

  @override
  bool get writeable => true;
}
