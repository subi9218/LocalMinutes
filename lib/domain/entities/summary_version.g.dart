// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'summary_version.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSummaryVersionCollection on Isar {
  IsarCollection<SummaryVersion> get summaryVersions => this.collection();
}

const SummaryVersionSchema = CollectionSchema(
  name: r'SummaryVersion',
  id: -8189992089549055684,
  properties: {
    r'actionItemsJson': PropertySchema(
      id: 0,
      name: r'actionItemsJson',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'decisions': PropertySchema(
      id: 2,
      name: r'decisions',
      type: IsarType.stringList,
    ),
    r'keyDiscussions': PropertySchema(
      id: 3,
      name: r'keyDiscussions',
      type: IsarType.stringList,
    ),
    r'meetingId': PropertySchema(
      id: 4,
      name: r'meetingId',
      type: IsarType.long,
    ),
    r'meetingTitle': PropertySchema(
      id: 5,
      name: r'meetingTitle',
      type: IsarType.string,
    ),
    r'openQuestions': PropertySchema(
      id: 6,
      name: r'openQuestions',
      type: IsarType.stringList,
    ),
    r'participants': PropertySchema(
      id: 7,
      name: r'participants',
      type: IsarType.stringList,
    ),
    r'version': PropertySchema(
      id: 8,
      name: r'version',
      type: IsarType.long,
    )
  },
  estimateSize: _summaryVersionEstimateSize,
  serialize: _summaryVersionSerialize,
  deserialize: _summaryVersionDeserialize,
  deserializeProp: _summaryVersionDeserializeProp,
  idName: r'id',
  indexes: {
    r'meetingId': IndexSchema(
      id: -1528984323152142407,
      name: r'meetingId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'meetingId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _summaryVersionGetId,
  getLinks: _summaryVersionGetLinks,
  attach: _summaryVersionAttach,
  version: '3.1.0+1',
);

int _summaryVersionEstimateSize(
  SummaryVersion object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.actionItemsJson.length * 3;
  bytesCount += 3 + object.decisions.length * 3;
  {
    for (var i = 0; i < object.decisions.length; i++) {
      final value = object.decisions[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.keyDiscussions.length * 3;
  {
    for (var i = 0; i < object.keyDiscussions.length; i++) {
      final value = object.keyDiscussions[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.meetingTitle.length * 3;
  bytesCount += 3 + object.openQuestions.length * 3;
  {
    for (var i = 0; i < object.openQuestions.length; i++) {
      final value = object.openQuestions[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.participants.length * 3;
  {
    for (var i = 0; i < object.participants.length; i++) {
      final value = object.participants[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _summaryVersionSerialize(
  SummaryVersion object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.actionItemsJson);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeStringList(offsets[2], object.decisions);
  writer.writeStringList(offsets[3], object.keyDiscussions);
  writer.writeLong(offsets[4], object.meetingId);
  writer.writeString(offsets[5], object.meetingTitle);
  writer.writeStringList(offsets[6], object.openQuestions);
  writer.writeStringList(offsets[7], object.participants);
  writer.writeLong(offsets[8], object.version);
}

SummaryVersion _summaryVersionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SummaryVersion();
  object.actionItemsJson = reader.readString(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.decisions = reader.readStringList(offsets[2]) ?? [];
  object.id = id;
  object.keyDiscussions = reader.readStringList(offsets[3]) ?? [];
  object.meetingId = reader.readLong(offsets[4]);
  object.meetingTitle = reader.readString(offsets[5]);
  object.openQuestions = reader.readStringList(offsets[6]) ?? [];
  object.participants = reader.readStringList(offsets[7]) ?? [];
  object.version = reader.readLong(offsets[8]);
  return object;
}

P _summaryVersionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readStringList(offset) ?? []) as P;
    case 3:
      return (reader.readStringList(offset) ?? []) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringList(offset) ?? []) as P;
    case 7:
      return (reader.readStringList(offset) ?? []) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _summaryVersionGetId(SummaryVersion object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _summaryVersionGetLinks(SummaryVersion object) {
  return [];
}

void _summaryVersionAttach(
    IsarCollection<dynamic> col, Id id, SummaryVersion object) {
  object.id = id;
}

extension SummaryVersionQueryWhereSort
    on QueryBuilder<SummaryVersion, SummaryVersion, QWhere> {
  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhere> anyMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'meetingId'),
      );
    });
  }
}

extension SummaryVersionQueryWhere
    on QueryBuilder<SummaryVersion, SummaryVersion, QWhereClause> {
  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause> idBetween(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause>
      meetingIdEqualTo(int meetingId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'meetingId',
        value: [meetingId],
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause>
      meetingIdNotEqualTo(int meetingId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'meetingId',
              lower: [],
              upper: [meetingId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'meetingId',
              lower: [meetingId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'meetingId',
              lower: [meetingId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'meetingId',
              lower: [],
              upper: [meetingId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause>
      meetingIdGreaterThan(
    int meetingId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'meetingId',
        lower: [meetingId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause>
      meetingIdLessThan(
    int meetingId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'meetingId',
        lower: [],
        upper: [meetingId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterWhereClause>
      meetingIdBetween(
    int lowerMeetingId,
    int upperMeetingId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'meetingId',
        lower: [lowerMeetingId],
        includeLower: includeLower,
        upper: [upperMeetingId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension SummaryVersionQueryFilter
    on QueryBuilder<SummaryVersion, SummaryVersion, QFilterCondition> {
  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'actionItemsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'actionItemsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'actionItemsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      actionItemsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'actionItemsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      createdAtGreaterThan(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      createdAtLessThan(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      createdAtBetween(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'decisions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'decisions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'decisions',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'decisions',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'decisions',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'decisions',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'decisions',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'decisions',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'decisions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      decisionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'decisions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      idGreaterThan(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition> idBetween(
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

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'keyDiscussions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'keyDiscussions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'keyDiscussions',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'keyDiscussions',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'keyDiscussions',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'keyDiscussions',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'keyDiscussions',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'keyDiscussions',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'keyDiscussions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      keyDiscussionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'keyDiscussions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingId',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'meetingId',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'meetingId',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'meetingId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'meetingTitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'meetingTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      meetingTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'meetingTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'openQuestions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'openQuestions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'openQuestions',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'openQuestions',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'openQuestions',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'openQuestions',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'openQuestions',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'openQuestions',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'openQuestions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      openQuestionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'openQuestions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'participants',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'participants',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'participants',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'participants',
        value: '',
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'participants',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'participants',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'participants',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'participants',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'participants',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      participantsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'participants',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      versionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'version',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      versionGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'version',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      versionLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'version',
        value: value,
      ));
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterFilterCondition>
      versionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'version',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension SummaryVersionQueryObject
    on QueryBuilder<SummaryVersion, SummaryVersion, QFilterCondition> {}

extension SummaryVersionQueryLinks
    on QueryBuilder<SummaryVersion, SummaryVersion, QFilterCondition> {}

extension SummaryVersionQuerySortBy
    on QueryBuilder<SummaryVersion, SummaryVersion, QSortBy> {
  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByActionItemsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByActionItemsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> sortByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByMeetingIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByMeetingTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByMeetingTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> sortByVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      sortByVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.desc);
    });
  }
}

extension SummaryVersionQuerySortThenBy
    on QueryBuilder<SummaryVersion, SummaryVersion, QSortThenBy> {
  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByActionItemsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByActionItemsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> thenByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByMeetingIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByMeetingTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByMeetingTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.desc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy> thenByVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.asc);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QAfterSortBy>
      thenByVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.desc);
    });
  }
}

extension SummaryVersionQueryWhereDistinct
    on QueryBuilder<SummaryVersion, SummaryVersion, QDistinct> {
  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByActionItemsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'actionItemsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByDecisions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'decisions');
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByKeyDiscussions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'keyDiscussions');
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'meetingId');
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByMeetingTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'meetingTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByOpenQuestions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'openQuestions');
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct>
      distinctByParticipants() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'participants');
    });
  }

  QueryBuilder<SummaryVersion, SummaryVersion, QDistinct> distinctByVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'version');
    });
  }
}

extension SummaryVersionQueryProperty
    on QueryBuilder<SummaryVersion, SummaryVersion, QQueryProperty> {
  QueryBuilder<SummaryVersion, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SummaryVersion, String, QQueryOperations>
      actionItemsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'actionItemsJson');
    });
  }

  QueryBuilder<SummaryVersion, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<SummaryVersion, List<String>, QQueryOperations>
      decisionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'decisions');
    });
  }

  QueryBuilder<SummaryVersion, List<String>, QQueryOperations>
      keyDiscussionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'keyDiscussions');
    });
  }

  QueryBuilder<SummaryVersion, int, QQueryOperations> meetingIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'meetingId');
    });
  }

  QueryBuilder<SummaryVersion, String, QQueryOperations>
      meetingTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'meetingTitle');
    });
  }

  QueryBuilder<SummaryVersion, List<String>, QQueryOperations>
      openQuestionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'openQuestions');
    });
  }

  QueryBuilder<SummaryVersion, List<String>, QQueryOperations>
      participantsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'participants');
    });
  }

  QueryBuilder<SummaryVersion, int, QQueryOperations> versionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'version');
    });
  }
}
