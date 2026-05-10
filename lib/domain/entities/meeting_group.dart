import 'package:isar/isar.dart';

part 'meeting_group.g.dart';

@collection
class MeetingGroup {
  Id id = Isar.autoIncrement;

  late String name;

  @Index()
  late DateTime createdAt;
}
