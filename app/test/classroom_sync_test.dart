import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/screens/school_screens.dart';

void main() {
  test('shows when Classroom was last checked', () {
    final now = DateTime(2026, 11, 3, 15, 0);
    expect(lastCheckedText(null, now), '');
    expect(
      lastCheckedText(DateTime(2026, 11, 3, 10, 42), now),
      contains('10:42'),
    );
    expect(
      lastCheckedText(DateTime(2026, 11, 2, 20, 5), now),
      startsWith('Last checked yesterday'),
    );
    expect(
      lastCheckedText(DateTime(2026, 10, 28, 9, 0), now),
      'Last checked Wed 28 Oct.',
    );
  });
}
