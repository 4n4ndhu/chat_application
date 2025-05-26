import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:record/record.dart';
import 'socket_service.dart';

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

    final rawList = widget.socketService.messagesByUserId[widget.otherUser.id];
    if (rawList != null) {
      messages.addAll(rawList);
    }

    widget.socketService.onMessagesUpdated = () {
      if (mounted) {
        setState(() {
          messages.clear();
          final updatedList =
              widget.socketService.messagesByUserId[widget.otherUser.id];
          if (updatedList != null) {
            messages.addAll(updatedList);
          }
        });
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

  @override
  void dispose() {
    _controller.dispose();
    audioPlayer.dispose();
    audioRecorder.dispose();
    super.dispose();
  }

  void _sendTextMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.socketService.sendPrivateMessage(
      to: widget.otherUser,
      message: text,
    );
    _controller.clear();
  }

  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final tempDir = await Directory.systemTemp.createTemp();
        _recordingPath = '${tempDir.path}/recording.m4a';

        await audioRecorder.start(
          RecordConfig(),
          path: _recordingPath!,
        );

        setState(() {
          isRecording = true;
        });
      }
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await audioRecorder.stop();
      setState(() => isRecording = false);

      if (path != null) {
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
      }
    }
  }

  void _stopAudio() async {
    await audioPlayer.stop();
    if (mounted) {
      setState(() => currentPlayingId = null);
    }
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
                final prevmsg = index + 1 < messages.length
                    ? messages[messages.length - 1 - (index + 1)]
                    : null;
                final isSameSender =
                    prevmsg != null && msg.isMine == prevmsg.isMine;
                return Align(
                  alignment:
                      msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(
                        top: isSameSender ? 2 : 10,
                        left: msg.isMine ? 40 : 20,
                        right: msg.isMine ? 20 : 40),
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: msg.isMine ? Colors.green[200] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: msg.isAudio
                        ? _buildAudioMessage(msg)
                        : Text(msg.text ?? ''),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(isRecording ? Icons.stop : Icons.mic),
                  onPressed: isRecording ? _stopRecording : _startRecording,
                  color: isRecording ? Colors.red : null,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: 5,
                    minLines: 1,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20)),
                        hintText: 'Type a message'),
                    // onSubmitted: (_) => _sendTextMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _sendTextMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAudioMessage(Message message) {
    final isPlaying = currentPlayingId == message.id;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
          onPressed: () {
            if (isPlaying) {
              _stopAudio();
            } else if (message.audioBase64 != null) {
              _playAudio(message.audioBase64!, message.id);
            }
          },
        ),
        Text('Voice message'),
        SizedBox(width: 8),
        Text(
          '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
