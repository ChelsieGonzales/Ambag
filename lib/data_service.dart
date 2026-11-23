import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';

/// Everything is stored per user:
///   users/{uid}/friends/{friendId}  -> { name }
///   users/{uid}/splits/{splitId}    -> { title, total, date, type, paidBy,
///                                        shares, paid, items, days }
class DataService {
  DataService._();

  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(FirebaseAuth.instance.currentUser!.uid);

  static CollectionReference<Map<String, dynamic>> get _friends =>
      _userDoc.collection('friends');

  static CollectionReference<Map<String, dynamic>> get _splits =>
      _userDoc.collection('splits');

  // ---------- FRIENDS ----------
  static Stream<List<Friend>> friendsStream() {
    return _friends.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Friend(d.id, (d.data()['name'] ?? '') as String))
          .where((f) => f.name.isNotEmpty)
          .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  static Future<void> addFriend(String name) async {
    await _friends.add({'name': name});
  }

  static Future<void> deleteFriend(String id) => _friends.doc(id).delete();

  static Future<void> renameFriend(String id, String name) =>
      _friends.doc(id).update({'name': name});

  // ---------- PAYMENT ACCOUNTS ----------
  /// users/{uid}/payments/{id} -> { method, bankName, accountName,
  ///                                accountNumber, createdAt }
  static CollectionReference<Map<String, dynamic>> get _payments =>
      _userDoc.collection('payments');

  static Stream<List<PaymentAccount>> paymentsStream() {
    return _payments.snapshots().map((snap) {
      final list = snap.docs.map(PaymentAccount.fromDoc).toList();
      list.sort((a, b) => a.created.compareTo(b.created));
      return list;
    });
  }

  static Future<void> addPayment(PaymentAccount a) async {
    await _payments.add({...a.toMap(), 'createdAt': Timestamp.now()});
  }

  static Future<void> updatePayment(PaymentAccount a) =>
      _payments.doc(a.id).update(a.toMap());

  static Future<void> deletePayment(String id) => _payments.doc(id).delete();

  /// Removes everything this user stored (used by "Delete account").
  static Future<void> deleteAllData() async {
    for (final col in [_friends, _splits, _payments]) {
      final snap = await col.get();
      for (var i = 0; i < snap.docs.length; i += 400) {
        final batch = _db.batch();
        for (final d in snap.docs.skip(i).take(400)) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
    await _userDoc.delete();
  }

  // ---------- SPLITS ----------
  static Stream<List<SplitRecord>> splitsStream() {
    return _splits
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SplitRecord.fromDoc).toList());
  }

  /// Creates a new split, or overwrites it when [r.id] is set (edit).
  static Future<void> saveSplit(SplitRecord r) async {
    if (r.id == null) {
      await _splits.add(r.toMap());
    } else {
      await _splits.doc(r.id).set(r.toMap());
    }
  }

  static Future<void> setPaid(String id, Map<String, bool> paid) =>
      _splits.doc(id).update({'paid': paid});

  static Future<void> deleteSplit(String id) => _splits.doc(id).delete();
}
