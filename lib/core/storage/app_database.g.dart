// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class Documents extends Table with TableInfo<Documents, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Documents(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _authorsMeta = const VerificationMeta(
    'authors',
  );
  late final GeneratedColumn<String> authors = GeneratedColumn<String>(
    'authors',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _journalMeta = const VerificationMeta(
    'journal',
  );
  late final GeneratedColumn<String> journal = GeneratedColumn<String>(
    'journal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  late final GeneratedColumn<String> year = GeneratedColumn<String>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _doiMeta = const VerificationMeta('doi');
  late final GeneratedColumn<String> doi = GeneratedColumn<String>(
    'doi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _keywordsMeta = const VerificationMeta(
    'keywords',
  );
  late final GeneratedColumn<String> keywords = GeneratedColumn<String>(
    'keywords',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'contentHash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'addedAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    authors,
    journal,
    year,
    doi,
    keywords,
    contentHash,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Document> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('authors')) {
      context.handle(
        _authorsMeta,
        authors.isAcceptableOrUnknown(data['authors']!, _authorsMeta),
      );
    } else if (isInserting) {
      context.missing(_authorsMeta);
    }
    if (data.containsKey('journal')) {
      context.handle(
        _journalMeta,
        journal.isAcceptableOrUnknown(data['journal']!, _journalMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('doi')) {
      context.handle(
        _doiMeta,
        doi.isAcceptableOrUnknown(data['doi']!, _doiMeta),
      );
    }
    if (data.containsKey('keywords')) {
      context.handle(
        _keywordsMeta,
        keywords.isAcceptableOrUnknown(data['keywords']!, _keywordsMeta),
      );
    } else if (isInserting) {
      context.missing(_keywordsMeta);
    }
    if (data.containsKey('contentHash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['contentHash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('addedAt')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['addedAt']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      authors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authors'],
      )!,
      journal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}year'],
      ),
      doi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doi'],
      ),
      keywords: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}keywords'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contentHash'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}addedAt'],
      )!,
    );
  }

  @override
  Documents createAlias(String alias) {
    return Documents(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Document extends DataClass implements Insertable<Document> {
  final String id;
  final String title;
  final String authors;

  /// JSON array
  final String? journal;
  final String? year;
  final String? doi;
  final String keywords;

  /// JSON array
  final String? contentHash;

  /// NULL = 无文件元数据条目
  final int addedAt;
  const Document({
    required this.id,
    required this.title,
    required this.authors,
    this.journal,
    this.year,
    this.doi,
    required this.keywords,
    this.contentHash,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['authors'] = Variable<String>(authors);
    if (!nullToAbsent || journal != null) {
      map['journal'] = Variable<String>(journal);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<String>(year);
    }
    if (!nullToAbsent || doi != null) {
      map['doi'] = Variable<String>(doi);
    }
    map['keywords'] = Variable<String>(keywords);
    if (!nullToAbsent || contentHash != null) {
      map['contentHash'] = Variable<String>(contentHash);
    }
    map['addedAt'] = Variable<int>(addedAt);
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      title: Value(title),
      authors: Value(authors),
      journal: journal == null && nullToAbsent
          ? const Value.absent()
          : Value(journal),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      doi: doi == null && nullToAbsent ? const Value.absent() : Value(doi),
      keywords: Value(keywords),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      addedAt: Value(addedAt),
    );
  }

  factory Document.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      authors: serializer.fromJson<String>(json['authors']),
      journal: serializer.fromJson<String?>(json['journal']),
      year: serializer.fromJson<String?>(json['year']),
      doi: serializer.fromJson<String?>(json['doi']),
      keywords: serializer.fromJson<String>(json['keywords']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'authors': serializer.toJson<String>(authors),
      'journal': serializer.toJson<String?>(journal),
      'year': serializer.toJson<String?>(year),
      'doi': serializer.toJson<String?>(doi),
      'keywords': serializer.toJson<String>(keywords),
      'contentHash': serializer.toJson<String?>(contentHash),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  Document copyWith({
    String? id,
    String? title,
    String? authors,
    Value<String?> journal = const Value.absent(),
    Value<String?> year = const Value.absent(),
    Value<String?> doi = const Value.absent(),
    String? keywords,
    Value<String?> contentHash = const Value.absent(),
    int? addedAt,
  }) => Document(
    id: id ?? this.id,
    title: title ?? this.title,
    authors: authors ?? this.authors,
    journal: journal.present ? journal.value : this.journal,
    year: year.present ? year.value : this.year,
    doi: doi.present ? doi.value : this.doi,
    keywords: keywords ?? this.keywords,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    addedAt: addedAt ?? this.addedAt,
  );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      authors: data.authors.present ? data.authors.value : this.authors,
      journal: data.journal.present ? data.journal.value : this.journal,
      year: data.year.present ? data.year.value : this.year,
      doi: data.doi.present ? data.doi.value : this.doi,
      keywords: data.keywords.present ? data.keywords.value : this.keywords,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('authors: $authors, ')
          ..write('journal: $journal, ')
          ..write('year: $year, ')
          ..write('doi: $doi, ')
          ..write('keywords: $keywords, ')
          ..write('contentHash: $contentHash, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    authors,
    journal,
    year,
    doi,
    keywords,
    contentHash,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.title == this.title &&
          other.authors == this.authors &&
          other.journal == this.journal &&
          other.year == this.year &&
          other.doi == this.doi &&
          other.keywords == this.keywords &&
          other.contentHash == this.contentHash &&
          other.addedAt == this.addedAt);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> authors;
  final Value<String?> journal;
  final Value<String?> year;
  final Value<String?> doi;
  final Value<String> keywords;
  final Value<String?> contentHash;
  final Value<int> addedAt;
  final Value<int> rowid;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.authors = const Value.absent(),
    this.journal = const Value.absent(),
    this.year = const Value.absent(),
    this.doi = const Value.absent(),
    this.keywords = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentsCompanion.insert({
    required String id,
    required String title,
    required String authors,
    this.journal = const Value.absent(),
    this.year = const Value.absent(),
    this.doi = const Value.absent(),
    required String keywords,
    this.contentHash = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       authors = Value(authors),
       keywords = Value(keywords),
       addedAt = Value(addedAt);
  static Insertable<Document> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? authors,
    Expression<String>? journal,
    Expression<String>? year,
    Expression<String>? doi,
    Expression<String>? keywords,
    Expression<String>? contentHash,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (authors != null) 'authors': authors,
      if (journal != null) 'journal': journal,
      if (year != null) 'year': year,
      if (doi != null) 'doi': doi,
      if (keywords != null) 'keywords': keywords,
      if (contentHash != null) 'contentHash': contentHash,
      if (addedAt != null) 'addedAt': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? authors,
    Value<String?>? journal,
    Value<String?>? year,
    Value<String?>? doi,
    Value<String>? keywords,
    Value<String?>? contentHash,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      journal: journal ?? this.journal,
      year: year ?? this.year,
      doi: doi ?? this.doi,
      keywords: keywords ?? this.keywords,
      contentHash: contentHash ?? this.contentHash,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (authors.present) {
      map['authors'] = Variable<String>(authors.value);
    }
    if (journal.present) {
      map['journal'] = Variable<String>(journal.value);
    }
    if (year.present) {
      map['year'] = Variable<String>(year.value);
    }
    if (doi.present) {
      map['doi'] = Variable<String>(doi.value);
    }
    if (keywords.present) {
      map['keywords'] = Variable<String>(keywords.value);
    }
    if (contentHash.present) {
      map['contentHash'] = Variable<String>(contentHash.value);
    }
    if (addedAt.present) {
      map['addedAt'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('authors: $authors, ')
          ..write('journal: $journal, ')
          ..write('year: $year, ')
          ..write('doi: $doi, ')
          ..write('keywords: $keywords, ')
          ..write('contentHash: $contentHash, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Highlights extends Table with TableInfo<Highlights, Highlight> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Highlights(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'docId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES documents(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'groupId',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'createdAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    docId,
    content,
    note,
    color,
    groupId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'highlights';
  @override
  VerificationContext validateIntegrity(
    Insertable<Highlight> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('docId')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['docId']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('groupId')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['groupId']!, _groupIdMeta),
      );
    }
    if (data.containsKey('createdAt')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['createdAt']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Highlight map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Highlight(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}docId'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}groupId'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}createdAt'],
      )!,
    );
  }

  @override
  Highlights createAlias(String alias) {
    return Highlights(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Highlight extends DataClass implements Insertable<Highlight> {
  final String id;
  final String docId;
  final String content;

  /// 高亮文本（Highlight.text）
  final String? note;
  final String color;
  final String? groupId;
  final int createdAt;
  const Highlight({
    required this.id,
    required this.docId,
    required this.content,
    this.note,
    required this.color,
    this.groupId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['docId'] = Variable<String>(docId);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['color'] = Variable<String>(color);
    if (!nullToAbsent || groupId != null) {
      map['groupId'] = Variable<String>(groupId);
    }
    map['createdAt'] = Variable<int>(createdAt);
    return map;
  }

  HighlightsCompanion toCompanion(bool nullToAbsent) {
    return HighlightsCompanion(
      id: Value(id),
      docId: Value(docId),
      content: Value(content),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      color: Value(color),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      createdAt: Value(createdAt),
    );
  }

  factory Highlight.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Highlight(
      id: serializer.fromJson<String>(json['id']),
      docId: serializer.fromJson<String>(json['docId']),
      content: serializer.fromJson<String>(json['content']),
      note: serializer.fromJson<String?>(json['note']),
      color: serializer.fromJson<String>(json['color']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'docId': serializer.toJson<String>(docId),
      'content': serializer.toJson<String>(content),
      'note': serializer.toJson<String?>(note),
      'color': serializer.toJson<String>(color),
      'groupId': serializer.toJson<String?>(groupId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Highlight copyWith({
    String? id,
    String? docId,
    String? content,
    Value<String?> note = const Value.absent(),
    String? color,
    Value<String?> groupId = const Value.absent(),
    int? createdAt,
  }) => Highlight(
    id: id ?? this.id,
    docId: docId ?? this.docId,
    content: content ?? this.content,
    note: note.present ? note.value : this.note,
    color: color ?? this.color,
    groupId: groupId.present ? groupId.value : this.groupId,
    createdAt: createdAt ?? this.createdAt,
  );
  Highlight copyWithCompanion(HighlightsCompanion data) {
    return Highlight(
      id: data.id.present ? data.id.value : this.id,
      docId: data.docId.present ? data.docId.value : this.docId,
      content: data.content.present ? data.content.value : this.content,
      note: data.note.present ? data.note.value : this.note,
      color: data.color.present ? data.color.value : this.color,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Highlight(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('content: $content, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, docId, content, note, color, groupId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Highlight &&
          other.id == this.id &&
          other.docId == this.docId &&
          other.content == this.content &&
          other.note == this.note &&
          other.color == this.color &&
          other.groupId == this.groupId &&
          other.createdAt == this.createdAt);
}

class HighlightsCompanion extends UpdateCompanion<Highlight> {
  final Value<String> id;
  final Value<String> docId;
  final Value<String> content;
  final Value<String?> note;
  final Value<String> color;
  final Value<String?> groupId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const HighlightsCompanion({
    this.id = const Value.absent(),
    this.docId = const Value.absent(),
    this.content = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.groupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HighlightsCompanion.insert({
    required String id,
    required String docId,
    required String content,
    this.note = const Value.absent(),
    required String color,
    this.groupId = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       docId = Value(docId),
       content = Value(content),
       color = Value(color),
       createdAt = Value(createdAt);
  static Insertable<Highlight> custom({
    Expression<String>? id,
    Expression<String>? docId,
    Expression<String>? content,
    Expression<String>? note,
    Expression<String>? color,
    Expression<String>? groupId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (docId != null) 'docId': docId,
      if (content != null) 'content': content,
      if (note != null) 'note': note,
      if (color != null) 'color': color,
      if (groupId != null) 'groupId': groupId,
      if (createdAt != null) 'createdAt': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HighlightsCompanion copyWith({
    Value<String>? id,
    Value<String>? docId,
    Value<String>? content,
    Value<String?>? note,
    Value<String>? color,
    Value<String?>? groupId,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return HighlightsCompanion(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      content: content ?? this.content,
      note: note ?? this.note,
      color: color ?? this.color,
      groupId: groupId ?? this.groupId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (docId.present) {
      map['docId'] = Variable<String>(docId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (groupId.present) {
      map['groupId'] = Variable<String>(groupId.value);
    }
    if (createdAt.present) {
      map['createdAt'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HighlightsCompanion(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('content: $content, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class History extends Table with TableInfo<History, HistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  History(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'docId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES documents(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  late final GeneratedColumn<int> openedAt = GeneratedColumn<int>(
    'openedAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _anchorBlockMeta = const VerificationMeta(
    'anchorBlock',
  );
  late final GeneratedColumn<int> anchorBlock = GeneratedColumn<int>(
    'anchorBlock',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    docId,
    openedAt,
    progress,
    anchorBlock,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('docId')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['docId']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('openedAt')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['openedAt']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('anchorBlock')) {
      context.handle(
        _anchorBlockMeta,
        anchorBlock.isAcceptableOrUnknown(
          data['anchorBlock']!,
          _anchorBlockMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {docId};
  @override
  HistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryData(
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}docId'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}openedAt'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      anchorBlock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anchorBlock'],
      ),
    );
  }

  @override
  History createAlias(String alias) {
    return History(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class HistoryData extends DataClass implements Insertable<HistoryData> {
  final String docId;

  /// unique = bubble 语义
  final int openedAt;
  final double progress;
  final int? anchorBlock;
  const HistoryData({
    required this.docId,
    required this.openedAt,
    required this.progress,
    this.anchorBlock,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['docId'] = Variable<String>(docId);
    map['openedAt'] = Variable<int>(openedAt);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || anchorBlock != null) {
      map['anchorBlock'] = Variable<int>(anchorBlock);
    }
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      docId: Value(docId),
      openedAt: Value(openedAt),
      progress: Value(progress),
      anchorBlock: anchorBlock == null && nullToAbsent
          ? const Value.absent()
          : Value(anchorBlock),
    );
  }

  factory HistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryData(
      docId: serializer.fromJson<String>(json['docId']),
      openedAt: serializer.fromJson<int>(json['openedAt']),
      progress: serializer.fromJson<double>(json['progress']),
      anchorBlock: serializer.fromJson<int?>(json['anchorBlock']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'docId': serializer.toJson<String>(docId),
      'openedAt': serializer.toJson<int>(openedAt),
      'progress': serializer.toJson<double>(progress),
      'anchorBlock': serializer.toJson<int?>(anchorBlock),
    };
  }

  HistoryData copyWith({
    String? docId,
    int? openedAt,
    double? progress,
    Value<int?> anchorBlock = const Value.absent(),
  }) => HistoryData(
    docId: docId ?? this.docId,
    openedAt: openedAt ?? this.openedAt,
    progress: progress ?? this.progress,
    anchorBlock: anchorBlock.present ? anchorBlock.value : this.anchorBlock,
  );
  HistoryData copyWithCompanion(HistoryCompanion data) {
    return HistoryData(
      docId: data.docId.present ? data.docId.value : this.docId,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      progress: data.progress.present ? data.progress.value : this.progress,
      anchorBlock: data.anchorBlock.present
          ? data.anchorBlock.value
          : this.anchorBlock,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryData(')
          ..write('docId: $docId, ')
          ..write('openedAt: $openedAt, ')
          ..write('progress: $progress, ')
          ..write('anchorBlock: $anchorBlock')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(docId, openedAt, progress, anchorBlock);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryData &&
          other.docId == this.docId &&
          other.openedAt == this.openedAt &&
          other.progress == this.progress &&
          other.anchorBlock == this.anchorBlock);
}

class HistoryCompanion extends UpdateCompanion<HistoryData> {
  final Value<String> docId;
  final Value<int> openedAt;
  final Value<double> progress;
  final Value<int?> anchorBlock;
  final Value<int> rowid;
  const HistoryCompanion({
    this.docId = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.progress = const Value.absent(),
    this.anchorBlock = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryCompanion.insert({
    required String docId,
    required int openedAt,
    this.progress = const Value.absent(),
    this.anchorBlock = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docId = Value(docId),
       openedAt = Value(openedAt);
  static Insertable<HistoryData> custom({
    Expression<String>? docId,
    Expression<int>? openedAt,
    Expression<double>? progress,
    Expression<int>? anchorBlock,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (docId != null) 'docId': docId,
      if (openedAt != null) 'openedAt': openedAt,
      if (progress != null) 'progress': progress,
      if (anchorBlock != null) 'anchorBlock': anchorBlock,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryCompanion copyWith({
    Value<String>? docId,
    Value<int>? openedAt,
    Value<double>? progress,
    Value<int?>? anchorBlock,
    Value<int>? rowid,
  }) {
    return HistoryCompanion(
      docId: docId ?? this.docId,
      openedAt: openedAt ?? this.openedAt,
      progress: progress ?? this.progress,
      anchorBlock: anchorBlock ?? this.anchorBlock,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (docId.present) {
      map['docId'] = Variable<String>(docId.value);
    }
    if (openedAt.present) {
      map['openedAt'] = Variable<int>(openedAt.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (anchorBlock.present) {
      map['anchorBlock'] = Variable<int>(anchorBlock.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryCompanion(')
          ..write('docId: $docId, ')
          ..write('openedAt: $openedAt, ')
          ..write('progress: $progress, ')
          ..write('anchorBlock: $anchorBlock, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Favorites extends Table with TableInfo<Favorites, Favorite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Favorites(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'createdAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, emoji, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<Favorite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('createdAt')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['createdAt']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Favorite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favorite(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}createdAt'],
      )!,
    );
  }

  @override
  Favorites createAlias(String alias) {
    return Favorites(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Favorite extends DataClass implements Insertable<Favorite> {
  final String id;

  /// '_default_' = 默认收藏夹（派生 isDefault）
  final String emoji;
  final String name;
  final int createdAt;
  const Favorite({
    required this.id,
    required this.emoji,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['emoji'] = Variable<String>(emoji);
    map['name'] = Variable<String>(name);
    map['createdAt'] = Variable<int>(createdAt);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      id: Value(id),
      emoji: Value(emoji),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Favorite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favorite(
      id: serializer.fromJson<String>(json['id']),
      emoji: serializer.fromJson<String>(json['emoji']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'emoji': serializer.toJson<String>(emoji),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Favorite copyWith({
    String? id,
    String? emoji,
    String? name,
    int? createdAt,
  }) => Favorite(
    id: id ?? this.id,
    emoji: emoji ?? this.emoji,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Favorite copyWithCompanion(FavoritesCompanion data) {
    return Favorite(
      id: data.id.present ? data.id.value : this.id,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favorite(')
          ..write('id: $id, ')
          ..write('emoji: $emoji, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, emoji, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favorite &&
          other.id == this.id &&
          other.emoji == this.emoji &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<String> id;
  final Value<String> emoji;
  final Value<String> name;
  final Value<int> createdAt;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.id = const Value.absent(),
    this.emoji = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String id,
    required String emoji,
    required String name,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       emoji = Value(emoji),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Favorite> custom({
    Expression<String>? id,
    Expression<String>? emoji,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (emoji != null) 'emoji': emoji,
      if (name != null) 'name': name,
      if (createdAt != null) 'createdAt': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<String>? id,
    Value<String>? emoji,
    Value<String>? name,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      id: id ?? this.id,
      emoji: emoji ?? this.emoji,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['createdAt'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('id: $id, ')
          ..write('emoji: $emoji, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class FavoriteDocuments extends Table
    with TableInfo<FavoriteDocuments, FavoriteDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FavoriteDocuments(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _favoriteIdMeta = const VerificationMeta(
    'favoriteId',
  );
  late final GeneratedColumn<String> favoriteId = GeneratedColumn<String>(
    'favoriteId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES favorites(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'docId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES documents(id)ON DELETE CASCADE',
  );
  @override
  List<GeneratedColumn> get $columns => [favoriteId, docId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('favoriteId')) {
      context.handle(
        _favoriteIdMeta,
        favoriteId.isAcceptableOrUnknown(data['favoriteId']!, _favoriteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_favoriteIdMeta);
    }
    if (data.containsKey('docId')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['docId']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {favoriteId, docId};
  @override
  FavoriteDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteDocument(
      favoriteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}favoriteId'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}docId'],
      )!,
    );
  }

  @override
  FavoriteDocuments createAlias(String alias) {
    return FavoriteDocuments(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(favoriteId, docId)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class FavoriteDocument extends DataClass
    implements Insertable<FavoriteDocument> {
  final String favoriteId;
  final String docId;
  const FavoriteDocument({required this.favoriteId, required this.docId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['favoriteId'] = Variable<String>(favoriteId);
    map['docId'] = Variable<String>(docId);
    return map;
  }

  FavoriteDocumentsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteDocumentsCompanion(
      favoriteId: Value(favoriteId),
      docId: Value(docId),
    );
  }

  factory FavoriteDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteDocument(
      favoriteId: serializer.fromJson<String>(json['favoriteId']),
      docId: serializer.fromJson<String>(json['docId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'favoriteId': serializer.toJson<String>(favoriteId),
      'docId': serializer.toJson<String>(docId),
    };
  }

  FavoriteDocument copyWith({String? favoriteId, String? docId}) =>
      FavoriteDocument(
        favoriteId: favoriteId ?? this.favoriteId,
        docId: docId ?? this.docId,
      );
  FavoriteDocument copyWithCompanion(FavoriteDocumentsCompanion data) {
    return FavoriteDocument(
      favoriteId: data.favoriteId.present
          ? data.favoriteId.value
          : this.favoriteId,
      docId: data.docId.present ? data.docId.value : this.docId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteDocument(')
          ..write('favoriteId: $favoriteId, ')
          ..write('docId: $docId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(favoriteId, docId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteDocument &&
          other.favoriteId == this.favoriteId &&
          other.docId == this.docId);
}

class FavoriteDocumentsCompanion extends UpdateCompanion<FavoriteDocument> {
  final Value<String> favoriteId;
  final Value<String> docId;
  final Value<int> rowid;
  const FavoriteDocumentsCompanion({
    this.favoriteId = const Value.absent(),
    this.docId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteDocumentsCompanion.insert({
    required String favoriteId,
    required String docId,
    this.rowid = const Value.absent(),
  }) : favoriteId = Value(favoriteId),
       docId = Value(docId);
  static Insertable<FavoriteDocument> custom({
    Expression<String>? favoriteId,
    Expression<String>? docId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (favoriteId != null) 'favoriteId': favoriteId,
      if (docId != null) 'docId': docId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteDocumentsCompanion copyWith({
    Value<String>? favoriteId,
    Value<String>? docId,
    Value<int>? rowid,
  }) {
    return FavoriteDocumentsCompanion(
      favoriteId: favoriteId ?? this.favoriteId,
      docId: docId ?? this.docId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (favoriteId.present) {
      map['favoriteId'] = Variable<String>(favoriteId.value);
    }
    if (docId.present) {
      map['docId'] = Variable<String>(docId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteDocumentsCompanion(')
          ..write('favoriteId: $favoriteId, ')
          ..write('docId: $docId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ZoteroItems extends Table with TableInfo<ZoteroItems, ZoteroItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ZoteroItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _zoteroKeyMeta = const VerificationMeta(
    'zoteroKey',
  );
  late final GeneratedColumn<String> zoteroKey = GeneratedColumn<String>(
    'zoteroKey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'docId',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES documents(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [zoteroKey, docId, version];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'zotero_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ZoteroItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('zoteroKey')) {
      context.handle(
        _zoteroKeyMeta,
        zoteroKey.isAcceptableOrUnknown(data['zoteroKey']!, _zoteroKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_zoteroKeyMeta);
    }
    if (data.containsKey('docId')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['docId']!, _docIdMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {zoteroKey};
  @override
  ZoteroItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ZoteroItem(
      zoteroKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zoteroKey'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}docId'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  ZoteroItems createAlias(String alias) {
    return ZoteroItems(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class ZoteroItem extends DataClass implements Insertable<ZoteroItem> {
  final String zoteroKey;
  final String? docId;
  final int version;
  const ZoteroItem({
    required this.zoteroKey,
    this.docId,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['zoteroKey'] = Variable<String>(zoteroKey);
    if (!nullToAbsent || docId != null) {
      map['docId'] = Variable<String>(docId);
    }
    map['version'] = Variable<int>(version);
    return map;
  }

  ZoteroItemsCompanion toCompanion(bool nullToAbsent) {
    return ZoteroItemsCompanion(
      zoteroKey: Value(zoteroKey),
      docId: docId == null && nullToAbsent
          ? const Value.absent()
          : Value(docId),
      version: Value(version),
    );
  }

  factory ZoteroItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ZoteroItem(
      zoteroKey: serializer.fromJson<String>(json['zoteroKey']),
      docId: serializer.fromJson<String?>(json['docId']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'zoteroKey': serializer.toJson<String>(zoteroKey),
      'docId': serializer.toJson<String?>(docId),
      'version': serializer.toJson<int>(version),
    };
  }

  ZoteroItem copyWith({
    String? zoteroKey,
    Value<String?> docId = const Value.absent(),
    int? version,
  }) => ZoteroItem(
    zoteroKey: zoteroKey ?? this.zoteroKey,
    docId: docId.present ? docId.value : this.docId,
    version: version ?? this.version,
  );
  ZoteroItem copyWithCompanion(ZoteroItemsCompanion data) {
    return ZoteroItem(
      zoteroKey: data.zoteroKey.present ? data.zoteroKey.value : this.zoteroKey,
      docId: data.docId.present ? data.docId.value : this.docId,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ZoteroItem(')
          ..write('zoteroKey: $zoteroKey, ')
          ..write('docId: $docId, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(zoteroKey, docId, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ZoteroItem &&
          other.zoteroKey == this.zoteroKey &&
          other.docId == this.docId &&
          other.version == this.version);
}

class ZoteroItemsCompanion extends UpdateCompanion<ZoteroItem> {
  final Value<String> zoteroKey;
  final Value<String?> docId;
  final Value<int> version;
  final Value<int> rowid;
  const ZoteroItemsCompanion({
    this.zoteroKey = const Value.absent(),
    this.docId = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ZoteroItemsCompanion.insert({
    required String zoteroKey,
    this.docId = const Value.absent(),
    required int version,
    this.rowid = const Value.absent(),
  }) : zoteroKey = Value(zoteroKey),
       version = Value(version);
  static Insertable<ZoteroItem> custom({
    Expression<String>? zoteroKey,
    Expression<String>? docId,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (zoteroKey != null) 'zoteroKey': zoteroKey,
      if (docId != null) 'docId': docId,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ZoteroItemsCompanion copyWith({
    Value<String>? zoteroKey,
    Value<String?>? docId,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return ZoteroItemsCompanion(
      zoteroKey: zoteroKey ?? this.zoteroKey,
      docId: docId ?? this.docId,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (zoteroKey.present) {
      map['zoteroKey'] = Variable<String>(zoteroKey.value);
    }
    if (docId.present) {
      map['docId'] = Variable<String>(docId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ZoteroItemsCompanion(')
          ..write('zoteroKey: $zoteroKey, ')
          ..write('docId: $docId, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Settings extends Table with TableInfo<Settings, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _settingKeyMeta = const VerificationMeta(
    'settingKey',
  );
  late final GeneratedColumn<String> settingKey = GeneratedColumn<String>(
    'settingKey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [settingKey, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('settingKey')) {
      context.handle(
        _settingKeyMeta,
        settingKey.isAcceptableOrUnknown(data['settingKey']!, _settingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_settingKeyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {settingKey};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      settingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settingKey'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Setting extends DataClass implements Insertable<Setting> {
  final String settingKey;
  final String value;
  const Setting({required this.settingKey, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['settingKey'] = Variable<String>(settingKey);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      settingKey: Value(settingKey),
      value: Value(value),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      settingKey: serializer.fromJson<String>(json['settingKey']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'settingKey': serializer.toJson<String>(settingKey),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? settingKey, String? value}) => Setting(
    settingKey: settingKey ?? this.settingKey,
    value: value ?? this.value,
  );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      settingKey: data.settingKey.present
          ? data.settingKey.value
          : this.settingKey,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('settingKey: $settingKey, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(settingKey, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.settingKey == this.settingKey &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> settingKey;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.settingKey = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String settingKey,
    required String value,
    this.rowid = const Value.absent(),
  }) : settingKey = Value(settingKey),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? settingKey,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (settingKey != null) 'settingKey': settingKey,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? settingKey,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      settingKey: settingKey ?? this.settingKey,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (settingKey.present) {
      map['settingKey'] = Variable<String>(settingKey.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('settingKey: $settingKey, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Meta extends Table with TableInfo<Meta, MetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Meta(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _metaKeyMeta = const VerificationMeta(
    'metaKey',
  );
  late final GeneratedColumn<String> metaKey = GeneratedColumn<String>(
    'metaKey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [metaKey, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('metaKey')) {
      context.handle(
        _metaKeyMeta,
        metaKey.isAcceptableOrUnknown(data['metaKey']!, _metaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_metaKeyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {metaKey};
  @override
  MetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaData(
      metaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metaKey'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  Meta createAlias(String alias) {
    return Meta(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class MetaData extends DataClass implements Insertable<MetaData> {
  final String metaKey;
  final String value;
  const MetaData({required this.metaKey, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['metaKey'] = Variable<String>(metaKey);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(metaKey: Value(metaKey), value: Value(value));
  }

  factory MetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaData(
      metaKey: serializer.fromJson<String>(json['metaKey']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'metaKey': serializer.toJson<String>(metaKey),
      'value': serializer.toJson<String>(value),
    };
  }

  MetaData copyWith({String? metaKey, String? value}) =>
      MetaData(metaKey: metaKey ?? this.metaKey, value: value ?? this.value);
  MetaData copyWithCompanion(MetaCompanion data) {
    return MetaData(
      metaKey: data.metaKey.present ? data.metaKey.value : this.metaKey,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaData(')
          ..write('metaKey: $metaKey, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(metaKey, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaData &&
          other.metaKey == this.metaKey &&
          other.value == this.value);
}

class MetaCompanion extends UpdateCompanion<MetaData> {
  final Value<String> metaKey;
  final Value<String> value;
  final Value<int> rowid;
  const MetaCompanion({
    this.metaKey = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String metaKey,
    required String value,
    this.rowid = const Value.absent(),
  }) : metaKey = Value(metaKey),
       value = Value(value);
  static Insertable<MetaData> custom({
    Expression<String>? metaKey,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (metaKey != null) 'metaKey': metaKey,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith({
    Value<String>? metaKey,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return MetaCompanion(
      metaKey: metaKey ?? this.metaKey,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (metaKey.present) {
      map['metaKey'] = Variable<String>(metaKey.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('metaKey: $metaKey, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Translations extends Table with TableInfo<Translations, Translation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Translations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cacheKey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _translationMeta = const VerificationMeta(
    'translation',
  );
  late final GeneratedColumn<String> translation = GeneratedColumn<String>(
    'translation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'createdAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [cacheKey, translation, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'translations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Translation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cacheKey')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cacheKey']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('translation')) {
      context.handle(
        _translationMeta,
        translation.isAcceptableOrUnknown(
          data['translation']!,
          _translationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_translationMeta);
    }
    if (data.containsKey('createdAt')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['createdAt']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  Translation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Translation(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cacheKey'],
      )!,
      translation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}translation'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}createdAt'],
      )!,
    );
  }

  @override
  Translations createAlias(String alias) {
    return Translations(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Translation extends DataClass implements Insertable<Translation> {
  final String cacheKey;
  final String translation;
  final int createdAt;
  const Translation({
    required this.cacheKey,
    required this.translation,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cacheKey'] = Variable<String>(cacheKey);
    map['translation'] = Variable<String>(translation);
    map['createdAt'] = Variable<int>(createdAt);
    return map;
  }

  TranslationsCompanion toCompanion(bool nullToAbsent) {
    return TranslationsCompanion(
      cacheKey: Value(cacheKey),
      translation: Value(translation),
      createdAt: Value(createdAt),
    );
  }

  factory Translation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Translation(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      translation: serializer.fromJson<String>(json['translation']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'translation': serializer.toJson<String>(translation),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Translation copyWith({
    String? cacheKey,
    String? translation,
    int? createdAt,
  }) => Translation(
    cacheKey: cacheKey ?? this.cacheKey,
    translation: translation ?? this.translation,
    createdAt: createdAt ?? this.createdAt,
  );
  Translation copyWithCompanion(TranslationsCompanion data) {
    return Translation(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      translation: data.translation.present
          ? data.translation.value
          : this.translation,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Translation(')
          ..write('cacheKey: $cacheKey, ')
          ..write('translation: $translation, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cacheKey, translation, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Translation &&
          other.cacheKey == this.cacheKey &&
          other.translation == this.translation &&
          other.createdAt == this.createdAt);
}

class TranslationsCompanion extends UpdateCompanion<Translation> {
  final Value<String> cacheKey;
  final Value<String> translation;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TranslationsCompanion({
    this.cacheKey = const Value.absent(),
    this.translation = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TranslationsCompanion.insert({
    required String cacheKey,
    required String translation,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       translation = Value(translation),
       createdAt = Value(createdAt);
  static Insertable<Translation> custom({
    Expression<String>? cacheKey,
    Expression<String>? translation,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cacheKey': cacheKey,
      if (translation != null) 'translation': translation,
      if (createdAt != null) 'createdAt': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TranslationsCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? translation,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return TranslationsCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      translation: translation ?? this.translation,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cacheKey'] = Variable<String>(cacheKey.value);
    }
    if (translation.present) {
      map['translation'] = Variable<String>(translation.value);
    }
    if (createdAt.present) {
      map['createdAt'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TranslationsCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('translation: $translation, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final Documents documents = Documents(this);
  late final Index idxDocumentsContentHash = Index(
    'idx_documents_contentHash',
    'CREATE UNIQUE INDEX idx_documents_contentHash ON documents (contentHash) WHERE contentHash IS NOT NULL',
  );
  late final Index idxDocumentsDoi = Index(
    'idx_documents_doi',
    'CREATE INDEX idx_documents_doi ON documents (doi)',
  );
  late final Index idxDocumentsAddedAt = Index(
    'idx_documents_addedAt',
    'CREATE INDEX idx_documents_addedAt ON documents (addedAt)',
  );
  late final Highlights highlights = Highlights(this);
  late final Index idxHighlightsDocId = Index(
    'idx_highlights_docId',
    'CREATE INDEX idx_highlights_docId ON highlights (docId)',
  );
  late final History history = History(this);
  late final Favorites favorites = Favorites(this);
  late final FavoriteDocuments favoriteDocuments = FavoriteDocuments(this);
  late final ZoteroItems zoteroItems = ZoteroItems(this);
  late final Index idxZoteroItemsDocId = Index(
    'idx_zotero_items_docId',
    'CREATE INDEX idx_zotero_items_docId ON zotero_items (docId)',
  );
  late final Settings settings = Settings(this);
  late final Meta meta = Meta(this);
  late final Translations translations = Translations(this);
  late final Index idxTranslationsCreatedAt = Index(
    'idx_translations_createdAt',
    'CREATE INDEX idx_translations_createdAt ON translations (createdAt)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    documents,
    idxDocumentsContentHash,
    idxDocumentsDoi,
    idxDocumentsAddedAt,
    highlights,
    idxHighlightsDocId,
    history,
    favorites,
    favoriteDocuments,
    zoteroItems,
    idxZoteroItemsDocId,
    settings,
    meta,
    translations,
    idxTranslationsCreatedAt,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('highlights', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('history', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'favorites',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('favorite_documents', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('favorite_documents', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('zotero_items', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $DocumentsCreateCompanionBuilder =
    DocumentsCompanion Function({
      required String id,
      required String title,
      required String authors,
      Value<String?> journal,
      Value<String?> year,
      Value<String?> doi,
      required String keywords,
      Value<String?> contentHash,
      required int addedAt,
      Value<int> rowid,
    });
typedef $DocumentsUpdateCompanionBuilder =
    DocumentsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> authors,
      Value<String?> journal,
      Value<String?> year,
      Value<String?> doi,
      Value<String> keywords,
      Value<String?> contentHash,
      Value<int> addedAt,
      Value<int> rowid,
    });

final class $DocumentsReferences
    extends BaseReferences<_$AppDatabase, Documents, Document> {
  $DocumentsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Highlights, List<Highlight>> _highlightsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.highlights,
    aliasName: 'documents__id__highlights__docId',
  );

  $HighlightsProcessedTableManager get highlightsRefs {
    final manager = $HighlightsTableManager(
      $_db,
      $_db.highlights,
    ).filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_highlightsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<History, List<HistoryData>> _historyRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.history,
    aliasName: 'documents__id__history__docId',
  );

  $HistoryProcessedTableManager get historyRefs {
    final manager = $HistoryTableManager(
      $_db,
      $_db.history,
    ).filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_historyRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<FavoriteDocuments, List<FavoriteDocument>>
  _favoriteDocumentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.favoriteDocuments,
        aliasName: 'documents__id__favorite_documents__docId',
      );

  $FavoriteDocumentsProcessedTableManager get favoriteDocumentsRefs {
    final manager = $FavoriteDocumentsTableManager(
      $_db,
      $_db.favoriteDocuments,
    ).filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _favoriteDocumentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<ZoteroItems, List<ZoteroItem>>
  _zoteroItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.zoteroItems,
    aliasName: 'documents__id__zotero_items__docId',
  );

  $ZoteroItemsProcessedTableManager get zoteroItemsRefs {
    final manager = $ZoteroItemsTableManager(
      $_db,
      $_db.zoteroItems,
    ).filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_zoteroItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $DocumentsFilterComposer extends Composer<_$AppDatabase, Documents> {
  $DocumentsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authors => $composableBuilder(
    column: $table.authors,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get journal => $composableBuilder(
    column: $table.journal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get doi => $composableBuilder(
    column: $table.doi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keywords => $composableBuilder(
    column: $table.keywords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> highlightsRefs(
    Expression<bool> Function($HighlightsFilterComposer f) f,
  ) {
    final $HighlightsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.highlights,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $HighlightsFilterComposer(
            $db: $db,
            $table: $db.highlights,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> historyRefs(
    Expression<bool> Function($HistoryFilterComposer f) f,
  ) {
    final $HistoryFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.history,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $HistoryFilterComposer(
            $db: $db,
            $table: $db.history,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> favoriteDocumentsRefs(
    Expression<bool> Function($FavoriteDocumentsFilterComposer f) f,
  ) {
    final $FavoriteDocumentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.favoriteDocuments,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoriteDocumentsFilterComposer(
            $db: $db,
            $table: $db.favoriteDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> zoteroItemsRefs(
    Expression<bool> Function($ZoteroItemsFilterComposer f) f,
  ) {
    final $ZoteroItemsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.zoteroItems,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ZoteroItemsFilterComposer(
            $db: $db,
            $table: $db.zoteroItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $DocumentsOrderingComposer extends Composer<_$AppDatabase, Documents> {
  $DocumentsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authors => $composableBuilder(
    column: $table.authors,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get journal => $composableBuilder(
    column: $table.journal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get doi => $composableBuilder(
    column: $table.doi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keywords => $composableBuilder(
    column: $table.keywords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $DocumentsAnnotationComposer extends Composer<_$AppDatabase, Documents> {
  $DocumentsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get authors =>
      $composableBuilder(column: $table.authors, builder: (column) => column);

  GeneratedColumn<String> get journal =>
      $composableBuilder(column: $table.journal, builder: (column) => column);

  GeneratedColumn<String> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get doi =>
      $composableBuilder(column: $table.doi, builder: (column) => column);

  GeneratedColumn<String> get keywords =>
      $composableBuilder(column: $table.keywords, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  Expression<T> highlightsRefs<T extends Object>(
    Expression<T> Function($HighlightsAnnotationComposer a) f,
  ) {
    final $HighlightsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.highlights,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $HighlightsAnnotationComposer(
            $db: $db,
            $table: $db.highlights,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> historyRefs<T extends Object>(
    Expression<T> Function($HistoryAnnotationComposer a) f,
  ) {
    final $HistoryAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.history,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $HistoryAnnotationComposer(
            $db: $db,
            $table: $db.history,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> favoriteDocumentsRefs<T extends Object>(
    Expression<T> Function($FavoriteDocumentsAnnotationComposer a) f,
  ) {
    final $FavoriteDocumentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.favoriteDocuments,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoriteDocumentsAnnotationComposer(
            $db: $db,
            $table: $db.favoriteDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> zoteroItemsRefs<T extends Object>(
    Expression<T> Function($ZoteroItemsAnnotationComposer a) f,
  ) {
    final $ZoteroItemsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.zoteroItems,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ZoteroItemsAnnotationComposer(
            $db: $db,
            $table: $db.zoteroItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $DocumentsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Documents,
          Document,
          $DocumentsFilterComposer,
          $DocumentsOrderingComposer,
          $DocumentsAnnotationComposer,
          $DocumentsCreateCompanionBuilder,
          $DocumentsUpdateCompanionBuilder,
          (Document, $DocumentsReferences),
          Document,
          PrefetchHooks Function({
            bool highlightsRefs,
            bool historyRefs,
            bool favoriteDocumentsRefs,
            bool zoteroItemsRefs,
          })
        > {
  $DocumentsTableManager(_$AppDatabase db, Documents table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $DocumentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $DocumentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $DocumentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> authors = const Value.absent(),
                Value<String?> journal = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> doi = const Value.absent(),
                Value<String> keywords = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                title: title,
                authors: authors,
                journal: journal,
                year: year,
                doi: doi,
                keywords: keywords,
                contentHash: contentHash,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String authors,
                Value<String?> journal = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> doi = const Value.absent(),
                required String keywords,
                Value<String?> contentHash = const Value.absent(),
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                title: title,
                authors: authors,
                journal: journal,
                year: year,
                doi: doi,
                keywords: keywords,
                contentHash: contentHash,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), $DocumentsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                highlightsRefs = false,
                historyRefs = false,
                favoriteDocumentsRefs = false,
                zoteroItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (highlightsRefs) db.highlights,
                    if (historyRefs) db.history,
                    if (favoriteDocumentsRefs) db.favoriteDocuments,
                    if (zoteroItemsRefs) db.zoteroItems,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (highlightsRefs)
                        await $_getPrefetchedData<
                          Document,
                          Documents,
                          Highlight
                        >(
                          currentTable: table,
                          referencedTable: $DocumentsReferences
                              ._highlightsRefsTable(db),
                          managerFromTypedResult: (p0) => $DocumentsReferences(
                            db,
                            table,
                            p0,
                          ).highlightsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.docId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (historyRefs)
                        await $_getPrefetchedData<
                          Document,
                          Documents,
                          HistoryData
                        >(
                          currentTable: table,
                          referencedTable: $DocumentsReferences
                              ._historyRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $DocumentsReferences(db, table, p0).historyRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.docId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (favoriteDocumentsRefs)
                        await $_getPrefetchedData<
                          Document,
                          Documents,
                          FavoriteDocument
                        >(
                          currentTable: table,
                          referencedTable: $DocumentsReferences
                              ._favoriteDocumentsRefsTable(db),
                          managerFromTypedResult: (p0) => $DocumentsReferences(
                            db,
                            table,
                            p0,
                          ).favoriteDocumentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.docId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (zoteroItemsRefs)
                        await $_getPrefetchedData<
                          Document,
                          Documents,
                          ZoteroItem
                        >(
                          currentTable: table,
                          referencedTable: $DocumentsReferences
                              ._zoteroItemsRefsTable(db),
                          managerFromTypedResult: (p0) => $DocumentsReferences(
                            db,
                            table,
                            p0,
                          ).zoteroItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.docId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $DocumentsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Documents,
      Document,
      $DocumentsFilterComposer,
      $DocumentsOrderingComposer,
      $DocumentsAnnotationComposer,
      $DocumentsCreateCompanionBuilder,
      $DocumentsUpdateCompanionBuilder,
      (Document, $DocumentsReferences),
      Document,
      PrefetchHooks Function({
        bool highlightsRefs,
        bool historyRefs,
        bool favoriteDocumentsRefs,
        bool zoteroItemsRefs,
      })
    >;
typedef $HighlightsCreateCompanionBuilder =
    HighlightsCompanion Function({
      required String id,
      required String docId,
      required String content,
      Value<String?> note,
      required String color,
      Value<String?> groupId,
      required int createdAt,
      Value<int> rowid,
    });
typedef $HighlightsUpdateCompanionBuilder =
    HighlightsCompanion Function({
      Value<String> id,
      Value<String> docId,
      Value<String> content,
      Value<String?> note,
      Value<String> color,
      Value<String?> groupId,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $HighlightsReferences
    extends BaseReferences<_$AppDatabase, Highlights, Highlight> {
  $HighlightsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Documents _docIdTable(_$AppDatabase db) =>
      db.documents.createAlias('highlights__docId__documents__id');

  $DocumentsProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('docId')!;

    final manager = $DocumentsTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $HighlightsFilterComposer extends Composer<_$AppDatabase, Highlights> {
  $HighlightsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $DocumentsFilterComposer get docId {
    final $DocumentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $HighlightsOrderingComposer extends Composer<_$AppDatabase, Highlights> {
  $HighlightsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $DocumentsOrderingComposer get docId {
    final $DocumentsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $HighlightsAnnotationComposer
    extends Composer<_$AppDatabase, Highlights> {
  $HighlightsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $DocumentsAnnotationComposer get docId {
    final $DocumentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $HighlightsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Highlights,
          Highlight,
          $HighlightsFilterComposer,
          $HighlightsOrderingComposer,
          $HighlightsAnnotationComposer,
          $HighlightsCreateCompanionBuilder,
          $HighlightsUpdateCompanionBuilder,
          (Highlight, $HighlightsReferences),
          Highlight,
          PrefetchHooks Function({bool docId})
        > {
  $HighlightsTableManager(_$AppDatabase db, Highlights table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $HighlightsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $HighlightsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $HighlightsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HighlightsCompanion(
                id: id,
                docId: docId,
                content: content,
                note: note,
                color: color,
                groupId: groupId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String docId,
                required String content,
                Value<String?> note = const Value.absent(),
                required String color,
                Value<String?> groupId = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => HighlightsCompanion.insert(
                id: id,
                docId: docId,
                content: content,
                note: note,
                color: color,
                groupId: groupId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $HighlightsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (docId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.docId,
                                referencedTable: $HighlightsReferences
                                    ._docIdTable(db),
                                referencedColumn: $HighlightsReferences
                                    ._docIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $HighlightsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Highlights,
      Highlight,
      $HighlightsFilterComposer,
      $HighlightsOrderingComposer,
      $HighlightsAnnotationComposer,
      $HighlightsCreateCompanionBuilder,
      $HighlightsUpdateCompanionBuilder,
      (Highlight, $HighlightsReferences),
      Highlight,
      PrefetchHooks Function({bool docId})
    >;
typedef $HistoryCreateCompanionBuilder =
    HistoryCompanion Function({
      required String docId,
      required int openedAt,
      Value<double> progress,
      Value<int?> anchorBlock,
      Value<int> rowid,
    });
typedef $HistoryUpdateCompanionBuilder =
    HistoryCompanion Function({
      Value<String> docId,
      Value<int> openedAt,
      Value<double> progress,
      Value<int?> anchorBlock,
      Value<int> rowid,
    });

final class $HistoryReferences
    extends BaseReferences<_$AppDatabase, History, HistoryData> {
  $HistoryReferences(super.$_db, super.$_table, super.$_typedResult);

  static Documents _docIdTable(_$AppDatabase db) =>
      db.documents.createAlias('history__docId__documents__id');

  $DocumentsProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('docId')!;

    final manager = $DocumentsTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $HistoryFilterComposer extends Composer<_$AppDatabase, History> {
  $HistoryFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anchorBlock => $composableBuilder(
    column: $table.anchorBlock,
    builder: (column) => ColumnFilters(column),
  );

  $DocumentsFilterComposer get docId {
    final $DocumentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $HistoryOrderingComposer extends Composer<_$AppDatabase, History> {
  $HistoryOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anchorBlock => $composableBuilder(
    column: $table.anchorBlock,
    builder: (column) => ColumnOrderings(column),
  );

  $DocumentsOrderingComposer get docId {
    final $DocumentsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $HistoryAnnotationComposer extends Composer<_$AppDatabase, History> {
  $HistoryAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get anchorBlock => $composableBuilder(
    column: $table.anchorBlock,
    builder: (column) => column,
  );

  $DocumentsAnnotationComposer get docId {
    final $DocumentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $HistoryTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          History,
          HistoryData,
          $HistoryFilterComposer,
          $HistoryOrderingComposer,
          $HistoryAnnotationComposer,
          $HistoryCreateCompanionBuilder,
          $HistoryUpdateCompanionBuilder,
          (HistoryData, $HistoryReferences),
          HistoryData,
          PrefetchHooks Function({bool docId})
        > {
  $HistoryTableManager(_$AppDatabase db, History table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $HistoryFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $HistoryOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $HistoryAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> docId = const Value.absent(),
                Value<int> openedAt = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<int?> anchorBlock = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion(
                docId: docId,
                openedAt: openedAt,
                progress: progress,
                anchorBlock: anchorBlock,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String docId,
                required int openedAt,
                Value<double> progress = const Value.absent(),
                Value<int?> anchorBlock = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion.insert(
                docId: docId,
                openedAt: openedAt,
                progress: progress,
                anchorBlock: anchorBlock,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), $HistoryReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (docId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.docId,
                                referencedTable: $HistoryReferences._docIdTable(
                                  db,
                                ),
                                referencedColumn: $HistoryReferences
                                    ._docIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $HistoryProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      History,
      HistoryData,
      $HistoryFilterComposer,
      $HistoryOrderingComposer,
      $HistoryAnnotationComposer,
      $HistoryCreateCompanionBuilder,
      $HistoryUpdateCompanionBuilder,
      (HistoryData, $HistoryReferences),
      HistoryData,
      PrefetchHooks Function({bool docId})
    >;
typedef $FavoritesCreateCompanionBuilder =
    FavoritesCompanion Function({
      required String id,
      required String emoji,
      required String name,
      required int createdAt,
      Value<int> rowid,
    });
typedef $FavoritesUpdateCompanionBuilder =
    FavoritesCompanion Function({
      Value<String> id,
      Value<String> emoji,
      Value<String> name,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $FavoritesReferences
    extends BaseReferences<_$AppDatabase, Favorites, Favorite> {
  $FavoritesReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<FavoriteDocuments, List<FavoriteDocument>>
  _favoriteDocumentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.favoriteDocuments,
        aliasName: 'favorites__id__favorite_documents__favoriteId',
      );

  $FavoriteDocumentsProcessedTableManager get favoriteDocumentsRefs {
    final manager = $FavoriteDocumentsTableManager(
      $_db,
      $_db.favoriteDocuments,
    ).filter((f) => f.favoriteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _favoriteDocumentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $FavoritesFilterComposer extends Composer<_$AppDatabase, Favorites> {
  $FavoritesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> favoriteDocumentsRefs(
    Expression<bool> Function($FavoriteDocumentsFilterComposer f) f,
  ) {
    final $FavoriteDocumentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.favoriteDocuments,
      getReferencedColumn: (t) => t.favoriteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoriteDocumentsFilterComposer(
            $db: $db,
            $table: $db.favoriteDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $FavoritesOrderingComposer extends Composer<_$AppDatabase, Favorites> {
  $FavoritesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $FavoritesAnnotationComposer extends Composer<_$AppDatabase, Favorites> {
  $FavoritesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> favoriteDocumentsRefs<T extends Object>(
    Expression<T> Function($FavoriteDocumentsAnnotationComposer a) f,
  ) {
    final $FavoriteDocumentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.favoriteDocuments,
      getReferencedColumn: (t) => t.favoriteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoriteDocumentsAnnotationComposer(
            $db: $db,
            $table: $db.favoriteDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $FavoritesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Favorites,
          Favorite,
          $FavoritesFilterComposer,
          $FavoritesOrderingComposer,
          $FavoritesAnnotationComposer,
          $FavoritesCreateCompanionBuilder,
          $FavoritesUpdateCompanionBuilder,
          (Favorite, $FavoritesReferences),
          Favorite,
          PrefetchHooks Function({bool favoriteDocumentsRefs})
        > {
  $FavoritesTableManager(_$AppDatabase db, Favorites table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $FavoritesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $FavoritesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $FavoritesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                id: id,
                emoji: emoji,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String emoji,
                required String name,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                id: id,
                emoji: emoji,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), $FavoritesReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({favoriteDocumentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (favoriteDocumentsRefs) db.favoriteDocuments,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (favoriteDocumentsRefs)
                    await $_getPrefetchedData<
                      Favorite,
                      Favorites,
                      FavoriteDocument
                    >(
                      currentTable: table,
                      referencedTable: $FavoritesReferences
                          ._favoriteDocumentsRefsTable(db),
                      managerFromTypedResult: (p0) => $FavoritesReferences(
                        db,
                        table,
                        p0,
                      ).favoriteDocumentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.favoriteId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $FavoritesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Favorites,
      Favorite,
      $FavoritesFilterComposer,
      $FavoritesOrderingComposer,
      $FavoritesAnnotationComposer,
      $FavoritesCreateCompanionBuilder,
      $FavoritesUpdateCompanionBuilder,
      (Favorite, $FavoritesReferences),
      Favorite,
      PrefetchHooks Function({bool favoriteDocumentsRefs})
    >;
typedef $FavoriteDocumentsCreateCompanionBuilder =
    FavoriteDocumentsCompanion Function({
      required String favoriteId,
      required String docId,
      Value<int> rowid,
    });
typedef $FavoriteDocumentsUpdateCompanionBuilder =
    FavoriteDocumentsCompanion Function({
      Value<String> favoriteId,
      Value<String> docId,
      Value<int> rowid,
    });

final class $FavoriteDocumentsReferences
    extends BaseReferences<_$AppDatabase, FavoriteDocuments, FavoriteDocument> {
  $FavoriteDocumentsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Favorites _favoriteIdTable(_$AppDatabase db) =>
      db.favorites.createAlias('favorite_documents__favoriteId__favorites__id');

  $FavoritesProcessedTableManager get favoriteId {
    final $_column = $_itemColumn<String>('favoriteId')!;

    final manager = $FavoritesTableManager(
      $_db,
      $_db.favorites,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_favoriteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static Documents _docIdTable(_$AppDatabase db) =>
      db.documents.createAlias('favorite_documents__docId__documents__id');

  $DocumentsProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('docId')!;

    final manager = $DocumentsTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $FavoriteDocumentsFilterComposer
    extends Composer<_$AppDatabase, FavoriteDocuments> {
  $FavoriteDocumentsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $FavoritesFilterComposer get favoriteId {
    final $FavoritesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.favoriteId,
      referencedTable: $db.favorites,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoritesFilterComposer(
            $db: $db,
            $table: $db.favorites,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $DocumentsFilterComposer get docId {
    final $DocumentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $FavoriteDocumentsOrderingComposer
    extends Composer<_$AppDatabase, FavoriteDocuments> {
  $FavoriteDocumentsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $FavoritesOrderingComposer get favoriteId {
    final $FavoritesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.favoriteId,
      referencedTable: $db.favorites,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoritesOrderingComposer(
            $db: $db,
            $table: $db.favorites,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $DocumentsOrderingComposer get docId {
    final $DocumentsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $FavoriteDocumentsAnnotationComposer
    extends Composer<_$AppDatabase, FavoriteDocuments> {
  $FavoriteDocumentsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $FavoritesAnnotationComposer get favoriteId {
    final $FavoritesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.favoriteId,
      referencedTable: $db.favorites,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $FavoritesAnnotationComposer(
            $db: $db,
            $table: $db.favorites,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $DocumentsAnnotationComposer get docId {
    final $DocumentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $FavoriteDocumentsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          FavoriteDocuments,
          FavoriteDocument,
          $FavoriteDocumentsFilterComposer,
          $FavoriteDocumentsOrderingComposer,
          $FavoriteDocumentsAnnotationComposer,
          $FavoriteDocumentsCreateCompanionBuilder,
          $FavoriteDocumentsUpdateCompanionBuilder,
          (FavoriteDocument, $FavoriteDocumentsReferences),
          FavoriteDocument,
          PrefetchHooks Function({bool favoriteId, bool docId})
        > {
  $FavoriteDocumentsTableManager(_$AppDatabase db, FavoriteDocuments table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $FavoriteDocumentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $FavoriteDocumentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $FavoriteDocumentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> favoriteId = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteDocumentsCompanion(
                favoriteId: favoriteId,
                docId: docId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String favoriteId,
                required String docId,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteDocumentsCompanion.insert(
                favoriteId: favoriteId,
                docId: docId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $FavoriteDocumentsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({favoriteId = false, docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (favoriteId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.favoriteId,
                                referencedTable: $FavoriteDocumentsReferences
                                    ._favoriteIdTable(db),
                                referencedColumn: $FavoriteDocumentsReferences
                                    ._favoriteIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (docId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.docId,
                                referencedTable: $FavoriteDocumentsReferences
                                    ._docIdTable(db),
                                referencedColumn: $FavoriteDocumentsReferences
                                    ._docIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $FavoriteDocumentsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      FavoriteDocuments,
      FavoriteDocument,
      $FavoriteDocumentsFilterComposer,
      $FavoriteDocumentsOrderingComposer,
      $FavoriteDocumentsAnnotationComposer,
      $FavoriteDocumentsCreateCompanionBuilder,
      $FavoriteDocumentsUpdateCompanionBuilder,
      (FavoriteDocument, $FavoriteDocumentsReferences),
      FavoriteDocument,
      PrefetchHooks Function({bool favoriteId, bool docId})
    >;
typedef $ZoteroItemsCreateCompanionBuilder =
    ZoteroItemsCompanion Function({
      required String zoteroKey,
      Value<String?> docId,
      required int version,
      Value<int> rowid,
    });
typedef $ZoteroItemsUpdateCompanionBuilder =
    ZoteroItemsCompanion Function({
      Value<String> zoteroKey,
      Value<String?> docId,
      Value<int> version,
      Value<int> rowid,
    });

final class $ZoteroItemsReferences
    extends BaseReferences<_$AppDatabase, ZoteroItems, ZoteroItem> {
  $ZoteroItemsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Documents _docIdTable(_$AppDatabase db) =>
      db.documents.createAlias('zotero_items__docId__documents__id');

  $DocumentsProcessedTableManager? get docId {
    final $_column = $_itemColumn<String>('docId');
    if ($_column == null) return null;
    final manager = $DocumentsTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $ZoteroItemsFilterComposer extends Composer<_$AppDatabase, ZoteroItems> {
  $ZoteroItemsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get zoteroKey => $composableBuilder(
    column: $table.zoteroKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  $DocumentsFilterComposer get docId {
    final $DocumentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ZoteroItemsOrderingComposer
    extends Composer<_$AppDatabase, ZoteroItems> {
  $ZoteroItemsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get zoteroKey => $composableBuilder(
    column: $table.zoteroKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  $DocumentsOrderingComposer get docId {
    final $DocumentsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ZoteroItemsAnnotationComposer
    extends Composer<_$AppDatabase, ZoteroItems> {
  $ZoteroItemsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get zoteroKey =>
      $composableBuilder(column: $table.zoteroKey, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  $DocumentsAnnotationComposer get docId {
    final $DocumentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DocumentsAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ZoteroItemsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          ZoteroItems,
          ZoteroItem,
          $ZoteroItemsFilterComposer,
          $ZoteroItemsOrderingComposer,
          $ZoteroItemsAnnotationComposer,
          $ZoteroItemsCreateCompanionBuilder,
          $ZoteroItemsUpdateCompanionBuilder,
          (ZoteroItem, $ZoteroItemsReferences),
          ZoteroItem,
          PrefetchHooks Function({bool docId})
        > {
  $ZoteroItemsTableManager(_$AppDatabase db, ZoteroItems table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ZoteroItemsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ZoteroItemsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ZoteroItemsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> zoteroKey = const Value.absent(),
                Value<String?> docId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ZoteroItemsCompanion(
                zoteroKey: zoteroKey,
                docId: docId,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String zoteroKey,
                Value<String?> docId = const Value.absent(),
                required int version,
                Value<int> rowid = const Value.absent(),
              }) => ZoteroItemsCompanion.insert(
                zoteroKey: zoteroKey,
                docId: docId,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $ZoteroItemsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (docId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.docId,
                                referencedTable: $ZoteroItemsReferences
                                    ._docIdTable(db),
                                referencedColumn: $ZoteroItemsReferences
                                    ._docIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $ZoteroItemsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      ZoteroItems,
      ZoteroItem,
      $ZoteroItemsFilterComposer,
      $ZoteroItemsOrderingComposer,
      $ZoteroItemsAnnotationComposer,
      $ZoteroItemsCreateCompanionBuilder,
      $ZoteroItemsUpdateCompanionBuilder,
      (ZoteroItem, $ZoteroItemsReferences),
      ZoteroItem,
      PrefetchHooks Function({bool docId})
    >;
typedef $SettingsCreateCompanionBuilder =
    SettingsCompanion Function({
      required String settingKey,
      required String value,
      Value<int> rowid,
    });
typedef $SettingsUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> settingKey,
      Value<String> value,
      Value<int> rowid,
    });

class $SettingsFilterComposer extends Composer<_$AppDatabase, Settings> {
  $SettingsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get settingKey => $composableBuilder(
    column: $table.settingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $SettingsOrderingComposer extends Composer<_$AppDatabase, Settings> {
  $SettingsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get settingKey => $composableBuilder(
    column: $table.settingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SettingsAnnotationComposer extends Composer<_$AppDatabase, Settings> {
  $SettingsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get settingKey => $composableBuilder(
    column: $table.settingKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $SettingsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Settings,
          Setting,
          $SettingsFilterComposer,
          $SettingsOrderingComposer,
          $SettingsAnnotationComposer,
          $SettingsCreateCompanionBuilder,
          $SettingsUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, Settings, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $SettingsTableManager(_$AppDatabase db, Settings table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SettingsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SettingsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SettingsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> settingKey = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                settingKey: settingKey,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String settingKey,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                settingKey: settingKey,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SettingsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Settings,
      Setting,
      $SettingsFilterComposer,
      $SettingsOrderingComposer,
      $SettingsAnnotationComposer,
      $SettingsCreateCompanionBuilder,
      $SettingsUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, Settings, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $MetaCreateCompanionBuilder =
    MetaCompanion Function({
      required String metaKey,
      required String value,
      Value<int> rowid,
    });
typedef $MetaUpdateCompanionBuilder =
    MetaCompanion Function({
      Value<String> metaKey,
      Value<String> value,
      Value<int> rowid,
    });

class $MetaFilterComposer extends Composer<_$AppDatabase, Meta> {
  $MetaFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get metaKey => $composableBuilder(
    column: $table.metaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $MetaOrderingComposer extends Composer<_$AppDatabase, Meta> {
  $MetaOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get metaKey => $composableBuilder(
    column: $table.metaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MetaAnnotationComposer extends Composer<_$AppDatabase, Meta> {
  $MetaAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get metaKey =>
      $composableBuilder(column: $table.metaKey, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $MetaTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Meta,
          MetaData,
          $MetaFilterComposer,
          $MetaOrderingComposer,
          $MetaAnnotationComposer,
          $MetaCreateCompanionBuilder,
          $MetaUpdateCompanionBuilder,
          (MetaData, BaseReferences<_$AppDatabase, Meta, MetaData>),
          MetaData,
          PrefetchHooks Function()
        > {
  $MetaTableManager(_$AppDatabase db, Meta table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MetaFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MetaOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MetaAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> metaKey = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion(metaKey: metaKey, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String metaKey,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion.insert(
                metaKey: metaKey,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MetaProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Meta,
      MetaData,
      $MetaFilterComposer,
      $MetaOrderingComposer,
      $MetaAnnotationComposer,
      $MetaCreateCompanionBuilder,
      $MetaUpdateCompanionBuilder,
      (MetaData, BaseReferences<_$AppDatabase, Meta, MetaData>),
      MetaData,
      PrefetchHooks Function()
    >;
typedef $TranslationsCreateCompanionBuilder =
    TranslationsCompanion Function({
      required String cacheKey,
      required String translation,
      required int createdAt,
      Value<int> rowid,
    });
typedef $TranslationsUpdateCompanionBuilder =
    TranslationsCompanion Function({
      Value<String> cacheKey,
      Value<String> translation,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $TranslationsFilterComposer
    extends Composer<_$AppDatabase, Translations> {
  $TranslationsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get translation => $composableBuilder(
    column: $table.translation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $TranslationsOrderingComposer
    extends Composer<_$AppDatabase, Translations> {
  $TranslationsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get translation => $composableBuilder(
    column: $table.translation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $TranslationsAnnotationComposer
    extends Composer<_$AppDatabase, Translations> {
  $TranslationsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get translation => $composableBuilder(
    column: $table.translation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $TranslationsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Translations,
          Translation,
          $TranslationsFilterComposer,
          $TranslationsOrderingComposer,
          $TranslationsAnnotationComposer,
          $TranslationsCreateCompanionBuilder,
          $TranslationsUpdateCompanionBuilder,
          (
            Translation,
            BaseReferences<_$AppDatabase, Translations, Translation>,
          ),
          Translation,
          PrefetchHooks Function()
        > {
  $TranslationsTableManager(_$AppDatabase db, Translations table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $TranslationsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $TranslationsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $TranslationsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> translation = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TranslationsCompanion(
                cacheKey: cacheKey,
                translation: translation,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String translation,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TranslationsCompanion.insert(
                cacheKey: cacheKey,
                translation: translation,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $TranslationsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Translations,
      Translation,
      $TranslationsFilterComposer,
      $TranslationsOrderingComposer,
      $TranslationsAnnotationComposer,
      $TranslationsCreateCompanionBuilder,
      $TranslationsUpdateCompanionBuilder,
      (Translation, BaseReferences<_$AppDatabase, Translations, Translation>),
      Translation,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $DocumentsTableManager get documents =>
      $DocumentsTableManager(_db, _db.documents);
  $HighlightsTableManager get highlights =>
      $HighlightsTableManager(_db, _db.highlights);
  $HistoryTableManager get history => $HistoryTableManager(_db, _db.history);
  $FavoritesTableManager get favorites =>
      $FavoritesTableManager(_db, _db.favorites);
  $FavoriteDocumentsTableManager get favoriteDocuments =>
      $FavoriteDocumentsTableManager(_db, _db.favoriteDocuments);
  $ZoteroItemsTableManager get zoteroItems =>
      $ZoteroItemsTableManager(_db, _db.zoteroItems);
  $SettingsTableManager get settings =>
      $SettingsTableManager(_db, _db.settings);
  $MetaTableManager get meta => $MetaTableManager(_db, _db.meta);
  $TranslationsTableManager get translations =>
      $TranslationsTableManager(_db, _db.translations);
}
