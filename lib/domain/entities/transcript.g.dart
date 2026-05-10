// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetTranscriptCollection on Isar {
  IsarCollection<Transcript> get transcripts => this.collection();
}

const TranscriptSchema = CollectionSchema(
  name: r'Transcript',
  id: -8505618206250344956,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'endTimeSeconds': PropertySchema(
      id: 1,
      name: r'endTimeSeconds',
      type: IsarType.double,
    ),
    r'meetingId': PropertySchema(
      id: 2,
      name: r'meetingId',
      type: IsarType.long,
    ),
    r'segmentIndex': PropertySchema(
      id: 3,
      name: r'segmentIndex',
      type: IsarType.long,
    ),
    r'speakerLabel': PropertySchema(
      id: 4,
      name: r'speakerLabel',
      type: IsarType.string,
    ),
    r'startTimeSeconds': PropertySchema(
      id: 5,
      name: r'startTimeSeconds',
      type: IsarType.double,
    ),
    r'text': PropertySchema(
      id: 6,
      name: r'text',
      type: IsarType.string,
    )
  },
  estimateSize: _transcriptEstimateSize,
  serialize: _transcriptSerialize,
  deserialize: _transcriptDeserialize,
  deserializeProp: _transcriptDeserializeProp,
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
  getId: _transcriptGetId,
  getLinks: _transcriptGetLinks,
  attach: _transcriptAttach,
  version: '3.1.0+1',
);

int _transcriptEstimateSize(
  Transcript object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.speakerLabel;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.text.length * 3;
  return bytesCount;
}

void _transcriptSerialize(
  Transcript object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeDouble(offsets[1], object.endTimeSeconds);
  writer.writeLong(offsets[2], object.meetingId);
  writer.writeLong(offsets[3], object.segmentIndex);
  writer.writeString(offsets[4], object.speakerLabel);
  writer.writeDouble(offsets[5], object.startTimeSeconds);
  writer.writeString(offsets[6], object.text);
}

Transcript _transcriptDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Transcript();
  object.createdAt = reader.readDateTime(offsets[0]);
  object.endTimeSeconds = reader.readDouble(offsets[1]);
  object.id = id;
  object.meetingId = reader.readLong(offsets[2]);
  object.segmentIndex = reader.readLong(offsets[3]);
  object.speakerLabel = reader.readStringOrNull(offsets[4]);
  object.startTimeSeconds = reader.readDouble(offsets[5]);
  object.text = reader.readString(offsets[6]);
  return object;
}

P _transcriptDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readDouble(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readDouble(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _transcriptGetId(Transcript object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _transcriptGetLinks(Transcript object) {
  return [];
}

void _transcriptAttach(IsarCollection<dynamic> col, Id id, Transcript object) {
  object.id = id;
}

extension TranscriptQueryWhereSort
    on QueryBuilder<Transcript, Transcript, QWhere> {
  QueryBuilder<Transcript, Transcript, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterWhere> anyMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'meetingId'),
      );
    });
  }
}

extension TranscriptQueryWhere
    on QueryBuilder<Transcript, Transcript, QWhereClause> {
  QueryBuilder<Transcript, Transcript, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> idBetween(
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

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> meetingIdEqualTo(
      int meetingId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'meetingId',
        value: [meetingId],
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> meetingIdNotEqualTo(
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

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> meetingIdGreaterThan(
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

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> meetingIdLessThan(
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

  QueryBuilder<Transcript, Transcript, QAfterWhereClause> meetingIdBetween(
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

extension TranscriptQueryFilter
    on QueryBuilder<Transcript, Transcript, QFilterCondition> {
  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      endTimeSecondsEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTimeSeconds',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      endTimeSecondsGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endTimeSeconds',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      endTimeSecondsLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endTimeSeconds',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      endTimeSecondsBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endTimeSeconds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> idBetween(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> meetingIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'meetingId',
        value: value,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> meetingIdLessThan(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> meetingIdBetween(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      segmentIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'segmentIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      segmentIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'segmentIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      segmentIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'segmentIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      segmentIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'segmentIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'speakerLabel',
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'speakerLabel',
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'speakerLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'speakerLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'speakerLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'speakerLabel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'speakerLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'speakerLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'speakerLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'speakerLabel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'speakerLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      speakerLabelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'speakerLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      startTimeSecondsEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTimeSeconds',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      startTimeSecondsGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startTimeSeconds',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      startTimeSecondsLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startTimeSeconds',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition>
      startTimeSecondsBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startTimeSeconds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textEqualTo(
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

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'text',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'text',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: '',
      ));
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterFilterCondition> textIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'text',
        value: '',
      ));
    });
  }
}

extension TranscriptQueryObject
    on QueryBuilder<Transcript, Transcript, QFilterCondition> {}

extension TranscriptQueryLinks
    on QueryBuilder<Transcript, Transcript, QFilterCondition> {}

extension TranscriptQuerySortBy
    on QueryBuilder<Transcript, Transcript, QSortBy> {
  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByEndTimeSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeSeconds', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy>
      sortByEndTimeSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeSeconds', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByMeetingIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortBySegmentIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'segmentIndex', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortBySegmentIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'segmentIndex', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortBySpeakerLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speakerLabel', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortBySpeakerLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speakerLabel', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByStartTimeSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeSeconds', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy>
      sortByStartTimeSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeSeconds', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> sortByTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.desc);
    });
  }
}

extension TranscriptQuerySortThenBy
    on QueryBuilder<Transcript, Transcript, QSortThenBy> {
  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByEndTimeSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeSeconds', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy>
      thenByEndTimeSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeSeconds', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByMeetingIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'meetingId', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenBySegmentIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'segmentIndex', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenBySegmentIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'segmentIndex', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenBySpeakerLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speakerLabel', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenBySpeakerLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speakerLabel', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByStartTimeSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeSeconds', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy>
      thenByStartTimeSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeSeconds', Sort.desc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.asc);
    });
  }

  QueryBuilder<Transcript, Transcript, QAfterSortBy> thenByTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.desc);
    });
  }
}

extension TranscriptQueryWhereDistinct
    on QueryBuilder<Transcript, Transcript, QDistinct> {
  QueryBuilder<Transcript, Transcript, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Transcript, Transcript, QDistinct> distinctByEndTimeSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endTimeSeconds');
    });
  }

  QueryBuilder<Transcript, Transcript, QDistinct> distinctByMeetingId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'meetingId');
    });
  }

  QueryBuilder<Transcript, Transcript, QDistinct> distinctBySegmentIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'segmentIndex');
    });
  }

  QueryBuilder<Transcript, Transcript, QDistinct> distinctBySpeakerLabel(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'speakerLabel', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Transcript, Transcript, QDistinct> distinctByStartTimeSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startTimeSeconds');
    });
  }

  QueryBuilder<Transcript, Transcript, QDistinct> distinctByText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'text', caseSensitive: caseSensitive);
    });
  }
}

extension TranscriptQueryProperty
    on QueryBuilder<Transcript, Transcript, QQueryProperty> {
  QueryBuilder<Transcript, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Transcript, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Transcript, double, QQueryOperations> endTimeSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endTimeSeconds');
    });
  }

  QueryBuilder<Transcript, int, QQueryOperations> meetingIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'meetingId');
    });
  }

  QueryBuilder<Transcript, int, QQueryOperations> segmentIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'segmentIndex');
    });
  }

  QueryBuilder<Transcript, String?, QQueryOperations> speakerLabelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'speakerLabel');
    });
  }

  QueryBuilder<Transcript, double, QQueryOperations>
      startTimeSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startTimeSeconds');
    });
  }

  QueryBuilder<Transcript, String, QQueryOperations> textProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'text');
    });
  }
}
