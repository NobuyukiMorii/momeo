// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $VoiceMemosTable extends VoiceMemos
    with TableInfo<$VoiceMemosTable, VoiceMemo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceMemosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, content, createdAt, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_memos';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoiceMemo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoiceMemo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceMemo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $VoiceMemosTable createAlias(String alias) {
    return $VoiceMemosTable(attachedDatabase, alias);
  }
}

class VoiceMemo extends DataClass implements Insertable<VoiceMemo> {
  final int id;
  final String content;
  final DateTime createdAt;
  final int position;
  const VoiceMemo({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['position'] = Variable<int>(position);
    return map;
  }

  VoiceMemosCompanion toCompanion(bool nullToAbsent) {
    return VoiceMemosCompanion(
      id: Value(id),
      content: Value(content),
      createdAt: Value(createdAt),
      position: Value(position),
    );
  }

  factory VoiceMemo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceMemo(
      id: serializer.fromJson<int>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'position': serializer.toJson<int>(position),
    };
  }

  VoiceMemo copyWith({
    int? id,
    String? content,
    DateTime? createdAt,
    int? position,
  }) => VoiceMemo(
    id: id ?? this.id,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    position: position ?? this.position,
  );
  VoiceMemo copyWithCompanion(VoiceMemosCompanion data) {
    return VoiceMemo(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceMemo(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, content, createdAt, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceMemo &&
          other.id == this.id &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.position == this.position);
}

class VoiceMemosCompanion extends UpdateCompanion<VoiceMemo> {
  final Value<int> id;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<int> position;
  const VoiceMemosCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.position = const Value.absent(),
  });
  VoiceMemosCompanion.insert({
    this.id = const Value.absent(),
    required String content,
    required DateTime createdAt,
    this.position = const Value.absent(),
  }) : content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<VoiceMemo> custom({
    Expression<int>? id,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (position != null) 'position': position,
    });
  }

  VoiceMemosCompanion copyWith({
    Value<int>? id,
    Value<String>? content,
    Value<DateTime>? createdAt,
    Value<int>? position,
  }) {
    return VoiceMemosCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceMemosCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $UtterancesTable extends Utterances
    with TableInfo<$UtterancesTable, Utterance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UtterancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recognizedAtMeta = const VerificationMeta(
    'recognizedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recognizedAt = GeneratedColumn<DateTime>(
    'recognized_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<double> durationSec = GeneratedColumn<double>(
    'duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memoIdMeta = const VerificationMeta('memoId');
  @override
  late final GeneratedColumn<int> memoId = GeneratedColumn<int>(
    'memo_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    recognizedAt,
    durationSec,
    memoId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'utterances';
  @override
  VerificationContext validateIntegrity(
    Insertable<Utterance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('recognized_at')) {
      context.handle(
        _recognizedAtMeta,
        recognizedAt.isAcceptableOrUnknown(
          data['recognized_at']!,
          _recognizedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recognizedAtMeta);
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecMeta);
    }
    if (data.containsKey('memo_id')) {
      context.handle(
        _memoIdMeta,
        memoId.isAcceptableOrUnknown(data['memo_id']!, _memoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memoIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Utterance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Utterance(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      recognizedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recognized_at'],
      )!,
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}duration_sec'],
      )!,
      memoId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}memo_id'],
      )!,
    );
  }

  @override
  $UtterancesTable createAlias(String alias) {
    return $UtterancesTable(attachedDatabase, alias);
  }
}

class Utterance extends DataClass implements Insertable<Utterance> {
  final int id;
  final String content;
  final DateTime recognizedAt;
  final double durationSec;
  final int memoId;
  const Utterance({
    required this.id,
    required this.content,
    required this.recognizedAt,
    required this.durationSec,
    required this.memoId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['content'] = Variable<String>(content);
    map['recognized_at'] = Variable<DateTime>(recognizedAt);
    map['duration_sec'] = Variable<double>(durationSec);
    map['memo_id'] = Variable<int>(memoId);
    return map;
  }

  UtterancesCompanion toCompanion(bool nullToAbsent) {
    return UtterancesCompanion(
      id: Value(id),
      content: Value(content),
      recognizedAt: Value(recognizedAt),
      durationSec: Value(durationSec),
      memoId: Value(memoId),
    );
  }

  factory Utterance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Utterance(
      id: serializer.fromJson<int>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      recognizedAt: serializer.fromJson<DateTime>(json['recognizedAt']),
      durationSec: serializer.fromJson<double>(json['durationSec']),
      memoId: serializer.fromJson<int>(json['memoId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'content': serializer.toJson<String>(content),
      'recognizedAt': serializer.toJson<DateTime>(recognizedAt),
      'durationSec': serializer.toJson<double>(durationSec),
      'memoId': serializer.toJson<int>(memoId),
    };
  }

  Utterance copyWith({
    int? id,
    String? content,
    DateTime? recognizedAt,
    double? durationSec,
    int? memoId,
  }) => Utterance(
    id: id ?? this.id,
    content: content ?? this.content,
    recognizedAt: recognizedAt ?? this.recognizedAt,
    durationSec: durationSec ?? this.durationSec,
    memoId: memoId ?? this.memoId,
  );
  Utterance copyWithCompanion(UtterancesCompanion data) {
    return Utterance(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      recognizedAt: data.recognizedAt.present
          ? data.recognizedAt.value
          : this.recognizedAt,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      memoId: data.memoId.present ? data.memoId.value : this.memoId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Utterance(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('recognizedAt: $recognizedAt, ')
          ..write('durationSec: $durationSec, ')
          ..write('memoId: $memoId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, content, recognizedAt, durationSec, memoId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Utterance &&
          other.id == this.id &&
          other.content == this.content &&
          other.recognizedAt == this.recognizedAt &&
          other.durationSec == this.durationSec &&
          other.memoId == this.memoId);
}

class UtterancesCompanion extends UpdateCompanion<Utterance> {
  final Value<int> id;
  final Value<String> content;
  final Value<DateTime> recognizedAt;
  final Value<double> durationSec;
  final Value<int> memoId;
  const UtterancesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.recognizedAt = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.memoId = const Value.absent(),
  });
  UtterancesCompanion.insert({
    this.id = const Value.absent(),
    required String content,
    required DateTime recognizedAt,
    required double durationSec,
    required int memoId,
  }) : content = Value(content),
       recognizedAt = Value(recognizedAt),
       durationSec = Value(durationSec),
       memoId = Value(memoId);
  static Insertable<Utterance> custom({
    Expression<int>? id,
    Expression<String>? content,
    Expression<DateTime>? recognizedAt,
    Expression<double>? durationSec,
    Expression<int>? memoId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (recognizedAt != null) 'recognized_at': recognizedAt,
      if (durationSec != null) 'duration_sec': durationSec,
      if (memoId != null) 'memo_id': memoId,
    });
  }

  UtterancesCompanion copyWith({
    Value<int>? id,
    Value<String>? content,
    Value<DateTime>? recognizedAt,
    Value<double>? durationSec,
    Value<int>? memoId,
  }) {
    return UtterancesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      recognizedAt: recognizedAt ?? this.recognizedAt,
      durationSec: durationSec ?? this.durationSec,
      memoId: memoId ?? this.memoId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (recognizedAt.present) {
      map['recognized_at'] = Variable<DateTime>(recognizedAt.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<double>(durationSec.value);
    }
    if (memoId.present) {
      map['memo_id'] = Variable<int>(memoId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UtterancesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('recognizedAt: $recognizedAt, ')
          ..write('durationSec: $durationSec, ')
          ..write('memoId: $memoId')
          ..write(')'))
        .toString();
  }
}

class $MemoEditsTable extends MemoEdits
    with TableInfo<$MemoEditsTable, MemoEdit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoEditsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _beforeTextMeta = const VerificationMeta(
    'beforeText',
  );
  @override
  late final GeneratedColumn<String> beforeText = GeneratedColumn<String>(
    'before_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _afterTextMeta = const VerificationMeta(
    'afterText',
  );
  @override
  late final GeneratedColumn<String> afterText = GeneratedColumn<String>(
    'after_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _editedAtMeta = const VerificationMeta(
    'editedAt',
  );
  @override
  late final GeneratedColumn<DateTime> editedAt = GeneratedColumn<DateTime>(
    'edited_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, beforeText, afterText, editedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memo_edits';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoEdit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('before_text')) {
      context.handle(
        _beforeTextMeta,
        beforeText.isAcceptableOrUnknown(data['before_text']!, _beforeTextMeta),
      );
    } else if (isInserting) {
      context.missing(_beforeTextMeta);
    }
    if (data.containsKey('after_text')) {
      context.handle(
        _afterTextMeta,
        afterText.isAcceptableOrUnknown(data['after_text']!, _afterTextMeta),
      );
    } else if (isInserting) {
      context.missing(_afterTextMeta);
    }
    if (data.containsKey('edited_at')) {
      context.handle(
        _editedAtMeta,
        editedAt.isAcceptableOrUnknown(data['edited_at']!, _editedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_editedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoEdit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoEdit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      beforeText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_text'],
      )!,
      afterText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_text'],
      )!,
      editedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}edited_at'],
      )!,
    );
  }

  @override
  $MemoEditsTable createAlias(String alias) {
    return $MemoEditsTable(attachedDatabase, alias);
  }
}

class MemoEdit extends DataClass implements Insertable<MemoEdit> {
  final int id;
  final String beforeText;
  final String afterText;
  final DateTime editedAt;
  const MemoEdit({
    required this.id,
    required this.beforeText,
    required this.afterText,
    required this.editedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['before_text'] = Variable<String>(beforeText);
    map['after_text'] = Variable<String>(afterText);
    map['edited_at'] = Variable<DateTime>(editedAt);
    return map;
  }

  MemoEditsCompanion toCompanion(bool nullToAbsent) {
    return MemoEditsCompanion(
      id: Value(id),
      beforeText: Value(beforeText),
      afterText: Value(afterText),
      editedAt: Value(editedAt),
    );
  }

  factory MemoEdit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoEdit(
      id: serializer.fromJson<int>(json['id']),
      beforeText: serializer.fromJson<String>(json['beforeText']),
      afterText: serializer.fromJson<String>(json['afterText']),
      editedAt: serializer.fromJson<DateTime>(json['editedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'beforeText': serializer.toJson<String>(beforeText),
      'afterText': serializer.toJson<String>(afterText),
      'editedAt': serializer.toJson<DateTime>(editedAt),
    };
  }

  MemoEdit copyWith({
    int? id,
    String? beforeText,
    String? afterText,
    DateTime? editedAt,
  }) => MemoEdit(
    id: id ?? this.id,
    beforeText: beforeText ?? this.beforeText,
    afterText: afterText ?? this.afterText,
    editedAt: editedAt ?? this.editedAt,
  );
  MemoEdit copyWithCompanion(MemoEditsCompanion data) {
    return MemoEdit(
      id: data.id.present ? data.id.value : this.id,
      beforeText: data.beforeText.present
          ? data.beforeText.value
          : this.beforeText,
      afterText: data.afterText.present ? data.afterText.value : this.afterText,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoEdit(')
          ..write('id: $id, ')
          ..write('beforeText: $beforeText, ')
          ..write('afterText: $afterText, ')
          ..write('editedAt: $editedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, beforeText, afterText, editedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoEdit &&
          other.id == this.id &&
          other.beforeText == this.beforeText &&
          other.afterText == this.afterText &&
          other.editedAt == this.editedAt);
}

class MemoEditsCompanion extends UpdateCompanion<MemoEdit> {
  final Value<int> id;
  final Value<String> beforeText;
  final Value<String> afterText;
  final Value<DateTime> editedAt;
  const MemoEditsCompanion({
    this.id = const Value.absent(),
    this.beforeText = const Value.absent(),
    this.afterText = const Value.absent(),
    this.editedAt = const Value.absent(),
  });
  MemoEditsCompanion.insert({
    this.id = const Value.absent(),
    required String beforeText,
    required String afterText,
    required DateTime editedAt,
  }) : beforeText = Value(beforeText),
       afterText = Value(afterText),
       editedAt = Value(editedAt);
  static Insertable<MemoEdit> custom({
    Expression<int>? id,
    Expression<String>? beforeText,
    Expression<String>? afterText,
    Expression<DateTime>? editedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (beforeText != null) 'before_text': beforeText,
      if (afterText != null) 'after_text': afterText,
      if (editedAt != null) 'edited_at': editedAt,
    });
  }

  MemoEditsCompanion copyWith({
    Value<int>? id,
    Value<String>? beforeText,
    Value<String>? afterText,
    Value<DateTime>? editedAt,
  }) {
    return MemoEditsCompanion(
      id: id ?? this.id,
      beforeText: beforeText ?? this.beforeText,
      afterText: afterText ?? this.afterText,
      editedAt: editedAt ?? this.editedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (beforeText.present) {
      map['before_text'] = Variable<String>(beforeText.value);
    }
    if (afterText.present) {
      map['after_text'] = Variable<String>(afterText.value);
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<DateTime>(editedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoEditsCompanion(')
          ..write('id: $id, ')
          ..write('beforeText: $beforeText, ')
          ..write('afterText: $afterText, ')
          ..write('editedAt: $editedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $VoiceMemosTable voiceMemos = $VoiceMemosTable(this);
  late final $UtterancesTable utterances = $UtterancesTable(this);
  late final $MemoEditsTable memoEdits = $MemoEditsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    voiceMemos,
    utterances,
    memoEdits,
  ];
}

typedef $$VoiceMemosTableCreateCompanionBuilder =
    VoiceMemosCompanion Function({
      Value<int> id,
      required String content,
      required DateTime createdAt,
      Value<int> position,
    });
typedef $$VoiceMemosTableUpdateCompanionBuilder =
    VoiceMemosCompanion Function({
      Value<int> id,
      Value<String> content,
      Value<DateTime> createdAt,
      Value<int> position,
    });

class $$VoiceMemosTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceMemosTable> {
  $$VoiceMemosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoiceMemosTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceMemosTable> {
  $$VoiceMemosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoiceMemosTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceMemosTable> {
  $$VoiceMemosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$VoiceMemosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VoiceMemosTable,
          VoiceMemo,
          $$VoiceMemosTableFilterComposer,
          $$VoiceMemosTableOrderingComposer,
          $$VoiceMemosTableAnnotationComposer,
          $$VoiceMemosTableCreateCompanionBuilder,
          $$VoiceMemosTableUpdateCompanionBuilder,
          (
            VoiceMemo,
            BaseReferences<_$AppDatabase, $VoiceMemosTable, VoiceMemo>,
          ),
          VoiceMemo,
          PrefetchHooks Function()
        > {
  $$VoiceMemosTableTableManager(_$AppDatabase db, $VoiceMemosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceMemosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceMemosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceMemosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => VoiceMemosCompanion(
                id: id,
                content: content,
                createdAt: createdAt,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String content,
                required DateTime createdAt,
                Value<int> position = const Value.absent(),
              }) => VoiceMemosCompanion.insert(
                id: id,
                content: content,
                createdAt: createdAt,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoiceMemosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VoiceMemosTable,
      VoiceMemo,
      $$VoiceMemosTableFilterComposer,
      $$VoiceMemosTableOrderingComposer,
      $$VoiceMemosTableAnnotationComposer,
      $$VoiceMemosTableCreateCompanionBuilder,
      $$VoiceMemosTableUpdateCompanionBuilder,
      (VoiceMemo, BaseReferences<_$AppDatabase, $VoiceMemosTable, VoiceMemo>),
      VoiceMemo,
      PrefetchHooks Function()
    >;
typedef $$UtterancesTableCreateCompanionBuilder =
    UtterancesCompanion Function({
      Value<int> id,
      required String content,
      required DateTime recognizedAt,
      required double durationSec,
      required int memoId,
    });
typedef $$UtterancesTableUpdateCompanionBuilder =
    UtterancesCompanion Function({
      Value<int> id,
      Value<String> content,
      Value<DateTime> recognizedAt,
      Value<double> durationSec,
      Value<int> memoId,
    });

class $$UtterancesTableFilterComposer
    extends Composer<_$AppDatabase, $UtterancesTable> {
  $$UtterancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recognizedAt => $composableBuilder(
    column: $table.recognizedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memoId => $composableBuilder(
    column: $table.memoId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UtterancesTableOrderingComposer
    extends Composer<_$AppDatabase, $UtterancesTable> {
  $$UtterancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recognizedAt => $composableBuilder(
    column: $table.recognizedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memoId => $composableBuilder(
    column: $table.memoId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UtterancesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UtterancesTable> {
  $$UtterancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get recognizedAt => $composableBuilder(
    column: $table.recognizedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get memoId =>
      $composableBuilder(column: $table.memoId, builder: (column) => column);
}

class $$UtterancesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UtterancesTable,
          Utterance,
          $$UtterancesTableFilterComposer,
          $$UtterancesTableOrderingComposer,
          $$UtterancesTableAnnotationComposer,
          $$UtterancesTableCreateCompanionBuilder,
          $$UtterancesTableUpdateCompanionBuilder,
          (
            Utterance,
            BaseReferences<_$AppDatabase, $UtterancesTable, Utterance>,
          ),
          Utterance,
          PrefetchHooks Function()
        > {
  $$UtterancesTableTableManager(_$AppDatabase db, $UtterancesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UtterancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UtterancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UtterancesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> recognizedAt = const Value.absent(),
                Value<double> durationSec = const Value.absent(),
                Value<int> memoId = const Value.absent(),
              }) => UtterancesCompanion(
                id: id,
                content: content,
                recognizedAt: recognizedAt,
                durationSec: durationSec,
                memoId: memoId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String content,
                required DateTime recognizedAt,
                required double durationSec,
                required int memoId,
              }) => UtterancesCompanion.insert(
                id: id,
                content: content,
                recognizedAt: recognizedAt,
                durationSec: durationSec,
                memoId: memoId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UtterancesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UtterancesTable,
      Utterance,
      $$UtterancesTableFilterComposer,
      $$UtterancesTableOrderingComposer,
      $$UtterancesTableAnnotationComposer,
      $$UtterancesTableCreateCompanionBuilder,
      $$UtterancesTableUpdateCompanionBuilder,
      (Utterance, BaseReferences<_$AppDatabase, $UtterancesTable, Utterance>),
      Utterance,
      PrefetchHooks Function()
    >;
typedef $$MemoEditsTableCreateCompanionBuilder =
    MemoEditsCompanion Function({
      Value<int> id,
      required String beforeText,
      required String afterText,
      required DateTime editedAt,
    });
typedef $$MemoEditsTableUpdateCompanionBuilder =
    MemoEditsCompanion Function({
      Value<int> id,
      Value<String> beforeText,
      Value<String> afterText,
      Value<DateTime> editedAt,
    });

class $$MemoEditsTableFilterComposer
    extends Composer<_$AppDatabase, $MemoEditsTable> {
  $$MemoEditsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeText => $composableBuilder(
    column: $table.beforeText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterText => $composableBuilder(
    column: $table.afterText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get editedAt => $composableBuilder(
    column: $table.editedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoEditsTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoEditsTable> {
  $$MemoEditsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeText => $composableBuilder(
    column: $table.beforeText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterText => $composableBuilder(
    column: $table.afterText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get editedAt => $composableBuilder(
    column: $table.editedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoEditsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoEditsTable> {
  $$MemoEditsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get beforeText => $composableBuilder(
    column: $table.beforeText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterText =>
      $composableBuilder(column: $table.afterText, builder: (column) => column);

  GeneratedColumn<DateTime> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);
}

class $$MemoEditsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoEditsTable,
          MemoEdit,
          $$MemoEditsTableFilterComposer,
          $$MemoEditsTableOrderingComposer,
          $$MemoEditsTableAnnotationComposer,
          $$MemoEditsTableCreateCompanionBuilder,
          $$MemoEditsTableUpdateCompanionBuilder,
          (MemoEdit, BaseReferences<_$AppDatabase, $MemoEditsTable, MemoEdit>),
          MemoEdit,
          PrefetchHooks Function()
        > {
  $$MemoEditsTableTableManager(_$AppDatabase db, $MemoEditsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoEditsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoEditsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoEditsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> beforeText = const Value.absent(),
                Value<String> afterText = const Value.absent(),
                Value<DateTime> editedAt = const Value.absent(),
              }) => MemoEditsCompanion(
                id: id,
                beforeText: beforeText,
                afterText: afterText,
                editedAt: editedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String beforeText,
                required String afterText,
                required DateTime editedAt,
              }) => MemoEditsCompanion.insert(
                id: id,
                beforeText: beforeText,
                afterText: afterText,
                editedAt: editedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoEditsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoEditsTable,
      MemoEdit,
      $$MemoEditsTableFilterComposer,
      $$MemoEditsTableOrderingComposer,
      $$MemoEditsTableAnnotationComposer,
      $$MemoEditsTableCreateCompanionBuilder,
      $$MemoEditsTableUpdateCompanionBuilder,
      (MemoEdit, BaseReferences<_$AppDatabase, $MemoEditsTable, MemoEdit>),
      MemoEdit,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$VoiceMemosTableTableManager get voiceMemos =>
      $$VoiceMemosTableTableManager(_db, _db.voiceMemos);
  $$UtterancesTableTableManager get utterances =>
      $$UtterancesTableTableManager(_db, _db.utterances);
  $$MemoEditsTableTableManager get memoEdits =>
      $$MemoEditsTableTableManager(_db, _db.memoEdits);
}
