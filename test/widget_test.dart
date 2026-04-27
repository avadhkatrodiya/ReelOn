import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelontask/app.dart';

void main() {
  testWidgets('boots app shell', (tester) async {
    await tester.pumpWidget(const ReelOnApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
