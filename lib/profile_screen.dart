import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data_service.dart';
import 'main.dart';
import 'models.dart';

class ProfileTab extends StatefulWidget {
  final String name;
  final List<SplitRecord> records;
  final List<Friend> friends;
  final VoidCallback onNameChanged;

  const ProfileTab({
    super.key,
    required this.name,
    required this.records,
    required this.friends,
    required this.onNameChanged,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<PaymentAccount> accounts = [];
  StreamSubscription<List<PaymentAccount>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = DataService.paymentsStream().listen((list) {
      if (!mounted) return;
      setState(() => accounts = list);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------- HELPERS ----------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _run(Future<void> Function() action) {
    action().catchError((Object e) {
      _snack('Couldn’t save that. Please try again.');
    });
  }

  BoxDecoration get _card => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: borderGreen),
  );

  Future<String?> _textDialog(
    String title, {
    String initial = '',
    String hint = '',
    String action = 'Save',
  }) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(action),
          ),
        ],
      ),
    );
    return res?.trim();
  }

  // ---------- ACTIONS ----------
  Future<void> _editName() async {
    final n = await _textDialog(
      'Your name',
      initial: widget.name,
      hint: 'Your name',
    );
    if (n == null || n.isEmpty || n == widget.name) return;
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await user.updateDisplayName(n);
      await user.reload();
      widget.onNameChanged();
    } catch (_) {
      _snack('Couldn’t update your name. Please try again.');
    }
  }

  Future<void> _addFriend() async {
    final n = await _textDialog(
      'Add a friend',
      hint: "Friend's name",
      action: 'Add',
    );
    if (n == null || n.isEmpty) return;
    if (widget.friends.any((f) => f.name.toLowerCase() == n.toLowerCase())) {
      _snack('$n is already in your list.');
      return;
    }
    _run(() => DataService.addFriend(n));
  }

  Future<void> _renameFriend(Friend f) async {
    final n = await _textDialog('Rename friend', initial: f.name);
    if (n == null || n.isEmpty || n == f.name) return;
    if (widget.friends.any(
      (x) => x.id != f.id && x.name.toLowerCase() == n.toLowerCase(),
    )) {
      _snack('$n is already in your list.');
      return;
    }
    _run(() => DataService.renameFriend(f.id, n));
  }

  Future<void> _removeFriend(Friend f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Remove ${f.name}?',
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
    if (ok == true) _run(() => DataService.deleteFriend(f.id));
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFAAA6AA), fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF7F9F4),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: borderGreen),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: sageGreen, width: 1.5),
    ),
  );

  Future<void> _editAccount([PaymentAccount? existing]) async {
    var method = existing?.method ?? 'GCash';
    String? formError;
    final bankCtrl = TextEditingController(text: existing?.bankName ?? '');
    final nameCtrl = TextEditingController(text: existing?.accountName ?? '');
    final numCtrl = TextEditingController(text: existing?.accountNumber ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isBank = method == 'Bank';

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              22,
              24,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null
                      ? 'Add a payment account'
                      : 'Edit payment account',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: inkText,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add as many as you like. Friends can pick one.',
                  style: TextStyle(color: mutedText, fontSize: 11),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in ['GCash', 'Maya', 'Bank'])
                      GestureDetector(
                        onTap: () => setSheet(() {
                          // a mobile number and a bank account number are
                          // different things, so clear it when switching kind
                          if ((m == 'Bank') != isBank) numCtrl.clear();
                          method = m;
                          formError = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: method == m ? softGreen : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: method == m
                                  ? Colors.transparent
                                  : borderGreen,
                            ),
                          ),
                          child: Text(
                            m,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: method == m ? forestGreen : mutedText,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (isBank) ...[
                  TextField(
                    controller: bankCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('Bank name (e.g. BDO, BPI, UnionBank)'),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec(
                    isBank ? 'Account name' : 'Name on your $method account',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: numCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: isBank ? 20 : 11,
                  decoration: _dec(
                    isBank
                        ? 'Account number'
                        : '$method mobile number (09XXXXXXXXX)',
                  ).copyWith(counterText: ''),
                ),
                if (formError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    formError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (isBank && bankCtrl.text.trim().isEmpty) {
                        setSheet(() => formError = 'Enter the bank name.');
                        return;
                      }
                      if (numCtrl.text.trim().isEmpty) {
                        setSheet(
                          () => formError = isBank
                              ? 'Enter the account number.'
                              : 'Enter the mobile number.',
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: forestGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      existing == null ? 'Add account' : 'Save',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true) return;

    final account = PaymentAccount(
      id: existing?.id ?? '',
      method: method,
      bankName: method == 'Bank' ? bankCtrl.text.trim() : '',
      accountName: nameCtrl.text.trim(),
      accountNumber: numCtrl.text.trim(),
      created: existing?.created ?? DateTime.now(),
    );
    _run(
      () => existing == null
          ? DataService.addPayment(account)
          : DataService.updatePayment(account),
    );
  }

  Future<void> _removeAccount(PaymentAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Remove ${a.label} account?',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(a.accountNumber),
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
    if (ok == true) _run(() => DataService.deletePayment(a.id));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _deleteAccount() async {
    final pwCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Delete your account?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your friends, splits, and payment details. It can’t be undone.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Enter your password to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: pwCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await DataService.deleteAllData();
      await user.delete(); // sends the user back to the login screen
    } on FirebaseAuthException catch (e) {
      _snack(
        e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Incorrect password.'
            : 'Couldn’t delete your account. Please try again.',
      );
    } catch (_) {
      _snack('Couldn’t delete your account. Please try again.');
    }
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = widget.name.isNotEmpty ? widget.name : 'You';

    final totalShared = widget.records.fold<double>(0, (s, r) => s + r.total);
    final toCollect = widget.records.fold<double>(
      0,
      (s, r) => s + r.unpaidAmount,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      children: [
        const Text(
          'Profile',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: inkText,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 18),

        // Identity
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _card,
          child: Row(
            children: [
              personAvatar(displayName, size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: inkText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user?.email ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit name',
                onPressed: _editName,
                icon: const Icon(
                  Icons.edit_outlined,
                  color: sageGreen,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Stats
        Row(
          children: [
            _statTile('${widget.records.length}', 'splits'),
            const SizedBox(width: 10),
            _statTile(peso(totalShared), 'shared'),
            const SizedBox(width: 10),
            _statTile(peso(toCollect), 'to collect'),
          ],
        ),
        const SizedBox(height: 16),

        _paymentCard(),
        const SizedBox(height: 16),
        _friendsCard(),
        const SizedBox(height: 22),

        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: forestGreen,
              side: const BorderSide(color: borderGreen),
              backgroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _deleteAccount,
          child: const Text(
            'Delete account',
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _statTile(String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: softGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Color(0xFF4A5B40),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: sageGreen, fontSize: 10)),
        ],
      ),
    ),
  );

  Widget _paymentCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Payment accounts',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: inkText,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _editAccount(),
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 16, color: accentPurple),
                    SizedBox(width: 2),
                    Text(
                      'Add account',
                      style: TextStyle(
                        color: accentPurple,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            accounts.isEmpty
                ? 'Add your GCash, Maya, or bank accounts so friends know where to send their share.'
                : 'Friends can copy any of these to pay you back.',
            style: const TextStyle(color: mutedText, fontSize: 11),
          ),
          for (final a in accounts) _accountTile(a),
        ],
      ),
    );
  }

  Widget _accountTile(PaymentAccount a) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderGreen),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEBE0F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              a.label,
              style: const TextStyle(
                color: accentPurple,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.accountName.isNotEmpty)
                  Text(
                    a.accountName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                Text(
                  a.accountNumber,
                  style: const TextStyle(color: mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy number',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: a.accountNumber));
              _snack('${a.label} number copied');
            },
            icon: const Icon(Icons.copy_rounded, size: 18, color: sageGreen),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, size: 18, color: mutedText),
            onSelected: (v) {
              if (v == 'edit') _editAccount(a);
              if (v == 'delete') _removeAccount(a);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Remove',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _friendsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Your people',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: inkText,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _addFriend,
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 16, color: accentPurple),
                    SizedBox(width: 2),
                    Text(
                      'Add friend',
                      style: TextStyle(
                        color: accentPurple,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.friends.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'No friends yet. Add the people you split with most.',
                style: TextStyle(color: mutedText, fontSize: 11),
              ),
            )
          else
            for (final f in widget.friends)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: borderGreen)),
                ),
                margin: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    personAvatar(f.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rename',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _renameFriend(f),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: mutedText,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeFriend(f),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
