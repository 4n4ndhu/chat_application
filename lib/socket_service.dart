import 'package:socket_io_client/socket_io_client.dart' as IO;

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
  final String text;
  final bool isMine;
  DateTime timestamp;

  Message(this.senderName, this.text, {required this.isMine})
      : timestamp = DateTime.now();

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      json['senderName'],
      json['text'],
      isMine: json['isMine'],
    )..timestamp = DateTime.parse(json['timestamp']);
  }

  Map<String, dynamic> toJson() => {
        'senderName': senderName,
        'text': text,
        'isMine': isMine,
        'timestamp': timestamp.toIso8601String(),
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
    socket = IO.io('http://192.168.220.33:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      print('Connected to server');
      currentUser = User(id: socket.id!, name: userName);
      socket.emit('join', currentUser.toJson());
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
      final message = data['message'] as String;

      _addMessage(
        from.id,
        Message(from.name, message, isMine: false),
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

  void sendPrivateMessage(User to, String message) {
    socket.emit('private_message', {
      'to': to.toJson(),
      'message': message,
      'from': currentUser.toJson(),
    });

    _addMessage(
      to.id,
      Message(currentUser.name, message, isMine: true),
      markUnread: false,
    );
  }

  void markMessagesRead(String userId) {
    unreadCountByUserId[userId] = 0;
    onMessagesUpdated?.call();
  }

  void dispose() {
    socket.dispose();
  }
}
