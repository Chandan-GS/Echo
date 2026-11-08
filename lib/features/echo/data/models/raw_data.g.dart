// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'raw_data.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetRawDataCollection on Isar {
  IsarCollection<RawData> get rawDatas => this.collection();
}

const RawDataSchema = CollectionSchema(
  name: r'RawData',
  id: 6440790256153188216,
  properties: {
    r'addressed': PropertySchema(
      id: 0,
      name: r'addressed',
      type: IsarType.string,
    ),
    r'captureKey': PropertySchema(
      id: 1,
      name: r'captureKey',
      type: IsarType.string,
    ),
    r'content': PropertySchema(
      id: 2,
      name: r'content',
      type: IsarType.string,
    ),
    r'embedding': PropertySchema(
      id: 3,
      name: r'embedding',
      type: IsarType.doubleList,
    ),
    r'heldAt': PropertySchema(
      id: 4,
      name: r'heldAt',
      type: IsarType.dateTime,
    ),
    r'isGroup': PropertySchema(
      id: 5,
      name: r'isGroup',
      type: IsarType.bool,
    ),
    r'noticeKey': PropertySchema(
      id: 6,
      name: r'noticeKey',
      type: IsarType.string,
    ),
    r'removal': PropertySchema(
      id: 7,
      name: r'removal',
      type: IsarType.string,
    ),
    r'sender': PropertySchema(
      id: 8,
      name: r'sender',
      type: IsarType.string,
    ),
    r'sent': PropertySchema(
      id: 9,
      name: r'sent',
      type: IsarType.bool,
    ),
    r'source': PropertySchema(
      id: 10,
      name: r'source',
      type: IsarType.string,
    ),
    r'swipedAt': PropertySchema(
      id: 11,
      name: r'swipedAt',
      type: IsarType.dateTime,
    ),
    r'thread': PropertySchema(
      id: 12,
      name: r'thread',
      type: IsarType.string,
    ),
    r'threadTitle': PropertySchema(
      id: 13,
      name: r'threadTitle',
      type: IsarType.string,
    ),
    r'timestamp': PropertySchema(
      id: 14,
      name: r'timestamp',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _rawDataEstimateSize,
  serialize: _rawDataSerialize,
  deserialize: _rawDataDeserialize,
  deserializeProp: _rawDataDeserializeProp,
  idName: r'id',
  indexes: {
    r'timestamp': IndexSchema(
      id: 1852253767416892198,
      name: r'timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'timestamp',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'thread': IndexSchema(
      id: 2879416675853168189,
      name: r'thread',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'thread',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'captureKey': IndexSchema(
      id: -7611860689174427149,
      name: r'captureKey',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'captureKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'noticeKey': IndexSchema(
      id: -233997087784929175,
      name: r'noticeKey',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'noticeKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'swipedAt': IndexSchema(
      id: 4946365284874959658,
      name: r'swipedAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'swipedAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'heldAt': IndexSchema(
      id: -10185352797084834,
      name: r'heldAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'heldAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _rawDataGetId,
  getLinks: _rawDataGetLinks,
  attach: _rawDataAttach,
  version: '3.1.0+1',
);

int _rawDataEstimateSize(
  RawData object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.addressed;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.captureKey;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.content.length * 3;
  {
    final value = object.embedding;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  {
    final value = object.noticeKey;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.removal;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.sender.length * 3;
  bytesCount += 3 + object.source.length * 3;
  {
    final value = object.thread;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.threadTitle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _rawDataSerialize(
  RawData object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.addressed);
  writer.writeString(offsets[1], object.captureKey);
  writer.writeString(offsets[2], object.content);
  writer.writeDoubleList(offsets[3], object.embedding);
  writer.writeDateTime(offsets[4], object.heldAt);
  writer.writeBool(offsets[5], object.isGroup);
  writer.writeString(offsets[6], object.noticeKey);
  writer.writeString(offsets[7], object.removal);
  writer.writeString(offsets[8], object.sender);
  writer.writeBool(offsets[9], object.sent);
  writer.writeString(offsets[10], object.source);
  writer.writeDateTime(offsets[11], object.swipedAt);
  writer.writeString(offsets[12], object.thread);
  writer.writeString(offsets[13], object.threadTitle);
  writer.writeDateTime(offsets[14], object.timestamp);
}

RawData _rawDataDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = RawData();
  object.addressed = reader.readStringOrNull(offsets[0]);
  object.captureKey = reader.readStringOrNull(offsets[1]);
  object.content = reader.readString(offsets[2]);
  object.embedding = reader.readDoubleList(offsets[3]);
  object.heldAt = reader.readDateTimeOrNull(offsets[4]);
  object.id = id;
  object.isGroup = reader.readBool(offsets[5]);
  object.noticeKey = reader.readStringOrNull(offsets[6]);
  object.removal = reader.readStringOrNull(offsets[7]);
  object.sender = reader.readString(offsets[8]);
  object.sent = reader.readBoolOrNull(offsets[9]);
  object.source = reader.readString(offsets[10]);
  object.swipedAt = reader.readDateTimeOrNull(offsets[11]);
  object.thread = reader.readStringOrNull(offsets[12]);
  object.threadTitle = reader.readStringOrNull(offsets[13]);
  object.timestamp = reader.readDateTime(offsets[14]);
  return object;
}

P _rawDataDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readDoubleList(offset)) as P;
    case 4:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readBoolOrNull(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _rawDataGetId(RawData object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _rawDataGetLinks(RawData object) {
  return [];
}

void _rawDataAttach(IsarCollection<dynamic> col, Id id, RawData object) {
  object.id = id;
}

extension RawDataQueryWhereSort on QueryBuilder<RawData, RawData, QWhere> {
  QueryBuilder<RawData, RawData, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhere> anyTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'timestamp'),
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhere> anySwipedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'swipedAt'),
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhere> anyHeldAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'heldAt'),
      );
    });
  }
}

extension RawDataQueryWhere on QueryBuilder<RawData, RawData, QWhereClause> {
  QueryBuilder<RawData, RawData, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> timestampEqualTo(
      DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'timestamp',
        value: [timestamp],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> timestampNotEqualTo(
      DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [],
              upper: [timestamp],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [timestamp],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [timestamp],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [],
              upper: [timestamp],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> timestampGreaterThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [timestamp],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> timestampLessThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [],
        upper: [timestamp],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> timestampBetween(
    DateTime lowerTimestamp,
    DateTime upperTimestamp, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [lowerTimestamp],
        includeLower: includeLower,
        upper: [upperTimestamp],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> threadIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'thread',
        value: [null],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> threadIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'thread',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> threadEqualTo(
      String? thread) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'thread',
        value: [thread],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> threadNotEqualTo(
      String? thread) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'thread',
              lower: [],
              upper: [thread],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'thread',
              lower: [thread],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'thread',
              lower: [thread],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'thread',
              lower: [],
              upper: [thread],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> captureKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'captureKey',
        value: [null],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> captureKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'captureKey',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> captureKeyEqualTo(
      String? captureKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'captureKey',
        value: [captureKey],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> captureKeyNotEqualTo(
      String? captureKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'captureKey',
              lower: [],
              upper: [captureKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'captureKey',
              lower: [captureKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'captureKey',
              lower: [captureKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'captureKey',
              lower: [],
              upper: [captureKey],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> noticeKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'noticeKey',
        value: [null],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> noticeKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'noticeKey',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> noticeKeyEqualTo(
      String? noticeKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'noticeKey',
        value: [noticeKey],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> noticeKeyNotEqualTo(
      String? noticeKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noticeKey',
              lower: [],
              upper: [noticeKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noticeKey',
              lower: [noticeKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noticeKey',
              lower: [noticeKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noticeKey',
              lower: [],
              upper: [noticeKey],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'swipedAt',
        value: [null],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'swipedAt',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtEqualTo(
      DateTime? swipedAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'swipedAt',
        value: [swipedAt],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtNotEqualTo(
      DateTime? swipedAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'swipedAt',
              lower: [],
              upper: [swipedAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'swipedAt',
              lower: [swipedAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'swipedAt',
              lower: [swipedAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'swipedAt',
              lower: [],
              upper: [swipedAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtGreaterThan(
    DateTime? swipedAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'swipedAt',
        lower: [swipedAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtLessThan(
    DateTime? swipedAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'swipedAt',
        lower: [],
        upper: [swipedAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> swipedAtBetween(
    DateTime? lowerSwipedAt,
    DateTime? upperSwipedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'swipedAt',
        lower: [lowerSwipedAt],
        includeLower: includeLower,
        upper: [upperSwipedAt],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'heldAt',
        value: [null],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'heldAt',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtEqualTo(
      DateTime? heldAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'heldAt',
        value: [heldAt],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtNotEqualTo(
      DateTime? heldAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'heldAt',
              lower: [],
              upper: [heldAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'heldAt',
              lower: [heldAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'heldAt',
              lower: [heldAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'heldAt',
              lower: [],
              upper: [heldAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtGreaterThan(
    DateTime? heldAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'heldAt',
        lower: [heldAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtLessThan(
    DateTime? heldAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'heldAt',
        lower: [],
        upper: [heldAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterWhereClause> heldAtBetween(
    DateTime? lowerHeldAt,
    DateTime? upperHeldAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'heldAt',
        lower: [lowerHeldAt],
        includeLower: includeLower,
        upper: [upperHeldAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension RawDataQueryFilter
    on QueryBuilder<RawData, RawData, QFilterCondition> {
  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'addressed',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'addressed',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'addressed',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'addressed',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'addressed',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'addressed',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'addressed',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'addressed',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'addressed',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'addressed',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'addressed',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> addressedIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'addressed',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'captureKey',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'captureKey',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'captureKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'captureKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'captureKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'captureKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'captureKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'captureKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'captureKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'captureKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'captureKey',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> captureKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'captureKey',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'content',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'content',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> contentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'embedding',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'embedding',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingElementEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'embedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition>
      embeddingElementGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'embedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition>
      embeddingElementLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'embedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingElementBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'embedding',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition>
      embeddingLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> embeddingLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> heldAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'heldAt',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> heldAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'heldAt',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> heldAtEqualTo(
      DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'heldAt',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> heldAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'heldAt',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> heldAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'heldAt',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> heldAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'heldAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> isGroupEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isGroup',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'noticeKey',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'noticeKey',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'noticeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'noticeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'noticeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'noticeKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'noticeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'noticeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'noticeKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'noticeKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'noticeKey',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> noticeKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'noticeKey',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'removal',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'removal',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'removal',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'removal',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'removal',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'removal',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'removal',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'removal',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'removal',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'removal',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'removal',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> removalIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'removal',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sender',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sender',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sender',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> senderIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sender',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sentIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sent',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sentIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sent',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sentEqualTo(
      bool? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sent',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'source',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'source',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'source',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'source',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'source',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'source',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'source',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'source',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'source',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> sourceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'source',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> swipedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'swipedAt',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> swipedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'swipedAt',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> swipedAtEqualTo(
      DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'swipedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> swipedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'swipedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> swipedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'swipedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> swipedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'swipedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'thread',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'thread',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'thread',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'thread',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'thread',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'thread',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'thread',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'thread',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'thread',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'thread',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'thread',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'thread',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'threadTitle',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'threadTitle',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'threadTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'threadTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'threadTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'threadTitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'threadTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'threadTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'threadTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'threadTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> threadTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'threadTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition>
      threadTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'threadTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> timestampEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<RawData, RawData, QAfterFilterCondition> timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension RawDataQueryObject
    on QueryBuilder<RawData, RawData, QFilterCondition> {}

extension RawDataQueryLinks
    on QueryBuilder<RawData, RawData, QFilterCondition> {}

extension RawDataQuerySortBy on QueryBuilder<RawData, RawData, QSortBy> {
  QueryBuilder<RawData, RawData, QAfterSortBy> sortByAddressed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addressed', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByAddressedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addressed', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByCaptureKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'captureKey', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByCaptureKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'captureKey', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByHeldAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'heldAt', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByHeldAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'heldAt', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByIsGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isGroup', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByIsGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isGroup', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByNoticeKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noticeKey', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByNoticeKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noticeKey', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByRemoval() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'removal', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByRemovalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'removal', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySender() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sender', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySenderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sender', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sent', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sent', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySwipedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'swipedAt', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortBySwipedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'swipedAt', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByThread() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thread', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByThreadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thread', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByThreadTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadTitle', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByThreadTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadTitle', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension RawDataQuerySortThenBy
    on QueryBuilder<RawData, RawData, QSortThenBy> {
  QueryBuilder<RawData, RawData, QAfterSortBy> thenByAddressed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addressed', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByAddressedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addressed', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByCaptureKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'captureKey', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByCaptureKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'captureKey', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByHeldAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'heldAt', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByHeldAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'heldAt', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByIsGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isGroup', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByIsGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isGroup', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByNoticeKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noticeKey', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByNoticeKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noticeKey', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByRemoval() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'removal', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByRemovalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'removal', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySender() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sender', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySenderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sender', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sent', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sent', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySwipedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'swipedAt', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenBySwipedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'swipedAt', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByThread() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thread', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByThreadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thread', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByThreadTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadTitle', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByThreadTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadTitle', Sort.desc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<RawData, RawData, QAfterSortBy> thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension RawDataQueryWhereDistinct
    on QueryBuilder<RawData, RawData, QDistinct> {
  QueryBuilder<RawData, RawData, QDistinct> distinctByAddressed(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'addressed', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByCaptureKey(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'captureKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'content', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByEmbedding() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'embedding');
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByHeldAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'heldAt');
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByIsGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isGroup');
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByNoticeKey(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'noticeKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByRemoval(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'removal', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctBySender(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sender', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctBySent() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sent');
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctBySource(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'source', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctBySwipedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'swipedAt');
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByThread(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'thread', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByThreadTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'threadTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RawData, RawData, QDistinct> distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }
}

extension RawDataQueryProperty
    on QueryBuilder<RawData, RawData, QQueryProperty> {
  QueryBuilder<RawData, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<RawData, String?, QQueryOperations> addressedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'addressed');
    });
  }

  QueryBuilder<RawData, String?, QQueryOperations> captureKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'captureKey');
    });
  }

  QueryBuilder<RawData, String, QQueryOperations> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'content');
    });
  }

  QueryBuilder<RawData, List<double>?, QQueryOperations> embeddingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'embedding');
    });
  }

  QueryBuilder<RawData, DateTime?, QQueryOperations> heldAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'heldAt');
    });
  }

  QueryBuilder<RawData, bool, QQueryOperations> isGroupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isGroup');
    });
  }

  QueryBuilder<RawData, String?, QQueryOperations> noticeKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'noticeKey');
    });
  }

  QueryBuilder<RawData, String?, QQueryOperations> removalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'removal');
    });
  }

  QueryBuilder<RawData, String, QQueryOperations> senderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sender');
    });
  }

  QueryBuilder<RawData, bool?, QQueryOperations> sentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sent');
    });
  }

  QueryBuilder<RawData, String, QQueryOperations> sourceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'source');
    });
  }

  QueryBuilder<RawData, DateTime?, QQueryOperations> swipedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'swipedAt');
    });
  }

  QueryBuilder<RawData, String?, QQueryOperations> threadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'thread');
    });
  }

  QueryBuilder<RawData, String?, QQueryOperations> threadTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'threadTitle');
    });
  }

  QueryBuilder<RawData, DateTime, QQueryOperations> timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }
}
