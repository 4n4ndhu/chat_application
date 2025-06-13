import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

class CallScreen extends StatefulWidget {
  final SocketService socketService;
  final bool isVideo;
  final User otherUser;
  final bool isCaller;

  const CallScreen({
    Key? key,
    required this.socketService,
    required this.isVideo,
    required this.otherUser,
    required this.isCaller,
  }) : super(key: key);

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  late RTCPeerConnection _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  Timer? _callDurationTimer;
  Duration _callDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startCall();
  }

  @override
  void dispose() {
    _callDurationTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();

    _remoteStream?.dispose();
    _peerConnection.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    try {
      await _createPeerConnection();
      _setupSocketListeners();

      await _getUserMedia();

      if (widget.isCaller) {
        final offer = await _peerConnection.createOffer();
        await _peerConnection.setLocalDescription(offer);
        widget.socketService.sendWebrtcOffer(widget.otherUser, {
          'sdp': offer.sdp,
          'type': offer.type,
        });
      }

      // _setupSocketListeners();
      _startCallTimer();
    } catch (e) {
      print('Error starting call: $e');
      _hangUp();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("failed to make call")));
      }
    }
  }

  Future<void> _createPeerConnection() async {
    const String EXPRESS_TURN_SERVER_ADDRESS = 'relay1.expressturn.com';
    const int EXPRESS_TURN_PORT = 3480; // This is the port provided in your URL
    const String EXPRESS_TURN_USERNAME = '000000002064816645';
    const String EXPRESS_TURN_PASSWORD = '8onVM/nOnKT+gRs4Yh1N434S3Ao=';
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {
          'urls': 'turn:$EXPRESS_TURN_SERVER_ADDRESS:$EXPRESS_TURN_PORT',
          'username': EXPRESS_TURN_USERNAME,
          'credential': EXPRESS_TURN_PASSWORD,
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection.onIceCandidate = (candidate) {
      print('DEBUG: Local ICE candidate generated: ${candidate.toMap()}');
      if (candidate != null) {
        widget.socketService.sendIceCandidate(widget.otherUser, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        setState(() => _isConnected = true);
      } else if (state ==
              RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _hangUp(endCallOnServer: false);
      }
    };

    _peerConnection.onTrack = (event) async {
      print('[WebRTC] onTrack: kind = ${event.track.kind}');

      if (_remoteStream == null) {
        _remoteStream = await createLocalMediaStream('remote');
        _remoteStream?.addTrack(event.track);

        setState(() {
          _remoteRenderer.srcObject = _remoteStream;
        });

        print(
            '[Renderer] Remote stream set. Tracks: ${_remoteStream?.getVideoTracks().length} video, ${_remoteStream?.getAudioTracks().length} audio');
      } else {
        _remoteStream?.addTrack(event.track);
      }

      print('[WebRTC] ✅ Track added to remote stream');
    };

    _peerConnection.onAddStream = (Stream) {
      if (widget.isVideo && Stream.getAudioTracks().isNotEmpty) {
        if (_remoteRenderer.srcObject != Stream) {
          setState(() {
            _remoteRenderer.srcObject = Stream;
            _remoteStream = Stream;
          });
        } else if (Stream.getAudioTracks().isNotEmpty) {
          print("DEBUG: remote audio stream recived via onAddStream");
        }
      }
    };
  }

  Future<void> _getUserMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo,
      });

      _localStream?.getTracks().forEach((track) {
        _peerConnection.addTrack(track, _localStream!);
      });

      _localRenderer.srcObject = _localStream;
    } catch (e) {
      print('Error getting user media: $e');
      throw e;
    }
  }

  void _setupSocketListeners() {
    widget.socketService.onWebrtcOffer = ({required from, required sdp}) async {
      if (from.id == widget.otherUser.id) {
        print('[WebRTC Debug] Received WebRTC Offer from ${from.name}');
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdp['type']),
        );
        print('[WebRTC Debug] Set Remote Description (Offer)');

        final answer = await _peerConnection.createAnswer();
        await _peerConnection.setLocalDescription(answer);
        print('[WebRTC Debug] Created and Set Local Description (Answer)');
        widget.socketService.sendWebrtcAnswer(widget.otherUser, {
          'sdp': answer.sdp,
          'type': answer.type,
        });
        print('[WebRTC Debug] Sent WebRTC Answer to ${widget.otherUser.name}');
      }
    };

    widget.socketService.onWebrtcAnswer =
        ({required from, required sdp}) async {
      if (from.id == widget.otherUser.id) {
        print('[WebRTC Debug] Received WebRTC Answer from ${from.name}');
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdp['type']),
        );
        print('[WebRTC Debug] Set Remote Description (Answer)');
      }
    };

    widget.socketService.onWebrtcIceCandidate =
        ({required from, required candidate}) async {
      if (from.id == widget.otherUser.id) {
        print(
            '[WebRTC Debug] Received ICE Candidate from ${from.name}: ${candidate['candidate']}');
        await _peerConnection.addCandidate(
          RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ),
        );
        print('[WebRTC Debug] Added ICE Candidate');
      }
    };

    // widget.socketService.onCallEnded = (data) {
    //   if (data['from'].id == widget.otherUser.id) {
    //     _hangUp();
    //   }
    // };

    widget.socketService.onCallAccepted = (data) {
      final User fromUser = data['from'];
      if (fromUser.id == widget.otherUser.id) {
        print('DEBUG: CallScreen received call_accepted from ${fromUser.name}');
        // No need to navigate here, as the caller is already in CallScreen
        // and the connection process will start via WebRTC signaling.
      }
    };

    widget.socketService.onCallRejected = (data) {
      final User fromUser = data[
          'from']; // Now 'from' is already a User object from SocketService
      if (fromUser.id == widget.otherUser.id) {
        print('DEBUG: Call rejected by ${fromUser.name}');
        if (mounted) {
          _hangUp(endCallOnServer: false);
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${fromUser.name} rejected the call.")));
        }
      }
    };

    widget.socketService.onCallEnded = (data) {
      final User fromUser = data[
          'from']; // Now 'from' is already a User object from SocketService
      print('DEBUG: onCallEnded received. Data: $data');
      print(
          'DEBUG: From ID: ${fromUser.id}, Other User ID: ${widget.otherUser.id}');
      if (fromUser.id == widget.otherUser.id) {
        print(
            'DEBUG: onCallEnded match. Calling _hangUp(endCallOnServer: false)');
        _hangUp(
            endCallOnServer:
                false); // Call hangUp without re-emitting to server
      } else {
        print('DEBUG: onCallEnded mismatch or irrelevant sender.');
      }
    };
  }

  void _startCallTimer() {
    _callDurationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration = Duration(seconds: _callDuration.inSeconds + 1);
      });
    });
  }

  void _hangUp({bool endCallOnServer = true}) {
    if (endCallOnServer) {
      widget.socketService.endCall(widget.otherUser);
    }
    _callDurationTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  void _toggleMute() {
    final audioTracks = _localStream?.getAudioTracks();
    if (audioTracks != null && audioTracks.isNotEmpty) {
      audioTracks.first.enabled = !_isMuted;
      setState(() => _isMuted = !_isMuted);
    }
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [minutes, seconds].join(':');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
              child: widget.isVideo &&
                      _remoteStream != null &&
                      _remoteStream!.getVideoTracks().isNotEmpty &&
                      _remoteRenderer.srcObject != null
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: Colors.black,
                      child: Center(
                        child: Text(
                          _isConnected
                              ? "connected: no video"
                              : "connecting....",
                          style: TextStyle(color: Colors.white, fontSize: 20),
                        ),
                      ),
                    )),
          if (widget.isVideo)
            Positioned(
              right: 20,
              top: 40,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                ),
                child: RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  widget.otherUser.name,
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
                Text(
                  _isConnected
                      ? _formatDuration(_callDuration)
                      : 'Connecting...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCallControlButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  onPressed: _toggleMute,
                  color: _isMuted ? Colors.red : Colors.white,
                ),
                _buildCallControlButton(
                  icon: Icons.call_end,
                  onPressed: _hangUp,
                  color: Colors.red,
                  size: 32,
                ),
                _buildCallControlButton(
                  icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                  onPressed: _toggleSpeaker,
                  color: _isSpeakerOn ? Colors.white : Colors.grey,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    double size = 24,
  }) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: Colors.black.withOpacity(0.4),
      child: IconButton(
        icon: Icon(icon, size: size, color: color),
        onPressed: onPressed,
      ),
    );
  }
}
