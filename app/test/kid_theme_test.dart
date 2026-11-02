import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/classroom.dart';
import 'package:super_mom/content.dart';
import 'package:super_mom/models.dart';

void main() {
  test('older children may connect Classroom unless Mom switches it off', () {
    final young = Kid(id: 'a', name: 'Yusuf', age: 7);
    final older = Kid(id: 'b', name: 'Aisha', age: 11);
    expect(young.mayConnectClassroom, isFalse);
    expect(older.mayConnectClassroom, isTrue);
    young.classroomSelf = true;
    older.classroomSelf = false;
    expect(young.mayConnectClassroom, isTrue);
    expect(older.mayConnectClassroom, isFalse);
  });

  test(
    "Mom's choice is saved with the profile; the child's own import is not",
    () {
      final k = Kid(id: 'a', name: 'Aisha', age: 11)
        ..classroomSelf = false
        ..selfClassroomEmail = 'aisha@school.org';
      final json = k.profileJson();
      expect(json['classroomSelf'], isFalse);
      expect(json.containsKey('selfClassroomEmail'), isFalse);
      final back = Kid.fromJson({...json, 'id': 'a'});
      expect(back.classroomSelf, isFalse);
      expect(
        Kid(
          id: 'c',
          name: 'X',
          age: 9,
        ).profileJson().containsKey('classroomSelf'),
        isFalse,
      );
    },
  );

  test(
    'every theme has a picture and two colours; unknown themes fall back',
    () {
      for (final t in kidThemes.values) {
        expect(t.emoji, isNotEmpty);
        expect(t.color, isNot(t.accent));
      }
      expect(
        themeOf(Kid(id: 'a', name: 'A', age: 8, theme: 'old')).name,
        'Ocean',
      );
      // Themes saved by earlier versions still exist.
      for (final old in ['rose', 'ocean', 'garden', 'sunset', 'galaxy']) {
        expect(kidThemes.containsKey(old), isTrue);
      }
    },
  );

  test('only the chosen Classroom classes are read', () {
    const all = [
      ClassroomCourse('g3', 'Grade 3'),
      ClassroomCourse('g5', 'Grade 5'),
      ClassroomCourse('g6', 'Grade 6'),
    ];
    expect(coursesToRead(all, {}), {'g3', 'g5', 'g6'});
    expect(coursesToRead(all, {'g5'}), {'g5'});
    // A class that ended is ignored; if none are left, read them all.
    expect(coursesToRead(all, {'g5', 'old'}), {'g5'});
    expect(coursesToRead(all, {'old'}), {'g3', 'g5', 'g6'});
  });

  test("Mom's chosen classes are saved with the child's profile", () {
    final k = Kid(id: 'a', name: 'Aisha', age: 11)..classroomCourseIds = ['g5'];
    final back = Kid.fromJson({...k.profileJson(), 'id': 'a'});
    expect(back.classroomCourseIds, ['g5']);
  });
}
