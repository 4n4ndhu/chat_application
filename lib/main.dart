import 'package:chat_application/chat_screen.dart';
import 'package:chat_application/socket_service.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final String myUserName =
      "User_${DateTime.now().millisecondsSinceEpoch % 1000}";

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-User Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: UserListScreen(myUserName: myUserName),
    );
  }
}

class UserListScreen extends StatefulWidget {
  final String myUserName;

  UserListScreen({required this.myUserName});

  @override
  _UserListScreenState createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  late SocketService socketService;

  @override
  void initState() {
    super.initState();
    socketService = SocketService();
    socketService.connect(widget.myUserName);
    socketService.onUserListUpdated = (List<User> users) {
      if (mounted) {
        setState(() {});
      }
    };
  }

  @override
  void dispose() {
    socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Online Users')),
      body: ListView.builder(
        itemCount: socketService.onlineUsers.length,
        itemBuilder: (context, index) {
          final user = socketService.onlineUsers[index];
          final unreadCount = socketService.unreadCountByUserId[user.id] ?? 0;

          return ListTile(
            title: Text(user.name),
            trailing: unreadCount > 0
                ? CircleAvatar(
                    radius: 12,
                    child: Text(unreadCount.toString()),
                  )
                : null,
            onTap: () {
              socketService.markMessagesRead(user.id);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    socketService: socketService,
                    otherUser: user,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
