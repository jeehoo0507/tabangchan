import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

String get _base => Uri.base.origin;

const allRoomIds = [
  "201","202","203","204","205","206","207","208","209","210",
  "211","212","213","214","215","세탁실",
  "216","217","218","219","220","221","222","223","224","225","226","227",
];

void main() => runApp(const TabangChanApp());

class TabangChanApp extends StatelessWidget {
  const TabangChanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '타방찬',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0.5,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  String? myRoom;
  String? currentPosition;

  Map<String, int> roomOccupancy = {};
  List<dynamic> requests = [];
  List<dynamic> messages = [];
  int _lastMessageCount = 0;

  Timer? _pollTimer;
  final _loginController = TextEditingController();
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();

  @override
  void dispose() {
    _pollTimer?.cancel();
    _loginController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final res = await http.get(Uri.parse('$_base/api/state'));
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(utf8.decode(res.bodyBytes));

      // 승인된 타방 감지
      final myApproved = (data['requests'] as List)
          .where((r) => r['from_room'] == myRoom && r['status'] == 'approved')
          .toList();
      if (myApproved.isNotEmpty) {
        final approved = myApproved.first;
        final approvedTo = approved['to_room'] as String;
        if (currentPosition != approvedTo) {
          await http.post(
            Uri.parse('$_base/api/delete_request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id': approved['id']}),
          );
          if (mounted) {
            setState(() => currentPosition = approvedTo);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$approvedTo호 타방이 승인되었습니다!')),
            );
          }
        }
      }

      final newMessages = data['messages'] as List;
      final newCount = newMessages.length;

      setState(() {
        roomOccupancy = (data['rooms'] as Map).map(
          (k, v) => MapEntry(k as String, (v['occupancy'] as num).toInt()),
        );
        requests = data['requests'] as List;
        messages = newMessages;
      });

      // 새 메시지가 왔을 때만 스크롤
      if (newCount > _lastMessageCount) {
        _lastMessageCount = newCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _post(String path, Map body) async {
    try {
      await http.post(
        Uri.parse('$_base$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      await _poll();
    } catch (_) {}
  }

  void _handleLogin() {
    final input = _loginController.text.trim();
    if (allRoomIds.contains(input) && input != '세탁실') {
      setState(() {
        myRoom = input;
        currentPosition = input;
      });
      _startPolling();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('존재하지 않는 호수입니다.')),
      );
    }
  }

  Future<void> _sendTabangRequest(String targetRoom) async {
    // 이미 다른 방 방문 중이면 차단
    if (currentPosition != myRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('현재 $currentPosition호 방문 중입니다. 먼저 내 방으로 복귀해주세요.')),
      );
      return;
    }
    // 이미 신청 중이면 차단
    final hasPending = requests.any((r) => r['from_room'] == currentPosition && r['status'] == 'pending');
    if (hasPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 신청 중인 타방이 있습니다.')),
      );
      return;
    }

    // 이름 + 사유 입력 다이얼로그
    final nameCtrl   = TextEditingController();
    final reasonCtrl = TextEditingController();
    final confirmed  = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$targetRoom호에 타방 신청'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: '이름',
                hintText: '예: 홍길동',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: '방문 사유 (선택)',
                hintText: '예: 과제 같이 하러요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
            child: const Text('신청하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _post('/api/request', {
      'from': currentPosition,   // 현재 위치 기준
      'to': targetRoom,
      'name': nameCtrl.text.trim(),
      'reason': reasonCtrl.text.trim(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$targetRoom호에 타방 신청을 보냈습니다.')),
    );
  }

  Future<void> _approveRequest(int id, String fromRoom) async {
    await _post('/api/approve', {'id': id});
  }

  Future<void> _rejectRequest(int id) async {
    await _post('/api/reject', {'id': id});
  }

  Future<void> _returnToMyRoom() async {
    if (currentPosition == myRoom) return;
    await _post('/api/return', {'from': currentPosition, 'to': myRoom});
    setState(() => currentPosition = myRoom);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('내 방으로 복귀했습니다.')),
    );
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    await _post('/api/chat', {'room': myRoom, 'msg': text});
  }

  @override
  Widget build(BuildContext context) {
    if (myRoom == null) return _buildLoginScreen();

    return Scaffold(
      appBar: AppBar(title: const Text('타방찬')),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildMapPage(),
          _buildTabangAndChatPage(),
          _buildSettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: '배치도'),
          BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), label: '타방/톡'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '설정'),
        ],
      ),
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('타방찬', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(
              controller: _loginController,
              decoration: InputDecoration(
                hintText: '호수 입력 (예: 227)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('시작하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          if (currentPosition != myRoom)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('현재 위치: $currentPosition호', style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _returnToMyRoom,
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('복귀하기'),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ["206","207","208","209","210"].map((id) => _roomTile(id, width: 60)).toList(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: ["205","204","203","202","201"].map((id) => _roomTile(id)).toList()),
              Container(
                width: 180, height: 260, margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text('중앙 정원', style: TextStyle(color: Colors.black12))),
              ),
              Column(children: ["211","212","213","214","215","세탁실"].map((id) => _roomTile(id)).toList()),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(children: ["222","223","224","225","226","227"].map((id) => _roomTile(id)).toList()),
              Container(width: 40, height: 310, alignment: Alignment.center, child: const VerticalDivider(thickness: 1.5, color: Colors.orangeAccent)),
              Column(children: ["216","217","218","219","220","221"].map((id) => _roomTile(id)).toList()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomTile(String id, {double width = 75}) {
    final count = roomOccupancy[id] ?? 0;
    final isOver = count >= 5;
    final isCurrentPos = id == currentPosition;
    final isMyHome = id == myRoom;

    return GestureDetector(
      onTap: () {
        if (isCurrentPos || id == '세탁실' || isOver) return;
        _sendTabangRequest(id);
      },
      child: Container(
        width: width, height: 50, margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isCurrentPos ? Colors.black : (isOver ? Colors.red[50] : Colors.white),
          border: Border.all(
            color: isMyHome ? Colors.blue : (isOver ? Colors.red : Colors.grey[300]!),
            width: isMyHome ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(id, style: TextStyle(fontSize: 12, color: isCurrentPos ? Colors.white : Colors.black, fontWeight: isCurrentPos ? FontWeight.bold : FontWeight.normal)),
            Text('$count명', style: TextStyle(fontSize: 10, color: isCurrentPos ? Colors.white70 : Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildTabangAndChatPage() {
    final incoming = requests.where((r) => r['to_room'] == myRoom && r['status'] == 'pending').toList();
    final myOutgoing = requests.where((r) => r['from_room'] == myRoom && r['status'] == 'pending').toList();

    return Column(
      children: [
        // 내가 보낸 신청 + 복귀 버튼
        if (myOutgoing.isNotEmpty || currentPosition != myRoom)
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                // 내가 보낸 신청 취소
                if (myOutgoing.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.send, color: Colors.orange),
                    title: Text('${myOutgoing.first['to_room']}호에 타방 신청 중',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('상대방 승인 대기 중'),
                    trailing: FilledButton.tonal(
                      onPressed: () => _rejectRequest(myOutgoing.first['id'] as int),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red[50]),
                      child: const Text('신청 취소', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                // 내 방으로 복귀
                if (currentPosition != myRoom) ...[
                  if (myOutgoing.isNotEmpty) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on, color: Colors.blue),
                    title: Text('현재 $currentPosition호에 있음',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('내 방: $myRoom호'),
                    trailing: FilledButton.tonal(
                      onPressed: _returnToMyRoom,
                      child: const Text('내 방 복귀'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        // 상단: 내 방으로 온 신청 목록
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('내 방으로 온 신청', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                child: incoming.isEmpty
                    ? const Center(child: Text('신청이 없습니다.'))
                    : ListView.builder(
                        itemCount: incoming.length,
                        itemBuilder: (context, i) {
                          final req      = incoming[i];
                          final fromRoom = req['from_room'] as String;
                          final name     = req['name'] as String? ?? '';
                          final reason   = req['reason'] as String? ?? '';
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.person, size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text('$fromRoom호 · $name',
                                          style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  if (reason.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(reason, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _rejectRequest(req['id'] as int),
                                        child: const Text('거절'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => _approveRequest(req['id'] as int, fromRoom),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                                        child: const Text('승인'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const Divider(thickness: 8, color: Color(0xFFF5F5F5)),
        // 하단: 전체 채팅
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('기숙사 전체 톡', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('아직 메시지가 없습니다.'))
                    : ListView.builder(
                        controller: _chatScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final msg = messages[i];
                          final isMine = msg['room'] == myRoom;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.black, fontSize: 14),
                                children: [
                                  TextSpan(
                                    text: '[${msg['room']}] ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isMine ? Colors.blue : Colors.black87,
                                    ),
                                  ),
                                  TextSpan(text: msg['msg'] as String),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: InputDecoration(
                          hintText: '메시지를 입력하세요...',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send_rounded, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return Column(
      children: [
        const SizedBox(height: 20),
        ListTile(leading: const Icon(Icons.home), title: const Text('내 소속'), trailing: Text('$myRoom호')),
        ListTile(leading: const Icon(Icons.location_on), title: const Text('현재 위치'), trailing: Text('$currentPosition호')),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          onTap: () {
            _pollTimer?.cancel();
            setState(() {
              myRoom = null;
              currentPosition = null;
              messages = [];
              requests = [];
              _lastMessageCount = 0;
            });
          },
        ),
      ],
    );
  }
}
