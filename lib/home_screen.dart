import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'main.dart'; // colors + BrandLogo
import 'data_service.dart';
import 'models.dart';
import 'new_split_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  // Live data from Firestore (a new user starts with nothing).
  List<Friend> friends = [];
  List<SplitRecord> records = [];
  final Set<String> selected = {};
  bool friendsLoaded = false;
  bool splitsLoaded = false;
  String? loadError;
  StreamSubscription<List<Friend>>? _friendsSub;
  StreamSubscription<List<SplitRecord>>? _splitsSub;

  @override
  void initState() {
    super.initState();
    _friendsSub = DataService.friendsStream().listen((list) {
      if (!mounted) return;
      setState(() {
        friends = list;
        friendsLoaded = true;
        loadError = null;
        selected.removeWhere((n) => !list.any((f) => f.name == n));
      });
    }, onError: _onLoadError);

    _splitsSub = DataService.splitsStream().listen((list) {
      if (!mounted) return;
      setState(() {
        records = list;
        splitsLoaded = true;
        loadError = null;
      });
    }, onError: _onLoadError);
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _splitsSub?.cancel();
    super.dispose();
  }

  void _onLoadError(Object e) {
    if (!mounted) return;
    setState(() {
      friendsLoaded = true;
      splitsLoaded = true;
      loadError =
          'We couldn’t load your data. Check your connection and '
          'your Firestore rules.';
    });
  }

  /// Runs a Firestore write without blocking the UI (works offline too).
  void _run(Future<void> Function() action) {
    action().catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t save that. Please try again.')),
      );
    });
  }

  // ---------- USER ----------
  String get _firstName {
    final n = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    return n.isNotEmpty ? n.split(' ').first : 'You';
  }

  // ---------- ACTIONS ----------
  Future<void> _openNewSplit({
    List<String> pre = const [],
    SplitRecord? editing,
  }) async {
    final result = await Navigator.push<SplitRecord>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewSplitScreen(
          myName: _firstName,
          friends: friends.map((f) => f.name).toList(),
          preselected: pre,
          editing: editing,
        ),
      ),
    );
    if (result != null) {
      setState(() => selected.clear());
      _run(() => DataService.saveSplit(result));
    }
  }

  /// Opens a saved split: paid toggles, edit, delete.
  void _viewSplit(SplitRecord r) {
    final id = r.id;
    showBreakdownSheet(
      context,
      r,
      myName: _firstName,
      onPaidChanged: id == null
          ? null
          : (paid) => _run(() => DataService.setPaid(id, paid)),
      onEdit: (current) => _openNewSplit(editing: current),
      onDelete: id == null
          ? null
          : () => _run(() => DataService.deleteSplit(id)),
    );
  }

  Future<void> _confirmDeleteFriend(String name) async {
    final i = friends.indexWhere((f) => f.name == name);
    if (i < 0) return;
    final friend = friends[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Remove $name?',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: const Text('Your past splits with them stay as they are.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) _run(() => DataService.deleteFriend(friend.id));
  }

  Future<void> _addFriendDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Add a friend',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: "Friend's name"),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final n = name?.trim() ?? '';
    if (n.isEmpty) return;
    if (friends.any((f) => f.name.toLowerCase() == n.toLowerCase())) return;
    _run(() => DataService.addFriend(n));
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: IndexedStack(
          index: tab,
          children: [_homeTab(), _historyTab(), _profileTab()],
        ),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _homeTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Row(
          children: [
            const BrandLogo(),
            const Spacer(),
            const Icon(Icons.shield_outlined, size: 13, color: mutedText),
            const SizedBox(width: 4),
            const Text(
              'Just us',
              style: TextStyle(color: mutedText, fontSize: 11),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => tab = 2),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: softGreen,
                child: Text(
                  initialOf(_firstName),
                  style: const TextStyle(
                    color: forestGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (loadError != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEAEA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              loadError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Hey, $_firstName',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: inkText,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Share the bill. Keep the memories.',
                    style: TextStyle(color: mutedText, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 22),
        _heroCard(),
        const SizedBox(height: 16),
        _usualPeopleCard(),
        const SizedBox(height: 16),
        _recentActivityCard(),
        const SizedBox(height: 16),
        _monthCard(),
        const SizedBox(height: 16),
        _waysCard(),
      ],
    );
  }

  Widget _historyTab() {
    if (!splitsLoaded) {
      return const Center(child: CircularProgressIndicator(color: forestGreen));
    }
    if (records.isEmpty) {
      return _emptyState(
        Icons.history,
        'No history yet',
        'Your past splits will live here.',
        'Start a split',
        () => _openNewSplit(),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        const Text(
          'History',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: inkText,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
          decoration: _cardDecoration(),
          child: Column(children: [for (final r in records) _activityRow(r)]),
        ),
      ],
    );
  }

  Widget _profileTab() => ProfileTab(
    name: FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '',
    records: records,
    friends: friends,
    onNameChanged: () => setState(() {}),
  );

  // ---------- SHARED UI ----------
  BoxDecoration _cardDecoration({Color color = Colors.white}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: borderGreen),
  );

  Widget _emptyState(
    IconData icon,
    String title,
    String body,
    String cta,
    VoidCallback onTap,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: sageGreen),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: inkText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedText, fontSize: 12),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: forestGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(cta),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- HERO ----------
  Widget _heroCard() {
    return Container(
      height: 215,
      decoration: _cardDecoration(color: softGreen),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: 55,
            child: Transform.rotate(
              angle: 0.14,
              child: Container(
                width: 170,
                height: 190,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF7),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: darkText.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Barkada Dinner',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _receiptRow('You', '₱800.00'),
                    _receiptRow('Maria', '₱800.00'),
                    _receiptRow('Carlo', '₱800.00'),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 10,
            child: Icon(
              Icons.auto_awesome,
              color: const Color(0xFFB69BC8).withValues(alpha: 0.9),
              size: 24,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THE BEST THINGS ARE SHARED',
                  style: TextStyle(
                    color: sageGreen,
                    fontSize: 7,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No bill stress.\nJust good times.',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 25,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dinner dates or beach escapes.\nSplit fairly. Get back to the good stuff.',
                  style: TextStyle(color: sageGreen, fontSize: 10),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => _openNewSplit(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: forestGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Let's split something",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String name, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(name, style: const TextStyle(fontSize: 8)),
        const Spacer(),
        Text(
          amount,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  // ---------- YOUR USUAL PEOPLE ----------
  Widget _usualPeopleCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Your usual people',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: inkText,
                ),
              ),
              if (friends.isNotEmpty) ...[
                const SizedBox(width: 8),
                _pill('${friends.length}'),
              ],
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Pick your people. We'll handle the numbers.",
            style: TextStyle(color: mutedText, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (!friendsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  color: forestGreen,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (friends.isEmpty)
            _noFriendsYet()
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in friends) ...[
                    _friendAvatar(f.name),
                    const SizedBox(width: 18),
                  ],
                  _addPerson(),
                ],
              ),
            ),
            const Divider(height: 28, color: borderGreen),
            Row(
              children: [
                Text(
                  '${selected.length} friend${selected.length == 1 ? '' : 's'} selected',
                  style: const TextStyle(color: mutedText, fontSize: 11),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => _openNewSplit(
                          pre: friends
                              .map((f) => f.name)
                              .where(selected.contains)
                              .toList(),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: softGreen,
                    foregroundColor: forestGreen,
                    disabledBackgroundColor: const Color(0xFFEEF2E9),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Split with friends',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _noFriendsYet() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGreen),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFCFC6D6)),
            ),
            child: const Icon(Icons.group_add_outlined, color: mutedText),
          ),
          const SizedBox(height: 12),
          const Text(
            'No one here yet',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add the people you split with most.\nThey’ll show up here for one-tap splits.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 11),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _addFriendDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add your first friend'),
            style: OutlinedButton.styleFrom(
              foregroundColor: accentPurple,
              side: const BorderSide(color: Color(0xFFD9CCE6)),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendAvatar(String name) {
    final isSelected = selected.contains(name);
    final c = avatarColors(name);
    return GestureDetector(
      onLongPress: () => _confirmDeleteFriend(name),
      onTap: () => setState(() {
        isSelected ? selected.remove(name) : selected.add(name);
      }),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF8B6BAA)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  backgroundColor: c.$1,
                  child: Text(
                    initialOf(name),
                    style: TextStyle(
                      color: c.$2,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              if (isSelected)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B6BAA),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(color: mutedText, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _addPerson() => GestureDetector(
    onTap: _addFriendDialog,
    child: Column(
      children: [
        Container(
          width: 46,
          height: 46,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCFC6D6)),
          ),
          child: const Icon(Icons.add, color: mutedText),
        ),
        const SizedBox(height: 9),
        const Text(
          'Someone new',
          style: TextStyle(color: mutedText, fontSize: 9),
        ),
      ],
    ),
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: softGreen,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: sageGreen,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  // ---------- RECENT ACTIVITY ----------
  Widget _recentActivityCard() {
    final recent = records.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Recent activity',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: inkText,
                ),
              ),
              const Spacer(),
              if (records.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => tab = 1),
                  child: const Row(
                    children: [
                      Text(
                        'View all history',
                        style: TextStyle(color: mutedText, fontSize: 11),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 12, color: mutedText),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'A little recap of your shared moments.',
            style: TextStyle(color: mutedText, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (!splitsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  color: forestGreen,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (recent.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: const Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 38,
                    color: Color(0xFFC5CCBE),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No splits yet',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your first shared moment will show up here.',
                    style: TextStyle(color: mutedText, fontSize: 11),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                Text(
                  '${monthNames[recent.first.date.month - 1].toUpperCase()} ${recent.first.date.year}',
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 9,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${records.length} split${records.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: mutedText, fontSize: 10),
                ),
              ],
            ),
            for (final r in recent) _activityRow(r),
          ],
        ],
      ),
    );
  }

  Widget _activityRow(SplitRecord r) {
    final icon = switch (r.type) {
      SplitType.equal => Icons.people_outline,
      SplitType.item => Icons.restaurant,
      SplitType.days => Icons.calendar_today_outlined,
    };
    final c = avatarColors(r.title);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _viewSplit(r),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: borderGreen)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: c.$1,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: c.$2, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: inkText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${shortDate(r.date)}  •  ${r.peopleCount} people',
                    style: const TextStyle(color: mutedText, fontSize: 10),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  peso(r.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: inkText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.settled ? 'Settled' : '${r.unpaidCount} unpaid',
                  style: TextStyle(
                    color: r.settled ? sageGreen : const Color(0xFFB9703F),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- THIS MONTH ----------
  Widget _monthCard() {
    final now = DateTime.now();
    final thisMonth = records
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final totalSpent = thisMonth.fold<double>(0, (s, r) => s + r.total);
    final toCollect = thisMonth.fold<double>(0, (s, r) => s + r.unpaidAmount);
    final people = <String>{
      for (final r in thisMonth)
        for (final k in r.shares.keys)
          if (k != r.paidBy) k,
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(color: softGreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'THIS MONTH, TOGETHER',
                style: TextStyle(
                  color: sageGreen,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Spacer(),
              Icon(Icons.calendar_today_outlined, size: 15, color: sageGreen),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            peso(totalSpent),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A5B40),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            thisMonth.isEmpty
                ? 'Nothing shared yet. Your first split starts the tally.'
                : toCollect > 0
                ? 'Total shared expenses  •  ${peso(toCollect)} still to collect'
                : 'Total shared expenses  •  All settled up',
            style: const TextStyle(color: sageGreen, fontSize: 11),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _stat(Icons.call_split, '${thisMonth.length}', 'splits created'),
              const SizedBox(width: 28),
              _stat(
                Icons.people_outline,
                '${people.length}',
                'people included',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFD5E0CC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: sageGreen),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF4A5B40),
            ),
          ),
          Text(label, style: const TextStyle(color: sageGreen, fontSize: 9)),
        ],
      ),
    ],
  );

  // ---------- ONE BILL, THREE WAYS ----------
  Widget _waysCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A FAIR SHARE, YOUR WAY',
            style: TextStyle(
              color: mutedText,
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'One bill. Three ways.',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: inkText,
            ),
          ),
          const SizedBox(height: 16),
          _wayRow(
            Icons.people_outline,
            'Equal split',
            'Same good time, same share.',
            const Color(0xFFEBE0F5),
          ),
          _wayRow(
            Icons.restaurant,
            'Item-based',
            'Pay only for what you had.',
            const Color(0xFFF8E3D6),
          ),
          _wayRow(
            Icons.calendar_today_outlined,
            'Days-based',
            'A fair share for every day you were there.',
            const Color(0xFFDCE9E2),
          ),
        ],
      ),
    );
  }

  Widget _wayRow(IconData icon, String title, String subtitle, Color bg) {
    return InkWell(
      onTap: () => _openNewSplit(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: darkText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: mutedText, fontSize: 10),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: mutedText, size: 20),
          ],
        ),
      ),
    );
  }

  // ---------- BOTTOM NAV ----------
  Widget _bottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.history, Icons.history, 'History'),
      (Icons.person_outline, Icons.person, 'Profile'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: borderGreen)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(items.length, (i) {
              final active = tab == i;
              final item = items[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => tab = i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: active ? softGreen : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        active ? item.$2 : item.$1,
                        color: active ? forestGreen : mutedText,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$3,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? forestGreen : mutedText,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
