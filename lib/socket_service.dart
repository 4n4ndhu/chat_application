import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';

class User {
  final String id;
  final String name;

  User({required this.id, required this.name});

  factory User.fromJson(Map<String, dynamic> json) =>
      User(id: json['id'], name: json['name']);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class Message {
  final String senderName;
  final String? text;
  final String? audioBase64;
  final bool isMine;
  DateTime timestamp;
  final String id;

  Message({
    required this.senderName,
    this.text,
    this.audioBase64,
    required this.isMine,
    required this.id,
  }) : timestamp = DateTime.now();

  bool get isAudio => audioBase64 != null;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      senderName: json['senderName'],
      text: json['text'],
      audioBase64: json['audioBase64'],
      isMine: json['isMine'],
      id: json['id'] ?? const Uuid().v4(),
    )..timestamp = DateTime.parse(json['timestamp']);
  }

  Map<String, dynamic> toJson() => {
        'senderName': senderName,
        'text': text,
        'audioBase64': audioBase64,
        'isMine': isMine,
        'timestamp': timestamp.toIso8601String(),
        'id': id,
      };
}

class SocketService {
  late IO.Socket socket;
  late User currentUser;

  List<User> onlineUsers = [];
  Map<String, List<Message>> messagesByUserId = {};
  Map<String, int> unreadCountByUserId = {};

  Function(List<User>)? onUserListUpdated;
  Function()? onMessagesUpdated;

  void connect(String userName) {
    socket = IO.io('http://62.72.31.17:3002', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
  final socketId = socket.id;
  if (socketId != null) {
    currentUser = User(id: socketId, name: userName);
    socket.emit('join', currentUser.toJson());
  } else {
    print('Socket ID is null!');
  }
});


    socket.on('user_list', (data) {
      final users = (data as List)
          .map((u) => User.fromJson(u))
          .where((u) => u.id != currentUser.id)
          .toList();
      onlineUsers = users;
      onUserListUpdated?.call(users);
    });

    socket.on('private_message', (data) {
      final from = User.fromJson(data['from']);
      final message = data['message'] as String?;
      final audioBase64 = data['audioBase64'] as String?;

      _addMessage(
        from.id,
        Message(
          senderName: from.name,
          text: message,
          audioBase64: audioBase64,
          isMine: false,
          id: data['id'] ?? const Uuid().v4(),
        ),
        markUnread: true,
      );
    });

    socket.onDisconnect((_) {
      print('Disconnected from server');
    });
  }

  void _addMessage(String userId, Message message, {bool markUnread = true}) {
    messagesByUserId.putIfAbsent(userId, () => <Message>[]);
    messagesByUserId[userId]!.add(message);

    if (markUnread) {
      unreadCountByUserId[userId] = (unreadCountByUserId[userId] ?? 0) + 1;
    }

    onMessagesUpdated?.call();
  }

  void sendPrivateMessage({
    required User to,
    String? message,
    String? audioBase64,
  }) {
    final messageId = const Uuid().v4();

    socket.emit('private_message', {
      'to': to.toJson(),
      'message': message,
      'audioBase64': audioBase64,
      'from': currentUser.toJson(),
      'id': messageId,
    });

    _addMessage(
      to.id,
      Message(
        senderName: currentUser.name,
        text: message,
        audioBase64: audioBase64,
        isMine: true,
        id: messageId,
      ),
      markUnread: false,
    );
  }

  void markMessagesRead(String userId) {
    unreadCountByUserId[userId] = 0;
    onMessagesUpdated?.call();
  }

  void dispose() {
    socket.disconnect();
    socket.dispose();
  }
}
