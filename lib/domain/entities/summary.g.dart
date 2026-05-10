// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'summary.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSummaryCollection on Isar {
  IsarCollection<Summary> get summarys => this.collection();
}

const SummarySchema = CollectionSchema(
  name: r'Summary',
  id: -1062335529282731241,
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
    r'evidenceJson': PropertySchema(
      id: 3,
      name: r'evidenceJson',
      type: IsarType.string,
    ),
    r'keyDiscussions': PropertySchema(
      id: 4,
      name: r'keyDiscussions',
      type: IsarType.stringList,
    ),
    r'meetingDate': PropertySchema(
      id: 5,
      name: r'meetingDate',
      type: IsarType.dateTime,
    ),
    r'meetingId': PropertySchema(
      id: 6,
      name: r'meetingId',
      type: IsarType.long,
    ),
    r'meetingTitle': PropertySchema(
      id: 7,
      name: r'meetingTitle',
      type: IsarType.string,
    ),
    r'openQuestions': PropertySchema(
      id: 8,
      name: r'openQuestions',
      type: IsarType.stringList,
    ),
    r'participants': PropertySchema(
      id: 9,
      name: r'participants',
      type: IsarType.stringList,
    )
  },
  estimateSize: _summaryEstimateSize,
  serialize: _summarySerialize,
  deserialize: _summaryDeserialize,
  deserializeProp: _summaryDeserializeProp,
  idName: r'id',
  indexes: {
    r'meetingId': IndexSchema(
      id: -1528984323152142407,
      name: r'meetingId',
      unique: true,
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
  getId: _summaryGetId,
  getLinks: _summaryGetLinks,
  attach: _summaryAttach,
  version: '3.1.0+1',
);

int _summaryEstimateSize(
  Summary object,
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
  bytesCount += 3 + object.evidenceJson.length * 3;
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

void _summarySerialize(
  Summary object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.actionItemsJson);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeStringList(offsets[2], object.decisions);
  writer.writeString(offsets[3], object.evidenceJson);
  writer.writeStringList(offsets[4], object.keyDiscussions);
  writer.writeDateTime(offsets[5], object.meetingDate);
  writer.writeLong(offsets[6], object.meetingId);
  writer.writeString(offsets[7], object.meetingTitle);
  writer.writeStringList(offsets[8], object.openQuestions);
  writer.writeStringList(offsets[9], object.participants);
}

Summary _summaryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Summary();
  object.actionItemsJson = reader.readString(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.decisions = reader.readStringList(offsets[2]) ?? [];
  object.evidenceJson = reader.readString(offsets[3]);
  object.id = id;
  object.keyDiscussions = reader.readStringList(offsets[4]) ?? [];
  object.meetingDate = reader.readDateTime(offsets[5]);
  object.meetingId = reader.readLong(offsets[6]);
  object.meetingTitle = reader.readString(offsets[7]);
  object.openQuestions = reader.readStringList(offsets[8]) ?? [];
  object.participants = reader.readStringList(offsets[9]) ?? [];
  return object;
}

P _summaryDeserializeProp<P>(
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
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readStringList(offset) ?? []) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readStringList(offset) ?? []) as P;
    case 9:
      return (reader.readStringList(offset) ?? []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _summaryGetId(Summary object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _summaryGetLinks(Summary object) {
  return [];
}

void _summaryAttach(IsarCollection<dynamic> col, Id id, Summary object) {
  object.id = id;
}

extension SummaryByIndex on IsarCollection<Summary> {
  Future<Summary?> getByMeetingId(int meetingId) {
    return getByIndex(r'meetingId', [meetingId]);
  }

  Summary? getByMeetingIdSync(int meetingId) {
    return getByIndexSync(r'meetingId', [meetingId]);
  }

  Future<bool> deleteByMeetingId(int meetingId) {
    return deleteByIndex(r'meetingId', [meetingId]);
  }

  bool deleteByMeetingIdSync(int meetingId) {
    return deleteByIndexSync(r'meetingId', [meetingId]);
  }

  Future<List<Summary?>> getAllByMeetingId(List<int> meetingIdValues) {
    final values = meetingIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'meetingId', values);
  }

  List<Summary?> getAllByMeetingIdSync(List<int> meetingIdValues) {
    final values = meetingIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'meetingId', values);
  }

  Future<int> deleteAllByMeetingId(List<int> meetingIdValues) {
    final values = meetingIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'meetingId', values);
  }

  int deleteAllByMeetingIdSync(List<int> meetingIdValues) {
    final values = meetingIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'meetingId', values);
  }

  Future<Id> putByMeetingId(Summary object) {
    return putByIndex(r'meetingId', object);
  }

  Id putByMeetingIdSync(Summary object, {bool saveLinks = true}) {
    return putByIndexSync(r'meetingId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByMeetingId(List<Summary> objects) {
    return putAllByIndex(r'meetingId', objects);
  }

  List<Id> putAllByMeetingIdSync(List<Summary> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'meetingId', objects, saveLinks: saveLinks);
  }
}

extension SummaryQueryWhereSort on QueryBuilder<Summary, Summary, QWhere> {
  QueryBuilder<Summary, Summary, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<Summary, Summary, QAfterWhere> anyMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'meetingId'),
      );
    });
  }
}

extension SummaryQueryWhere on QueryBuilder<Summary, Summary, QWhereClause> {
  QueryBuilder<Summary, Summary, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<Summary, Summary, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Summary, Summary, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Summary, Summary, QAfterWhereClause> idBetween(
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

  QueryBuilder<Summary, Summary, QAfterWhereClause> meetingIdEqualTo(
      int meetingId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'meetingId',
        value: [meetingId],
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterWhereClause> meetingIdNotEqualTo(
      int meetingId) {
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

  QueryBuilder<Summary, Summary, QAfterWhereClause> meetingIdGreaterThan(
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

  QueryBuilder<Summary, Summary, QAfterWhereClause> meetingIdLessThan(
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

  QueryBuilder<Summary, Summary, QAfterWhereClause> meetingIdBetween(
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

extension SummaryQueryFilter
    on QueryBuilder<Summary, Summary, QFilterCondition> {
  QueryBuilder<Summary, Summary, QAfterFilterCondition> actionItemsJsonEqualTo(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> actionItemsJsonLessThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> actionItemsJsonBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> actionItemsJsonEndsWith(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> actionItemsJsonContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'actionItemsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> actionItemsJsonMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'actionItemsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      actionItemsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'actionItemsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      actionItemsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'actionItemsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> createdAtGreaterThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsElementEqualTo(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsElementBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      decisionsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'decisions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsElementMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'decisions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      decisionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'decisions',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      decisionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'decisions',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsLengthEqualTo(
      int length) {
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsIsEmpty() {
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsIsNotEmpty() {
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsLengthLessThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> decisionsLengthBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'evidenceJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'evidenceJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'evidenceJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'evidenceJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'evidenceJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'evidenceJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'evidenceJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'evidenceJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> evidenceJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'evidenceJson',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      evidenceJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'evidenceJson',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> idBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      keyDiscussionsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'keyDiscussions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      keyDiscussionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'keyDiscussions',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      keyDiscussionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'keyDiscussions',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingDateEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingDateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'meetingDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingDateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'meetingDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingDateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'meetingDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingId',
        value: value,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingIdGreaterThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingIdLessThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingIdBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleEqualTo(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleGreaterThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleLessThan(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleBetween(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleStartsWith(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleEndsWith(
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'meetingTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'meetingTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition> meetingTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      meetingTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'meetingTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      openQuestionsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'openQuestions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      openQuestionsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'openQuestions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      openQuestionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'openQuestions',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      openQuestionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'openQuestions',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> openQuestionsIsEmpty() {
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      participantsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'participants',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      participantsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'participants',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      participantsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'participants',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
      participantsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'participants',
        value: '',
      ));
    });
  }

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition> participantsIsEmpty() {
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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

  QueryBuilder<Summary, Summary, QAfterFilterCondition>
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
}

extension SummaryQueryObject
    on QueryBuilder<Summary, Summary, QFilterCondition> {}

extension SummaryQueryLinks
    on QueryBuilder<Summary, Summary, QFilterCondition> {}

extension SummaryQuerySortBy on QueryBuilder<Summary, Summary, QSortBy> {
  QueryBuilder<Summary, Summary, QAfterSortBy> sortByActionItemsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByActionItemsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByEvidenceJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'evidenceJson', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByEvidenceJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'evidenceJson', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByMeetingDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingDate', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByMeetingDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingDate', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByMeetingIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByMeetingTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> sortByMeetingTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.desc);
    });
  }
}

extension SummaryQuerySortThenBy
    on QueryBuilder<Summary, Summary, QSortThenBy> {
  QueryBuilder<Summary, Summary, QAfterSortBy> thenByActionItemsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByActionItemsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'actionItemsJson', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByEvidenceJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'evidenceJson', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByEvidenceJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'evidenceJson', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByMeetingDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingDate', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByMeetingDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingDate', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByMeetingIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.desc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByMeetingTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.asc);
    });
  }

  QueryBuilder<Summary, Summary, QAfterSortBy> thenByMeetingTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingTitle', Sort.desc);
    });
  }
}

extension SummaryQueryWhereDistinct
    on QueryBuilder<Summary, Summary, QDistinct> {
  QueryBuilder<Summary, Summary, QDistinct> distinctByActionItemsJson(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'actionItemsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByDecisions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'decisions');
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByEvidenceJson(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'evidenceJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByKeyDiscussions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'keyDiscussions');
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByMeetingDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'meetingDate');
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'meetingId');
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByMeetingTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'meetingTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByOpenQuestions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'openQuestions');
    });
  }

  QueryBuilder<Summary, Summary, QDistinct> distinctByParticipants() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'participants');
    });
  }
}

extension SummaryQueryProperty
    on QueryBuilder<Summary, Summary, QQueryProperty> {
  QueryBuilder<Summary, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Summary, String, QQueryOperations> actionItemsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'actionItemsJson');
    });
  }

  QueryBuilder<Summary, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Summary, List<String>, QQueryOperations> decisionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'decisions');
    });
  }

  QueryBuilder<Summary, String, QQueryOperations> evidenceJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'evidenceJson');
    });
  }

  QueryBuilder<Summary, List<String>, QQueryOperations>
      keyDiscussionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'keyDiscussions');
    });
  }

  QueryBuilder<Summary, DateTime, QQueryOperations> meetingDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'meetingDate');
    });
  }

  QueryBuilder<Summary, int, QQueryOperations> meetingIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'meetingId');
    });
  }

  QueryBuilder<Summary, String, QQueryOperations> meetingTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'meetingTitle');
    });
  }

  QueryBuilder<Summary, List<String>, QQueryOperations>
      openQuestionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'openQuestions');
    });
  }

  QueryBuilder<Summary, List<String>, QQueryOperations> participantsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'participants');
    });
  }
}
