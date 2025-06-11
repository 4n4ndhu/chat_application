import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final SocketService socketService;
  final User caller;
  final bool isVideoCall;

  const IncomingCallScreen({
    Key? key,
    required this.socketService,
    required this.caller,
    required this.isVideoCall,
  }) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Function(Map<String, dynamic>)? _callEndedListener;

  @override
  void initState() {
    super.initState();
    // Set up the listener for when the call ends (e.g., caller hangs up)
    _callEndedListener = (data) {
      // Ensure it's the specific caller who ended the call
      final User fromUser = data['from'];
      if (fromUser.id == widget.caller.id) {
        print('DEBUG: IncomingCallScreen received call_ended from caller');
        // Only pop if this screen is still active in the navigation stack
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
      }
    };
    widget.socketService.onCallEnded = _callEndedListener;

   
    widget.socketService.onCallRejected = (data) {
      final User fromUser = data['from'];
      if (fromUser.id == widget.caller.id) {
        print('DEBUG: IncomingCallScreen received call_rejected from caller');
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
      }
    };
  }

  @override
  void dispose() {
 
    if (widget.socketService.onCallEnded == _callEndedListener) {
      widget.socketService.onCallEnded = null;
    }
    // Also reset onCallRejected if needed
    if (widget.socketService.onCallRejected == _callEndedListener) {
      // Make sure this is distinct if you have different listeners
      widget.socketService.onCallRejected = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              child: Text(
                widget.caller.name[0].toUpperCase(),
                style: TextStyle(fontSize: 48),
              ),
            ),
            SizedBox(height: 20),
            Text(
              widget.caller.name,
              style: TextStyle(color: Colors.white, fontSize: 28),
            ),
            SizedBox(height: 10),
            Text(
              'Incoming ${widget.isVideoCall ? 'Video' : 'Voice'} Call',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.green,
                  heroTag: 'acceptCallButton',
                  child: Icon(Icons.call, color: Colors.white),
                  onPressed: () {
                    widget.socketService.acceptCall(widget.caller);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CallScreen(
                          socketService: widget.socketService,
                          isVideo: widget.isVideoCall,
                          otherUser: widget.caller,
                          isCaller: false,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(width: 40),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  heroTag: 'rejectCallButton',
                  child: Icon(Icons.call_end, color: Colors.white),
                  onPressed: () {
                    widget.socketService.rejectCall(widget.caller);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
