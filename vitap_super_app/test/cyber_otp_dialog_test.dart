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
}
