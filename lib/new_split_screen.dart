import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'models.dart';

class NewSplitScreen extends StatefulWidget {
  final String myName;
  final List<String> friends;
  final List<String> preselected;

  final SplitRecord? editing;

  const NewSplitScreen({
    super.key,
    required this.myName,
    this.friends = const [],
    this.preselected = const [],
    this.editing,
  });

  @override
  State<NewSplitScreen> createState() => _NewSplitScreenState();
}

class _NewSplitScreenState extends State<NewSplitScreen> {
  final _titleCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _guestCtrl = TextEditingController();
  final _itemNameCtrl = TextEditingController();
  final _itemPriceCtrl = TextEditingController();

  late List<String> people;
  final Map<String, int> days = {};
  final List<SplitItem> items = [];
  SplitType type = SplitType.equal;
  String? error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      people = e.shares.keys.toList();
      type = e.type;
      _titleCtrl.text = e.title;
      _totalCtrl.text = e.total == e.total.roundToDouble()
          ? e.total.toInt().toString()
          : e.total.toStringAsFixed(2);
      items.addAll(
        e.items.map((i) => SplitItem(i.name, i.price, {...i.sharedBy})),
      );
    } else {
      people = [widget.myName, ...widget.preselected];
    }
    for (final p in people) {
      days[p] = widget.editing?.days[p] ?? 1;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _totalCtrl.dispose();
    _guestCtrl.dispose();
    _itemNameCtrl.dispose();
    _itemPriceCtrl.dispose();
    super.dispose();
  }

  // ---------- STATE HELPERS ----------
  String get _me {
    final e = widget.editing;
    return (e != null && e.paidBy.isNotEmpty) ? e.paidBy : widget.myName;
  }

  double get total => double.tryParse(_totalCtrl.text.replaceAll(',', '')) ?? 0;
  int get totalCents => (total * 100).round();
  double get itemsTotal => items.fold(0.0, (s, i) => s + i.price);

  void _addPerson(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    if (people.any((p) => p.toLowerCase() == name.toLowerCase())) return;
    setState(() {
      people.add(name);
      days[name] = 1;
      error = null;
    });
  }

  void _removePerson(String name) {
    setState(() {
      people.remove(name);
      days.remove(name);
      for (final i in items) {
        i.sharedBy.remove(name);
      }
    });
  }

  void _addItem() {
    final name = _itemNameCtrl.text.trim();
    final price = double.tryParse(_itemPriceCtrl.text.replaceAll(',', ''));
    if (name.isEmpty || price == null || price <= 0) return;
    setState(() {
      items.add(SplitItem(name, price, people.toSet()));
      _itemNameCtrl.clear();
      _itemPriceCtrl.clear();
      error = null;
    });
  }

  // ---------- CALCULATION ----------
  Map<String, int> _computeCents() {
    final out = {for (final p in people) p: 0};

    switch (type) {
      case SplitType.equal:
        final a = allocate(totalCents, List.filled(people.length, 1));
        for (var i = 0; i < people.length; i++) {
          out[people[i]] = a[i];
        }
      case SplitType.days:
        final a = allocate(
          totalCents,
          people.map((p) => days[p] ?? 1).toList(),
        );
        for (var i = 0; i < people.length; i++) {
          out[people[i]] = a[i];
        }
      case SplitType.item:
        for (final it in items) {
          final members = people.where((p) => it.sharedBy.contains(p)).toList();
          final a = allocate(
            (it.price * 100).round(),
            List.filled(members.length, 1),
          );
          for (var i = 0; i < members.length; i++) {
            out[members[i]] = out[members[i]]! + a[i];
          }
        }
    }
    return out;
  }

  String? _validate() {
    if (_titleCtrl.text.trim().isEmpty) {
      return "Give this split a name. What's the occasion?";
    }
    if (totalCents <= 0) return 'Enter the total bill.';
    if (people.length < 2) return 'Add at least one more person.';
    if (type == SplitType.item) {
      if (items.isEmpty) return 'Add at least one item.';
      if (items.any((i) => i.sharedBy.isEmpty)) {
        return 'Every item needs at least one person.';
      }
      if ((itemsTotal * 100).round() != totalCents) {
        return 'Your items should add up to ${peso(total)}.';
      }
    }
    return null;
  }

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    final err = _validate();
    if (err != null) {
      setState(() => error = err);
      return;
    }
    setState(() => error = null);

    final cents = _computeCents();
    final old = widget.editing;
    final paidBy = (old != null && old.paidBy.isNotEmpty)
        ? old.paidBy
        : widget.myName;

    final record = SplitRecord(
      id: old?.id,
      title: _titleCtrl.text.trim(),
      total: totalCents / 100,
      date: old?.date ?? DateTime.now(),
      type: type,
      paidBy: paidBy,
      shares: {for (final e in cents.entries) e.key: e.value / 100},
      // the person who covered the bill is always paid
      paid: {
        for (final p in cents.keys)
          p: p == paidBy ? true : (old?.paid[p] ?? false),
      },
      items: type == SplitType.item
          ? [
              for (final i in items)
                SplitItem(i.name, i.price, {...i.sharedBy}),
            ]
          : const [],
      days: type == SplitType.days
          ? {for (final p in people) p: days[p] ?? 1}
          : const {},
    );

    final save = await showBreakdownSheet(
      context,
      record,
      myName: widget.myName,
      canSave: true,
      saveLabel: old == null ? 'Save split' : 'Save changes',
    );
    if (save == true && mounted) Navigator.pop(context, record);
  }

  // ---------- UI ----------
  InputDecoration _decoration(String hint, {String? prefix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFAAA6AA), fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    prefixText: prefix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: borderGreen),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: sageGreen, width: 1.5),
    ),
  );

  Widget _label(String text, {String? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF5E6F55),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(color: mutedText, fontSize: 11),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label("What's the occasion?"),
                      TextField(
                        controller: _titleCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: _decoration('e.g. Barkada Dinner'),
                      ),
                      const SizedBox(height: 22),
                      _label('Total bill'),
                      _totalField(),
                      const SizedBox(height: 22),
                      _label("Who's in?", trailing: '${people.length} people'),
                      _peopleChips(),
                      _addFriendRow(),
                      const SizedBox(height: 16),
                      _guestRow(),
                      const SizedBox(height: 24),
                      _label('How are we splitting?'),
                      _segments(),
                      const SizedBox(height: 16),
                      if (type == SplitType.equal) _equalView(),
                      if (type == SplitType.item) _itemView(),
                      if (type == SplitType.days) _daysView(),
                      const SizedBox(height: 18),
                      const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: mutedText,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Every peso is accounted for.',
                            style: TextStyle(color: mutedText, fontSize: 11),
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _calculate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: forestGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Calculate breakdown',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
    decoration: const BoxDecoration(
      color: cream,
      border: Border(bottom: BorderSide(color: borderGreen)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editing == null
                    ? 'Good times, fairly split.'
                    : 'Edit this split.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: inkText,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'A few details. We’ll take care of the math.',
                style: TextStyle(color: mutedText, fontSize: 11),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: borderGreen),
            ),
            child: const Icon(Icons.close, color: sageGreen, size: 20),
          ),
        ),
      ],
    ),
  );

  Widget _totalField() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderGreen),
    ),
    child: Row(
      children: [
        const Text(
          '₱',
          style: TextStyle(
            fontSize: 24,
            color: sageGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _totalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() => error = null),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A5B40),
            ),
            decoration: const InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(color: Color(0xFFCFD3C8)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _peopleChips() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final p in people)
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: borderGreen),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              personAvatar(p, size: 28),
              const SizedBox(width: 8),
              Text(
                p,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (p == _me)
                const Text(
                  ' (you)',
                  style: TextStyle(color: mutedText, fontSize: 10),
                )
              else ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _removePerson(p),
                  child: const Icon(Icons.close, size: 13, color: mutedText),
                ),
              ],
            ],
          ),
        ),
    ],
  );

  Widget _addFriendRow() {
    final available = widget.friends
        .where((f) => !people.any((p) => p.toLowerCase() == f.toLowerCase()))
        .toList();
    if (available.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 6,
        children: [
          const Text(
            'Add a friend:',
            style: TextStyle(color: mutedText, fontSize: 11),
          ),
          for (final f in available)
            GestureDetector(
              onTap: () => _addPerson(f),
              child: Text(
                '+ $f',
                style: const TextStyle(
                  color: accentPurple,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _guestRow() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _guestCtrl,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) {
            _addPerson(v);
            _guestCtrl.clear();
          },
          decoration: _decoration('Or add a one-time guest'),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: () {
            _addPerson(_guestCtrl.text);
            _guestCtrl.clear();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add guest'),
          style: OutlinedButton.styleFrom(
            foregroundColor: mutedText,
            side: const BorderSide(color: borderGreen),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    ],
  );

  Widget _segments() {
    const opts = [
      (SplitType.equal, Icons.people_outline, 'Equal Split'),
      (SplitType.item, Icons.restaurant, 'Item-Based'),
      (SplitType.days, Icons.calendar_today_outlined, 'Days-Based'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF0E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderGreen),
      ),
      child: Row(
        children: [
          for (final o in opts)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  type = o.$1;
                  error = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: type == o.$1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        o.$2,
                        size: 14,
                        color: type == o.$1 ? forestGreen : mutedText,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          o.$3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: type == o.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: type == o.$1 ? forestGreen : mutedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ----- EQUAL -----
  Widget _equalView() {
    final each = people.isEmpty ? 0.0 : total / people.length;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFDDE8D8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_outline, color: sageGreen, size: 28),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Everyone gets an equal share',
                  style: TextStyle(color: accentPurple, fontSize: 10.5),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          peso(each),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4A5B40),
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text(
                        '/ person',
                        style: TextStyle(color: sageGreen, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- ITEM-BASED -----
  Widget _itemView() {
    final matches = (itemsTotal * 100).round() == totalCents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select who shared each item. We split shared items equally.',
          style: TextStyle(color: mutedText, fontSize: 11),
        ),
        const SizedBox(height: 14),
        for (var idx = 0; idx < items.length; idx++) _itemCard(items[idx], idx),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _itemNameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration('Item name'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _itemPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: _decoration('Price', prefix: '₱ '),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addItem,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderGreen),
                ),
                child: const Icon(Icons.add, color: forestGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'Items total',
              style: TextStyle(color: mutedText, fontSize: 11),
            ),
            const Spacer(),
            Text(
              '${peso(itemsTotal)} / ${peso(total)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: matches ? const Color(0xFF4A5B40) : Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemCard(SplitItem it, int idx) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderGreen),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                it.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              peso(it.price),
              style: const TextStyle(color: sageGreen, fontSize: 12),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: () => setState(() => items.removeAt(idx)),
              child: const Icon(Icons.close, size: 15, color: mutedText),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in people)
              GestureDetector(
                onTap: () => setState(() {
                  it.sharedBy.contains(p)
                      ? it.sharedBy.remove(p)
                      : it.sharedBy.add(p);
                  error = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: it.sharedBy.contains(p)
                        ? const Color(0xFFDCE9D6)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: it.sharedBy.contains(p)
                          ? Colors.transparent
                          : borderGreen,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.sharedBy.contains(p)) ...[
                        const Icon(Icons.check, size: 12, color: sageGreen),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        p,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: it.sharedBy.contains(p)
                              ? forestGreen
                              : mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  // ----- DAYS-BASED -----
  Widget _daysView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'A fair share for every day they were there.',
        style: TextStyle(color: mutedText, fontSize: 11),
      ),
      const SizedBox(height: 10),
      for (final p in people)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: borderGreen)),
          ),
          child: Row(
            children: [
              personAvatar(p, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  p,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              _stepBtn(
                Icons.remove,
                (days[p] ?? 1) > 1,
                () => setState(() => days[p] = (days[p] ?? 1) - 1),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${days[p] ?? 1} ${(days[p] ?? 1) == 1 ? 'day' : 'days'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: mutedText, fontSize: 11),
                ),
              ),
              _stepBtn(
                Icons.add,
                true,
                () => setState(() => days[p] = (days[p] ?? 1) + 1),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _stepBtn(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFEFF3EA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderGreen),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? forestGreen : const Color(0xFFC5CCBE),
          ),
        ),
      );
}

// ---------- BREAKDOWN SHEET ----------
Future<bool?> showBreakdownSheet(
  BuildContext context,
  SplitRecord r, {
  required String myName,
  bool canSave = false,
  String saveLabel = 'Save split',
  void Function(Map<String, bool> paid)? onPaidChanged,
  void Function(SplitRecord current)? onEdit,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final paid = Map<String, bool>.from(r.paid);

      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final current = r.copyWith(paid: paid);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: inkText,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${peso(r.total)} total  •  ${shortDate(r.date)}',
                    style: const TextStyle(color: mutedText, fontSize: 11),
                  ),
                  if (!canSave) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: current.settled
                            ? softGreen
                            : const Color(0xFFF8E3D6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        current.settled
                            ? 'All settled up'
                            : '${current.unpaidCount} not paid yet  •  ${peso(current.unpaidAmount)} to collect',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: current.settled
                              ? forestGreen
                              : const Color(0xFFB9703F),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final e in r.shares.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  personAvatar(e.key, size: 36),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.key ==
                                                  (r.paidBy.isEmpty
                                                      ? myName
                                                      : r.paidBy)
                                              ? '${e.key} (you)'
                                              : e.key,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          peso(e.value),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            color: Color(0xFF4A5B40),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!canSave)
                                    _paidPill(
                                      isPaid: paid[e.key] ?? false,
                                      locked: e.key == r.paidBy,
                                      onTap: () {
                                        setSheet(
                                          () => paid[e.key] =
                                              !(paid[e.key] ?? false),
                                        );
                                        onPaidChanged?.call(Map.of(paid));
                                      },
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (canSave)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: forestGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          saveLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                onEdit?.call(current);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: forestGreen,
                                side: const BorderSide(color: borderGreen),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: ctx,
                                  builder: (d) => AlertDialog(
                                    backgroundColor: Colors.white,
                                    title: const Text(
                                      'Delete this split?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                      ),
                                    ),
                                    content: Text(
                                      '“${r.title}” will be removed for good.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(d, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(d, true),
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true && ctx.mounted) {
                                  Navigator.pop(ctx);
                                  onDelete?.call();
                                }
                              },
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                  color: Color(0xFFF1D3D3),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _paidPill({
  required bool isPaid,
  required bool locked,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: locked ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPaid ? softGreen : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPaid ? Colors.transparent : borderGreen),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: isPaid ? sageGreen : mutedText,
          ),
          const SizedBox(width: 5),
          Text(
            isPaid ? 'Paid' : 'Unpaid',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isPaid ? forestGreen : mutedText,
            ),
          ),
        ],
      ),
    ),
  );
}
