// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_record.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetChatRecordCollection on Isar {
  IsarCollection<ChatRecord> get chatRecords => this.collection();
}

const ChatRecordSchema = CollectionSchema(
  name: r'ChatRecord',
  id: 7364859201837462519,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'isUser': PropertySchema(
      id: 1,
      name: r'isUser',
      type: IsarType.bool,
    ),
    r'text': PropertySchema(
      id: 2,
      name: r'text',
      type: IsarType.string,
    )
  },
  estimateSize: _chatRecordEstimateSize,
  serialize: _chatRecordSerialize,
  deserialize: _chatRecordDeserialize,
  deserializeProp: _chatRecordDeserializeProp,
  idName: r'id',
  indexes: {
    r'createdAt': IndexSchema(
      id: 8796754321012345678,
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'isUser': IndexSchema(
      id: 9876543210987654321,
      name: r'isUser',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isUser',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _chatRecordGetId,
  getLinks: _chatRecordGetLinks,
  attach: _chatRecordAttach,
  version: '3.1.0+1',
);

int _chatRecordEstimateSize(
  ChatRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.text.length * 3;
  return bytesCount;
}

void _chatRecordSerialize(
  ChatRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeBool(offsets[1], object.isUser);
  writer.writeString(offsets[2], object.text);
}

ChatRecord _chatRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ChatRecord(
    isUser: reader.readBool(offsets[1]),
    text: reader.readString(offsets[2]),
  );
  object.createdAt = reader.readDateTime(offsets[0]);
  object.id = id;
  return object;
}

P _chatRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _chatRecordGetId(ChatRecord object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _chatRecordGetLinks(ChatRecord object) {
  return [];
}

void _chatRecordAttach(IsarCollection<dynamic> col, Id id, ChatRecord object) {
  object.id = id;
}

extension ChatRecordQueryWhereSort on QueryBuilder<ChatRecord, ChatRecord, QWhere> {
  QueryBuilder<ChatRecord, ChatRecord, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterWhere> anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterWhere> anyIsUser() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isUser'),
      );
    });
  }
}

extension ChatRecordQueryWhere on QueryBuilder<ChatRecord, ChatRecord, QWhereClause> {
  QueryBuilder<ChatRecord, ChatRecord, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterWhereClause> createdAtEqualTo(DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterWhereClause> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [lower],
        includeLower: includeLower,
        upper: [upper],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterWhereClause> isUserEqualTo(bool isUser) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isUser',
        value: [isUser],
      ));
    });
  }
}

extension ChatRecordQueryFilter on QueryBuilder<ChatRecord, ChatRecord, QFilterCondition> {
  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> isUserEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isUser',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> textEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatRecord, ChatRecord, QAfterFilterCondition> textContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }
}
