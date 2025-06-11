import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';

class User {
  final String id;
  final String name;

  User({required this.id, required this.name});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
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
  Function(String)? onNewMessage;
  Function()? onMessagesUpdated;

  // Call related events
  Function(Map<String, dynamic>)? onIncomingCall;
  Function(Map<String, dynamic>)? onCallAccepted;
  Function(Map<String, dynamic>)? onCallRejected;
  Function(Map<String, dynamic>)? onCallEnded;
  Function({required User from, required Map<String, dynamic> sdp})?
      onWebrtcOffer;
  Function({required User from, required Map<String, dynamic> sdp})?
      onWebrtcAnswer;
  Function({required User from, required Map<String, dynamic> candidate})?
      onWebrtcIceCandidate;

  final Uuid _uuid = const Uuid();
  String serverUrl = "http://192.168.220.34:3000";

  void connect(
    String userName,
  ) {
    try {
      socket = IO.io(
        serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .setQuery({'username': userName})
            .disableForceNew()
            .build(),
      );

      socket.onConnect((_) {
        final socketId = socket.id;
        if (socketId != null) {
          currentUser = User(id: socketId, name: userName);
          socket.emit('join', currentUser.toJson());
        }
      });

      socket.on('user_list', (data) {
        try {
          final users = (data as List)
              .map((u) => User.fromJson(u))
              .where((u) => u.id != currentUser.id)
              .toList();
          onlineUsers = users;
          onUserListUpdated?.call(users);
        } catch (e) {
          print('Error processing user_list: $e');
        }
      });

      socket.on('private_message', (data) {
        try {
          final from = User.fromJson(data['from']);
          final message = data['message'] as String?;
          final audioBase64 = data['audioBase64'] as String?;
          final messageId = data['id'] as String? ?? _uuid.v4();

          _addMessage(
            from.id,
            Message(
              senderName: from.name,
              text: message,
              audioBase64: audioBase64,
              isMine: false,
              id: messageId,
            ),
            markUnread: true,
          );
          onNewMessage?.call(from.id);
        } catch (e) {
          print('Error processing private_message: $e');
        }
      });

      // Call related events
      socket.on('incoming_call', (data) {
        onIncomingCall?.call(data);
        // if (onIncomingCall != null) {
        //   onIncomingCall!(data);
        // }
      });

      socket.on('call_accepted', (data) {
        if (onCallAccepted != null) {
          // onCallAccepted!(data);
          onCallAccepted!({
            'from': User.fromJson(data['from']),
            // 'isVideo': data['isVideo']
          });
        }
      });

      socket.on('call_rejected', (data) {
        if (onCallRejected != null) {
          // onCallRejected!(data);
          onCallRejected!({'from': User.fromJson(data['from'])});
        }
      });

      socket.on('call_ended', (data) {
        if (onCallEnded != null) {
          // onCallEnded!(data);
          onCallEnded!({'from': User.fromJson(data['from'])});
        }
      });

      socket.on('webrtc_offer', (data) {
        // onWebrtcOffer?.call(data);
        if (onWebrtcOffer != null) {
          onWebrtcOffer!(from: User.fromJson(data['from']), sdp: data['sdp']);
        }
      });

      socket.on('webrtc_answer', (data) {
        // onWebrtcAnswer?.call(data);
        if (onWebrtcAnswer != null) {
          onWebrtcAnswer!(from: User.fromJson(data['from']), sdp: data['sdp']);
        }
      });

      socket.on('webrtc_ice_candidate', (data) {
        // onWebrtcIceCandidate?.call(data);
        if (onWebrtcIceCandidate != null) {
          onWebrtcIceCandidate!(
              from: User.fromJson(data['from']), candidate: data['candidate']);
        }
      });

      socket.onDisconnect((_) {
        print('Disconnected from server');
      });

      socket.onError((error) {
        print('Socket error: $error');
      });
    } catch (e) {
      print('Error initializing socket: $e');
    }
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
    try {
      final messageId = _uuid.v4();
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
    } catch (e) {
      print('Error sending private message: $e');
    }
  }

  void markMessagesRead(String userId) {
    unreadCountByUserId[userId] = 0;
    onMessagesUpdated?.call();
  }

  Map<String, dynamic> _userToJson(User user) {
    return user.toJson();
  }

  // Call signaling helpers
  // void initiateCall(User to, bool isVideo) {
  //   socket.emit('call_initiate', {
  //     'to': to.toJson(),
  //     'from': currentUser.toJson(),
  //     'isVideo': isVideo,
  //   });
  // }
  void initiateCall(User toUser, bool isVideo) {
    socket.emit('call_initiate', {
      'to': _userToJson(toUser),
      'from': _userToJson(currentUser!),
      'isVideo': isVideo
    });
  }

  // void acceptCall(User to) {
  //   socket.emit('call_accept', {
  //     'to': to.toJson(),
  //     'from': currentUser.toJson(),
  //   });
  // }
  void acceptCall(User toUser) {
    socket.emit('call_accept',
        {'to': _userToJson(toUser), 'from': _userToJson(currentUser!)});
  }

  // void rejectCall(User to) {
  //   socket.emit('call_reject', {
  //     'to': to.toJson(),
  //     'from': currentUser.toJson(),
  //   });
  // }
  void rejectCall(User toUser) {
    socket.emit('call_reject',
        {'to': _userToJson(toUser), 'from': _userToJson(currentUser!)});
  }

  // void endCall(User to) {
  //   socket.emit('call_end', {
  //     'to': to.toJson(),
  //     'from': currentUser.toJson(),
  //   });
  // }
  void endCall(User toUser) {
    socket.emit('call_end',
        {'to': _userToJson(toUser), 'from': _userToJson(currentUser!)});
  }

  // void sendWebrtcOffer(User to, Map<String, dynamic> sdp) {
  //   socket.emit('webrtc_offer', {
  //     'to': to.toJson(),
  //     'sdp': sdp,
  //   });
  // }

  void sendWebrtcOffer(User toUser, Map<String, dynamic> sdp) {
    socket.emit('webrtc_offer', {'to': _userToJson(toUser), 'sdp': sdp});
  }

  // void sendWebrtcAnswer(User to, Map<String, dynamic> sdp) {
  //   socket.emit('webrtc_answer', {
  //     'to': to.toJson(),
  //     'sdp': sdp,
  //   });
  // }

  void sendWebrtcAnswer(User toUser, Map<String, dynamic> sdp) {
    socket.emit('webrtc_answer', {'to': _userToJson(toUser), 'sdp': sdp});
  }

  // void sendIceCandidate(User to, Map<String, dynamic> candidate) {
  //   socket.emit('webrtc_ice_candidate', {
  //     'to': to.toJson(),
  //     'candidate': candidate,
  //   });
  // }
  void sendIceCandidate(User toUser, Map<String, dynamic> candidate) {
    socket.emit('webrtc_ice_candidate',
        {'to': _userToJson(toUser), 'candidate': candidate});
  }

  void dispose() {
    socket.disconnect();
    socket.dispose();
  }
}
