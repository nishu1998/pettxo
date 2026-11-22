// ignore_for_file: subtype_of_sealed_class
// Minimal in-memory Firestore for repository unit tests. Supports exactly what
// the like, comment, share, service and block-set code paths use:
// collection/doc refs, doc get/set/update/delete, where(isEqualTo/whereIn) +
// limit queries, and runTransaction. Every read is recorded in [log] so tests
// can assert which Firestore operations a flow performs.
import 'package:cloud_firestore/cloud_firestore.dart';

typedef JsonMap = Map<String, dynamic>;

class InMemoryFirestore implements FirebaseFirestore {
  final Map<String, JsonMap> _docs = <String, JsonMap>{};

  /// Every read, e.g. `get userBlocks/a_b`, `txget socialPosts/p1`,
  /// `query userBlocks ownerUserId == a`.
  final List<String> log = <String>[];

  /// Errors to throw from queries on a collection path (simulated failures).
  final Map<String, Object> queryErrors = <String, Object>{};

  int _autoId = 0;

  void seed(String path, JsonMap data) =>
      _docs[path] = Map<String, dynamic>.of(data);

  JsonMap? read(String path) => _docs[path];

  bool exists(String path) => _docs.containsKey(path);

  List<String> pointGetsOn(String collection) => log
      .where(
        (entry) =>
            (entry.startsWith('get $collection/') ||
            entry.startsWith('txget $collection/')),
      )
      .toList(growable: false);

  List<String> queriesOn(String collection) => log
      .where((entry) => entry.startsWith('query $collection '))
      .toList(growable: false);

  String _nextId() => 'auto${_autoId++}';

  JsonMap _resolve(JsonMap data, {JsonMap? base}) {
    final result = Map<String, dynamic>.of(base ?? const <String, dynamic>{});
    data.forEach((key, value) {
      result[key] = value is FieldValue ? Timestamp.now() : value;
    });
    return result;
  }

  @override
  CollectionReference<JsonMap> collection(String collectionPath) =>
      FakeCollectionReference(this, collectionPath);

  @override
  DocumentReference<JsonMap> doc(String documentPath) =>
      FakeDocumentReference(this, documentPath);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = FakeTransaction(this);
    final result = await transactionHandler(transaction);
    transaction._commit();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDocumentSnapshot implements DocumentSnapshot<JsonMap> {
  FakeDocumentSnapshot(this.reference, this._data);

  @override
  final DocumentReference<JsonMap> reference;
  final JsonMap? _data;

  @override
  String get id => reference.id;

  @override
  bool get exists => _data != null;

  @override
  JsonMap? data() => _data == null ? null : Map.of(_data);

  @override
  dynamic get(Object field) => _data?[field];

  @override
  dynamic operator [](Object field) => _data?[field];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQueryDocumentSnapshot implements QueryDocumentSnapshot<JsonMap> {
  FakeQueryDocumentSnapshot(this.reference, this._data);

  @override
  final DocumentReference<JsonMap> reference;
  final JsonMap _data;

  @override
  String get id => reference.id;

  @override
  bool get exists => true;

  @override
  JsonMap data() => Map.of(_data);

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDocumentReference implements DocumentReference<JsonMap> {
  FakeDocumentReference(this._db, this.path);

  final InMemoryFirestore _db;

  @override
  final String path;

  @override
  FirebaseFirestore get firestore => _db;

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<JsonMap> collection(String collectionPath) =>
      FakeCollectionReference(_db, '$path/$collectionPath');

  @override
  Future<DocumentSnapshot<JsonMap>> get([GetOptions? options]) async {
    _db.log.add('get $path');
    return FakeDocumentSnapshot(this, _db._docs[path]);
  }

  @override
  Future<void> set(JsonMap data, [SetOptions? options]) async {
    _db._docs[path] = _db._resolve(data);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    final existing = _db._docs[path];
    if (existing == null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
    }
    _db._docs[path] = _db._resolve(
      data.cast<String, dynamic>(),
      base: existing,
    );
  }

  @override
  Future<void> delete() async {
    _db._docs.remove(path);
  }

  @override
  bool operator ==(Object other) =>
      other is FakeDocumentReference && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Filter {
  const _Filter(this.field, this.isEqualTo, this.whereIn);

  final String field;
  final Object? isEqualTo;
  final List<Object?>? whereIn;

  bool matches(String docId, JsonMap data) {
    final value = field == '__name__' ? docId : data[field];
    if (whereIn != null) return whereIn!.contains(value);
    return value == isEqualTo;
  }

  @override
  String toString() =>
      whereIn != null ? '$field in $whereIn' : '$field == $isEqualTo';
}

class FakeQuery implements Query<JsonMap> {
  FakeQuery(this._db, this._collectionPath, this._filters, this._limit);

  final InMemoryFirestore _db;
  final String _collectionPath;
  final List<_Filter> _filters;
  final int? _limit;

  @override
  FirebaseFirestore get firestore => _db;

  @override
  Query<JsonMap> limit(int limit) =>
      FakeQuery(_db, _collectionPath, _filters, limit);

  @override
  Future<QuerySnapshot<JsonMap>> get([GetOptions? options]) async {
    _db.log.add('query $_collectionPath ${_filters.join(' && ')}'.trim());
    final error = _db.queryErrors[_collectionPath];
    if (error != null) throw error;
    final prefix = '$_collectionPath/';
    final docs = <QueryDocumentSnapshot<JsonMap>>[];
    for (final entry in _db._docs.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final docId = entry.key.substring(prefix.length);
      if (docId.contains('/')) continue;
      if (!_filters.every((filter) => filter.matches(docId, entry.value))) {
        continue;
      }
      docs.add(
        FakeQueryDocumentSnapshot(
          FakeDocumentReference(_db, entry.key),
          entry.value,
        ),
      );
      if (_limit != null && docs.length >= _limit) break;
    }
    return FakeQuerySnapshot(docs);
  }

  Query<JsonMap> _where(Invocation invocation) {
    final rawField = invocation.positionalArguments.first;
    final field = rawField is FieldPath ? '__name__' : '$rawField';
    final named = invocation.namedArguments;
    final whereIn = named[#whereIn] as Iterable<Object?>?;
    return FakeQuery(_db, _collectionPath, <_Filter>[
      ..._filters,
      _Filter(field, named[#isEqualTo], whereIn?.toList()),
    ], _limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) return _where(invocation);
    return super.noSuchMethod(invocation);
  }
}

class FakeCollectionReference extends FakeQuery
    implements CollectionReference<JsonMap> {
  FakeCollectionReference(InMemoryFirestore db, String path)
    : super(db, path, const <_Filter>[], null);

  @override
  String get path => _collectionPath;

  @override
  String get id => _collectionPath.split('/').last;

  @override
  DocumentReference<JsonMap> doc([String? path]) =>
      FakeDocumentReference(_db, '$_collectionPath/${path ?? _db._nextId()}');
}

class FakeQuerySnapshot implements QuerySnapshot<JsonMap> {
  FakeQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<JsonMap>> docs;

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransaction implements Transaction {
  FakeTransaction(this._db);

  final InMemoryFirestore _db;
  final List<void Function()> _writes = <void Function()>[];

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    final path = documentReference.path;
    _db.log.add('txget $path');
    final snapshot = FakeDocumentSnapshot(
      FakeDocumentReference(_db, path),
      _db._docs[path],
    );
    return snapshot as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    final path = documentReference.path;
    _writes.add(() => _db._docs[path] = _db._resolve(data as JsonMap));
    return this;
  }

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<String, dynamic> data,
  ) {
    final path = documentReference.path;
    _writes.add(() {
      final existing = _db._docs[path];
      if (existing == null) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      }
      _db._docs[path] = _db._resolve(data, base: existing);
    });
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    final path = documentReference.path;
    _writes.add(() => _db._docs.remove(path));
    return this;
  }

  void _commit() {
    for (final write in _writes) {
      write();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
