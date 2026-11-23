import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color softGreen = Color(0xFFE3EBDC);
const Color mutedText = Color(0xFF93889A);
const Color borderGreen = Color(0xFFDDE5D5);
const Color inkText = Color(0xFF30352F);
const Color accentPurple = Color(0xFF7A5C99);
const Color pageBg = Color(0xFFF4F7F0);

enum SplitType { equal, item, days }

class Friend {
  final String id;
  final String name;
  const Friend(this.id, this.name);
}

/// One place a friend can send money to (GCash, Maya, a bank...).
/// A user can save as many as they like.
class PaymentAccount {
  final String id;
  final String method; // 'GCash' | 'Maya' | 'Bank'
  final String bankName; // only for Bank
  final String accountName;
  final String accountNumber;
  final DateTime created;

  const PaymentAccount({
    required this.id,
    required this.method,
    this.bankName = '',
    this.accountName = '',
    required this.accountNumber,
    required this.created,
  });

  /// What to show on the pill: the bank's name for bank accounts.
  String get label =>
      method == 'Bank' && bankName.isNotEmpty ? bankName : method;

  Map<String, dynamic> toMap() => {
    'method': method,
    'bankName': bankName,
    'accountName': accountName,
    'accountNumber': accountNumber,
  };

  factory PaymentAccount.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final ts = m['createdAt'];
    return PaymentAccount(
      id: d.id,
      method: (m['method'] ?? 'GCash') as String,
      bankName: (m['bankName'] ?? '') as String,
      accountName: (m['accountName'] ?? '') as String,
      accountNumber: (m['accountNumber'] ?? '') as String,
      created: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

/// One line item in an item-based split.
class SplitItem {
  String name;
  double price;
  Set<String> sharedBy;
  SplitItem(this.name, this.price, this.sharedBy);

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'sharedBy': sharedBy.toList(),
  };

  factory SplitItem.fromMap(Map<String, dynamic> m) => SplitItem(
    (m['name'] ?? '') as String,
    ((m['price'] ?? 0) as num).toDouble(),
    Set<String>.from(m['sharedBy'] ?? const []),
  );
}

/// One saved split.
class SplitRecord {
  final String? id; // null until saved
  final String title;
  final double total;
  final DateTime date;
  final SplitType type;
  final String paidBy; // who covered the bill (the app user)

  /// person name -> amount they owe
  final Map<String, double> shares;

  /// person name -> has paid their share back
  final Map<String, bool> paid;

  /// kept so a split can be edited later exactly as it was entered
  final List<SplitItem> items;
  final Map<String, int> days;

  const SplitRecord({
    this.id,
    required this.title,
    required this.total,
    required this.date,
    required this.type,
    required this.paidBy,
    required this.shares,
    this.paid = const {},
    this.items = const [],
    this.days = const {},
  });

  int get peopleCount => shares.length;
  bool isPaid(String p) => paid[p] ?? false;
  int get unpaidCount => shares.keys.where((p) => !isPaid(p)).length;
  double get unpaidAmount => shares.entries
      .where((e) => !isPaid(e.key))
      .fold(0.0, (s, e) => s + e.value);
  bool get settled => unpaidCount == 0;

  SplitRecord copyWith({String? id, Map<String, bool>? paid}) => SplitRecord(
    id: id ?? this.id,
    title: title,
    total: total,
    date: date,
    type: type,
    paidBy: paidBy,
    shares: shares,
    paid: paid ?? this.paid,
    items: items,
    days: days,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'total': total,
    'date': Timestamp.fromDate(date),
    'type': type.name,
    'paidBy': paidBy,
    'shares': shares,
    'paid': paid,
    'items': items.map((i) => i.toMap()).toList(),
    'days': days,
  };

  factory SplitRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final ts = m['date'];
    return SplitRecord(
      id: d.id,
      title: (m['title'] ?? '') as String,
      total: ((m['total'] ?? 0) as num).toDouble(),
      date: ts is Timestamp ? ts.toDate() : DateTime.now(),
      type: SplitType.values.firstWhere(
        (t) => t.name == m['type'],
        orElse: () => SplitType.equal,
      ),
      paidBy: (m['paidBy'] ?? '') as String,
      shares: {
        for (final e in Map<String, dynamic>.from(m['shares'] ?? {}).entries)
          e.key: (e.value as num).toDouble(),
      },
      paid: {
        for (final e in Map<String, dynamic>.from(m['paid'] ?? {}).entries)
          e.key: e.value == true,
      },
      items: [
        for (final i in (m['items'] ?? []) as List)
          SplitItem.fromMap(Map<String, dynamic>.from(i as Map)),
      ],
      days: {
        for (final e in Map<String, dynamic>.from(m['days'] ?? {}).entries)
          e.key: (e.value as num).toInt(),
      },
    );
  }
}

// ---------- AVATAR COLORS ----------
const _palette = [
  (Color(0xFFF8E3D6), Color(0xFFB9703F)), // peach
  (Color(0xFFDCE9E2), Color(0xFF4F7F66)), // mint
  (Color(0xFFEBE0F5), Color(0xFF7A5C99)), // lavender
  (Color(0xFFFAF0C8), Color(0xFFA08A2A)), // butter
];

(Color, Color) avatarColors(String name) {
  var h = 0;
  for (final c in name.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0xFFFF;
  }
  return _palette[h % _palette.length];
}

String initialOf(String name) =>
    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

Widget personAvatar(String name, {double size = 28}) {
  final c = avatarColors(name);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: c.$1, shape: BoxShape.circle),
    child: Text(
      initialOf(name),
      style: TextStyle(
        color: c.$2,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.42,
      ),
    ),
  );
}

// ---------- FORMATTING ----------
String peso(num v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '₱$whole.${parts[1]}';
}

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String shortDate(DateTime d) =>
    '${monthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

// ---------- MONEY MATH ----------
/// Splits [totalCents] by [weights] with no cents lost
/// (largest-remainder method). e.g. 190000 / 3 -> 63333, 63333, 63334.
List<int> allocate(int totalCents, List<num> weights) {
  final sum = weights.fold<num>(0, (a, b) => a + b);
  if (weights.isEmpty || sum <= 0) return List.filled(weights.length, 0);

  final raw = weights.map((w) => totalCents * w / sum).toList();
  final result = raw.map((r) => r.floor()).toList();
  final left = totalCents - result.fold<int>(0, (a, b) => a + b);

  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) => (raw[b] - result[b]).compareTo(raw[a] - result[a]));

  for (var i = 0; i < left; i++) {
    result[order[i % order.length]]++;
  }
  return result;
}
