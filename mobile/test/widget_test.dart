import 'package:flutter_test/flutter_test.dart';

import 'package:birds/app.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BirdsApp());
    expect(find.text('Birds'), findsOneWidget);
  });
}
