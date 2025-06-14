import 'dart:async';
import 'dart:developer'; // For log() function
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
  // bool _isSpeakerOn = true;
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
      print('[SocketDebug] Attempting to create PeerConnection...');
      await _createPeerConnection();
      print(
          '[SocketDebug] PeerConnection created. Setting up socket listeners...');
      _setupSocketListeners();
      print('[SocketDebug] Socket listeners setup complete.');

      await _getUserMedia(); // Capture media BEFORE offer/answer

      if (widget.isCaller) {
        final offer = await _peerConnection.createOffer();
        await _peerConnection.setLocalDescription(offer);
        widget.socketService.sendWebrtcOffer(widget.otherUser, {
          'sdp': offer.sdp,
          'type': offer.type,
        });
        print('[SocketDebug] Caller: Sent WebRTC Offer.');
      } else {
        print('[SocketDebug] Callee: Waiting for WebRTC Offer...');
      }

      _startCallTimer();
    } catch (e) {
      print('Error starting call: $e');
      _hangUp();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to make call: $e")));
      }
    }
  }

  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        // RE-ENABLE AND UPDATE WITH YOUR NEWEST TURN SERVER CREDENTIALS
        {
          'urls':
              'turn:relay1.expressturn.com:3480', // Example: 'turn:global.relay.metered.ca:80'
          'username': '000000002065267973',
          'credential': 'GKDX9jTiguQHTGYnHt464EGSJ8Y=',
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
      log('ICE Connection State Changed: $state', name: 'WebRTC Debug');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        setState(() => _isConnected = true);
        log('ICE Connection State: CONNECTED!', name: 'WebRTC Debug');
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        log('ICE Connection State: COMPLETED!', name: 'WebRTC Debug');
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        log('ICE Connection State: DISCONNECTED!', name: 'WebRTC Debug');
        _hangUp(endCallOnServer: false); // Re-enabled hangup
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        log('ICE Connection State: FAILED!', name: 'WebRTC Debug');
        _hangUp(endCallOnServer: false); // Re-enabled hangup
      } else {
        log('ICE Connection State: Other state: $state', name: 'WebRTC Debug');
      }
    };

    // --- ENHANCED ONTRACK LISTENER ---
    _peerConnection.onTrack = (event) async {
      log('[WebRTC] onTrack: kind = ${event.track.kind}, event.streams.length = ${event.streams.length}, Track ID: ${event.track.id}, Track Enabled: ${event.track.enabled}');

      if (event.streams.isNotEmpty) {
        MediaStream remoteStream = event.streams[0];
        print('[WebRTC Debug] onTrack: Remote Stream ID: ${remoteStream.id}');
        print(
            '[WebRTC Debug] onTrack: Remote Stream Video Tracks: ${remoteStream.getVideoTracks().length}');
        print(
            '[WebRTC Debug] onTrack: Remote Stream Audio Tracks: ${remoteStream.getAudioTracks().length}');

        if (event.track.kind == 'video') {
          setState(() {
            _remoteRenderer.srcObject = remoteStream;
          });
          log('[Renderer] Remote video stream set via onTrack. Stream ID: ${remoteStream.id}');
          // ADDED: Print Remote Renderer Texture ID
          print(
              '[WebRTC Debug] Remote Renderer Texture ID (onTrack): ${_remoteRenderer.textureId}');
          // ADDED: Force a UI rebuild after setting srcObject if mounted
          if (mounted) {
            setState(() {/* Rebuild UI */});
            print('[WebRTC Debug] Forced UI rebuild after remote video set.');
          }
        } else if (event.track.kind == 'audio') {
          log('[WebRTC Debug] Remote audio track received via onTrack. Track ID: ${event.track.id}. Enabled: ${event.track.enabled}');
        }

        if (_remoteStream == null || _remoteStream!.id != remoteStream.id) {
          _remoteStream = remoteStream;
          log('[WebRTC] _remoteStream updated to incoming remote stream: ${remoteStream.id}');
        }

        // Detailed check for all tracks in the remote stream
        remoteStream.getTracks().forEach((track) {
          print(
              '[WebRTC Debug] Remote Stream Track Detail: ${track.kind} - ${track.id}, Enabled: ${track.enabled}');
        });
      } else {
        log('[WebRTC] onTrack event received with no streams!');
      }
    };
    // --- END ENHANCED ONTRACK LISTENER ---

    // --- ENHANCED ONADDSTREAM LISTENER ---
    _peerConnection.onAddStream = (stream) {
      print(
          'DEBUG: onAddStream CALLED! Stream ID: ${stream.id}, Video Tracks: ${stream.getVideoTracks().length}, Audio Tracks: ${stream.getAudioTracks().length}');
      if (widget.isVideo && stream.getVideoTracks().isNotEmpty) {
        if (_remoteRenderer.srcObject != stream) {
          setState(() {
            _remoteRenderer.srcObject = stream;
            _remoteStream = stream;
          });
          log("DEBUG: remote video stream set via onAddStream");
        }
      } else if (stream.getAudioTracks().isNotEmpty) {
        log("DEBUG: remote audio stream received via onAddStream (no video)");
      }
      // Detailed check for all tracks in the stream
      stream.getTracks().forEach((track) {
        print(
            '[WebRTC Debug] Remote Stream (onAddStream) Track Detail: ${track.kind} - ${track.id}, Enabled: ${track.enabled}');
      });
      // ADDED: Print Remote Renderer Texture ID in onAddStream
      print(
          '[WebRTC Debug] Remote Renderer Texture ID (onAddStream): ${_remoteRenderer.textureId}');
      // ADDED: Force a UI rebuild after setting srcObject if mounted
      if (mounted) {
        setState(() {/* Rebuild UI */});
        print(
            '[WebRTC Debug] Forced UI rebuild after remote video set in onAddStream.');
      }
    };
    // --- END ENHANCED ONADDSTREAM LISTENER ---
  }

  // --- ENHANCED GETUSERMEDIA ---
  Future<void> _getUserMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo,
      });

      print('[WebRTC Debug] Local stream obtained. ID: ${_localStream?.id}');
      if (_localStream != null) {
        print(
            '[WebRTC Debug] Local stream video tracks count: ${_localStream!.getVideoTracks().length}');
        print(
            '[WebRTC Debug] Local stream audio tracks count: ${_localStream!.getAudioTracks().length}');

        _localStream!.getTracks().forEach((track) {
          _peerConnection.addTrack(track, _localStream!);
          print(
              '[WebRTC Debug] Added local track to peer connection: ${track.kind} - ${track.id}, Enabled: ${track.enabled}');
        });
      }

      _localRenderer.srcObject = _localStream;
      print('[WebRTC Debug] Local renderer srcObject set.');
      // ADDED: Print Local Renderer Texture ID
      print(
          '[WebRTC Debug] Local Renderer Texture ID: ${_localRenderer.textureId}');
    } catch (e) {
      print('Error getting user media: $e');
      rethrow;
    }
  }
  // --- END ENHANCED GETUSERMEDIA ---

  void _setupSocketListeners() {
    print(
        '[SocketDebug] Inside _setupSocketListeners. Registering onWebrtcOffer...');
    widget.socketService.onWebrtcOffer = ({required from, required sdp}) async {
      print('[SocketDebug] onWebrtcOffer CALLED! From: ${from.name}');
      if (from.id == widget.otherUser.id) {
        print('[WebRTC Debug] Received WebRTC Offer from ${from.name}');
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdp['type']),
        );
        print('[WebRTC Debug] Set Remote Description (Offer)');

        final answer = await _peerConnection.createAnswer();
        await _peerConnection.setLocalDescription(answer);

        print('[WebRTC Debug] Created and Set Local Description (Answer)');
        print('Full SDP Type: ${answer.type}');
        print('Full SDP Content (START):');
        answer.sdp!.split('\n').forEach((line) => print(line));
        print('Full SDP Content (END)');

        widget.socketService.sendWebrtcAnswer(widget.otherUser, {
          'sdp': answer.sdp,
          'type': answer.type,
        });
        print('[WebRTC Debug] Sent WebRTC Answer to ${widget.otherUser.name}');
      }
    };

    widget.socketService.onWebrtcAnswer =
        ({required from, required sdp}) async {
      print('[SocketDebug] onWebrtcAnswer CALLED! From: ${from.name}');
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
      print('[SocketDebug] onWebrtcIceCandidate CALLED! From: ${from.name}');
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

    widget.socketService.onCallAccepted = (data) {
      final User fromUser = data['from'];
      if (fromUser.id == widget.otherUser.id) {
        print('DEBUG: CallScreen received call_accepted from ${fromUser.name}');
      }
    };

    widget.socketService.onCallRejected = (data) {
      final User fromUser = data['from'];
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
      final User fromUser = data['from'];
      print('DEBUG: onCallEnded received. Data: $data');
      print(
          'DEBUG: From ID: ${fromUser.id}, Other User ID: ${widget.otherUser.id}');
      if (fromUser.id == widget.otherUser.id) {
        print(
            'DEBUG: onCallEnded match. Calling _hangUp(endCallOnServer: false)');
        _hangUp(endCallOnServer: false);
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
    // Dispose renderers and streams immediately upon hangup
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection.dispose();

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  void _toggleMute() {
    final audioTracks = _localStream?.getAudioTracks();
    if (audioTracks != null && audioTracks.isNotEmpty) {
      audioTracks.first.enabled = !_isMuted;
      setState(() => _isMuted = !_isMuted);
      print('[WebRTC Debug] Local audio muted: ${_isMuted}');
    }
  }

  void _toggleSpeaker() {
    // setState(() => _isSpeakerOn = !_isSpeakerOn); // Uncomment if you want the icon to change
    print(
        '[WebRTC Debug] Speaker toggle button pressed, but programmatic control is disabled.');
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
          // Remote Video Renderer
          Positioned.fill(
            // Always try to render remote if it's a video call and srcObject is present
            child: widget.isVideo && _remoteRenderer.srcObject != null
                ? Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.yellow, width: 5)),
                    child: RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  )
                : Container(
                    color: Colors.black, // Background when no remote video
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isConnected
                                ? (widget.isVideo
                                    ? "Connected: Remote video should be here"
                                    : "Connected: Audio Call")
                                : "Connecting...",
                            style: TextStyle(color: Colors.white, fontSize: 20),
                          ),
                          SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () {
                              print('--- Debug Renderers State ---');
                              print(
                                  'Local Renderer srcObject: ${_localRenderer.srcObject?.id}');
                              print(
                                  'Local Renderer Texture ID: ${_localRenderer.textureId}');
                              print(
                                  'Remote Renderer srcObject: ${_remoteRenderer.srcObject?.id}');
                              print(
                                  'Remote Renderer Texture ID: ${_remoteRenderer.textureId}');
                              print('--- End Debug Renderers State ---');
                              setState(() {});
                            },
                            child: Text('Debug Renderers'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          // Local Video Renderer (if video call)
          if (widget.isVideo)
            Positioned(
              right: 20,
              top: 40,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
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
                    icon: Icons.volume_up,
                    onPressed: _toggleSpeaker,
                    color: Colors.white),
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
