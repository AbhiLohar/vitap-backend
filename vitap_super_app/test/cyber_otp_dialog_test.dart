import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitap_super_app/widgets/cyber_otp_dialog.dart';

void main() {
  testWidgets('CyberOtpDialog renders security badge, title, tips, and 6 digit boxes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    String? verifiedOtp;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CyberOtpDialog(
            title: "Enter your code",
            subtitle: "We sent a 6-digit code to verify your session.",
            onVerify: (otp) async {
              verifiedOtp = otp;
              return null;
            },
          ),
        ),
      ),
    );

    // Verify header tags and tips
    expect(find.text("SECURITY CHECK"), findsOneWidget);
    expect(find.text("Enter your code"), findsOneWidget);
    expect(find.text("Enter the 6-digit code"), findsOneWidget);
    expect(find.text("Tip: paste to fill every box at once."), findsOneWidget);
    expect(find.text("Verify Code"), findsOneWidget);

    // Enter 6 digits into the backing text field
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    await tester.enterText(textField, "123456");
    await tester.pump();

    // Verify digits are displayed
    expect(find.text("1"), findsOneWidget);
    expect(find.text("2"), findsOneWidget);
    expect(find.text("3"), findsOneWidget);
    expect(find.text("4"), findsOneWidget);
    expect(find.text("5"), findsOneWidget);
    expect(find.text("6"), findsOneWidget);

    // Verify onVerify was triggered
    expect(verifiedOtp, equals("123456"));
  });

  testWidgets('CyberOtpDialog configures numeric keypad and handles backspace deletion', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CyberOtpDialog(
            autoSubmit: false,
          ),
        ),
      ),
    );

    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    final TextField textFieldWidget = tester.widget<TextField>(textFieldFinder);

    // Verify keyboard is set to numeric number pad
    expect(textFieldWidget.keyboardType, equals(const TextInputType.numberWithOptions(decimal: false, signed: false)));
    expect(textFieldWidget.autofocus, isTrue);

    // Enter partial digits "45"
    await tester.enterText(textFieldFinder, "45");
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Text && w.data == "4"), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == "5"), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == "6"), findsNothing);

    // Simulate backspacing "5" -> leaves "4"
    await tester.enterText(textFieldFinder, "4");
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Text && w.data == "4"), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == "5"), findsNothing);

    // Tap on the text field
    await tester.tap(textFieldFinder);
    await tester.pump();
  });
}
