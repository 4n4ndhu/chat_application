import 'package:chat_application/socket_service.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final SocketService socketService;
  final User otherUser;

  ChatScreen({required this.socketService, required this.otherUser});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Message> messages = [];

  @override
  void initState() {
    super.initState();

    final rawList = widget.socketService.messagesByUserId[widget.otherUser.id];
    if (rawList != null) {
      messages.addAll(rawList);
    }

    widget.socketService.onMessagesUpdated = () {
      setState(() {
        messages.clear();
        final updatedList =
            widget.socketService.messagesByUserId[widget.otherUser.id];
        if (updatedList != null) {
          messages.addAll(updatedList);
        }
      });
    };
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add(
        Message(widget.socketService.currentUser.name, text, isMine: true),
      );
    });

    widget.socketService.sendPrivateMessage(widget.otherUser, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat with ${widget.otherUser.name}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (_, index) {
                final msg = messages[messages.length - 1 - index];
                return Align(
                  alignment:
                      msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: msg.isMine ? Colors.blue[200] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(msg.text),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(hintText: 'Type a message'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(icon: Icon(Icons.send), onPressed: _send),
              ],
            ),
          )
        ],
      ),
    );
  }
}
