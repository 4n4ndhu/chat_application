import 'package:chat_application/home_screen.dart';
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
      home: UserListScreen(myUserName: myUserName),
    );
  }
}
