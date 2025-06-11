import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:chat_application/incoming_call_screen.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:record/record.dart';
import 'socket_service.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final SocketService socketService;
  final User otherUser;

  const ChatScreen({
    Key? key,
    required this.socketService,
    required this.otherUser,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer audioPlayer = AudioPlayer();
  late final AudioRecorder audioRecorder;
  bool isRecording = false;
  String? currentPlayingId;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    audioRecorder = AudioRecorder();
    _initAudioSession();
    _loadMessages();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    audioPlayer.dispose();
    audioRecorder.dispose();
    super.dispose();
  }

  void _loadMessages() {
    final messages = widget.socketService.messagesByUserId[widget.otherUser.id];
    if (messages != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _setupSocketListeners() {
    widget.socketService.onMessagesUpdated = () {
      if (mounted) setState(() {});
      _scrollToBottom();
    };

    widget.socketService.onNewMessage = (userId) {
      if (userId == widget.otherUser.id && mounted) {
        _scrollToBottom();
      }
    };

    widget.socketService.onIncomingCall = (data) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => IncomingCallScreen(
              socketService: widget.socketService,
              caller: User.fromJson(data['from']),
              isVideoCall: data['isVideo'],
            ),
          ),
        );
      }
    };
  }

  Future<void> _initAudioSession() async {
    final session = await audio_session.AudioSession.instance;
    await session.configure(audio_session.AudioSessionConfiguration(
      avAudioSessionCategory:
          audio_session.AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          audio_session.AVAudioSessionCategoryOptions.allowBluetooth |
              audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: audio_session.AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: const audio_session.AndroidAudioAttributes(
        contentType: audio_session.AndroidAudioContentType.speech,
        flags: audio_session.AndroidAudioFlags.none,
        usage: audio_session.AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendTextMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.socketService.sendPrivateMessage(
      to: widget.otherUser,
      message: text,
    );
    _controller.clear();
    _scrollToBottom();
  }

  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final tempDir = await Directory.systemTemp.createTemp();
        _recordingPath =
            '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await audioRecorder.start(
          RecordConfig(encoder: AudioEncoder.aacLc),
          path: _recordingPath!,
        );

        setState(() => isRecording = true);
      }
    } catch (e) {
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await audioRecorder.stop();
      setState(() => isRecording = false);

      if (path != null && mounted) {
        final audioFile = File(path);
        final audioBytes = await audioFile.readAsBytes();
        final audioBase64 = base64Encode(audioBytes);

        widget.socketService.sendPrivateMessage(
          to: widget.otherUser,
          audioBase64: audioBase64,
        );

        await audioFile.delete();
      }
    } catch (e) {
      print('Error stopping recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send recording: $e')),
        );
      }
    }
  }

  Future<void> _playAudio(String audioBase64, String messageId) async {
    try {
      setState(() => currentPlayingId = messageId);
      await audioPlayer.stop();
      await audioPlayer.play(BytesSource(base64Decode(audioBase64)));
      audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => currentPlayingId = null);
        }
      });
    } catch (e) {
      print('Error playing audio: $e');
      if (mounted) {
        setState(() => currentPlayingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play audio: $e')),
        );
      }
    }
  }

  void _stopAudio() async {
    await audioPlayer.stop();
    if (mounted) {
      setState(() => currentPlayingId = null);
    }
  }

  void _makeVoiceCall() {
    widget.socketService.initiateCall(widget.otherUser, false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          socketService: widget.socketService,
          isVideo: false,
          otherUser: widget.otherUser,
          isCaller: true,
        ),
      ),
    );
  }

  void _makeVideoCall() {
    widget.socketService.initiateCall(widget.otherUser, true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          socketService: widget.socketService,
          isVideo: true,
          otherUser: widget.otherUser,
          isCaller: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages =
        widget.socketService.messagesByUserId[widget.otherUser.id] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUser.name),
        actions: [
          IconButton(
            icon: Icon(Icons.call),
            onPressed: _makeVoiceCall,
          ),
          IconButton(
            icon: Icon(Icons.videocam),
            onPressed: _makeVideoCall,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isMe = message.isMine;
    final isAudio = message.isAudio;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isMe ? 16 : 0),
            topRight: Radius.circular(isMe ? 0 : 16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.senderName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            SizedBox(height: 4),
            isAudio
                ? _buildAudioMessage(message)
                : Text(
                    message.text ?? '',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
            SizedBox(height: 4),
            Text(
              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioMessage(Message message) {
    final isPlaying = currentPlayingId == message.id;
    final isMe = message.isMine;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
          color: isMe ? Colors.white : Colors.blue,
          onPressed: () {
            if (isPlaying) {
              _stopAudio();
            } else if (message.audioBase64 != null) {
              _playAudio(message.audioBase64!, message.id);
            }
          },
        ),
        Text(
          'Voice message',
          style: TextStyle(color: isMe ? Colors.white : Colors.black87),
        ),
      ],
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(isRecording ? Icons.stop : Icons.mic),
            color: isRecording ? Colors.red : null,
            onPressed: isRecording ? _stopRecording : _startRecording,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
              onSubmitted: (_) => _sendTextMessage(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _sendTextMessage,
          ),
        ],
      ),
    );
  }
}
