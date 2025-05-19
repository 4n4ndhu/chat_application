// import 'package:chat_application/chat_screen.dart';
// import 'package:chat_application/socket_service.dart';
// import 'package:flutter/material.dart';

// class UserListScreen extends StatefulWidget {
//   final String myUserName;
//   UserListScreen({required this.myUserName});

//   @override
//   _UserListScreenState createState() => _UserListScreenState();
// }

// class _UserListScreenState extends State<UserListScreen> {
//   late SocketService socketService;
//   List<User> onlineUsers = [];

//   @override
//   void initState() {
//     super.initState();
//     socketService = SocketService();

//     socketService.onUserListUpdated = (users) {
//       setState(() {
//         onlineUsers =
//             users.where((u) => u.id != socketService.currentUser.id).toList();
//       });
//     };

//     socketService.connect(widget.myUserName);
//   }

//   @override
//   void dispose() {
//     socketService.dispose();
//     super.dispose();
//   }

//   void openChat(User user) {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) =>
//             ChatScreen(socketService: socketService, otherUser: user),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('Online Users')),
//       body: ListView.builder(
//         itemCount: onlineUsers.length,
//         itemBuilder: (_, index) {
//           final user = onlineUsers[index];
//           return ListTile(
//             title: Text(user.name),
//             trailing: socketService.unreadCountByUserId[user.id] != null
//                 ? CircleAvatar(
//                     radius: 10,
//                     backgroundColor: Colors.red,
//                     child: Text(
//                       '${socketService.unreadCountByUserId[user.id]}',
//                       style: TextStyle(color: Colors.white, fontSize: 12),
//                     ),
//                   )
//                 : null,
//             onTap: () async {
//               setState(() {
//                 socketService.unreadCountByUserId[user.id] = 0;
//               });
//               openChat(user);
//             },
//           );
//         },
//       ),
//     );
//   }
// }
