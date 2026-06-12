import 'package:flutter_test/flutter_test.dart';

import 'package:hgsc/main.dart';

void main() {
  testWidgets('shows localized HGSC splash on startup', (tester) async {
    await tester.pumpWidget(const CsacMobileApp());
    await tester.pump();

    expect(find.text('哈小信'), findsOneWidget);
  });
}
