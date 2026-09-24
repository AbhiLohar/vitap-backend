import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitap_super_app/screens/main_screen.dart';

void main() {
  testWidgets('Bottom navigation bar smoke test renders all 5 tabs', (WidgetTester tester) async {
    // Set a compact screen size to test responsiveness (e.g. 360 x 640)
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: MainScreen(username: 'TEST_USER'),
      ),
    );

    // Verify all 5 tab labels are rendered
    expect(find.text('Timetable'), findsWidgets);
    expect(find.text('Attendance'), findsWidgets);
    expect(find.text('More'), findsWidgets);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
