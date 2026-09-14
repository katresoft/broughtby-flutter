import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('the home page shows all three buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('I signed in'), findsOneWidget);
    expect(find.text('Show my code'), findsOneWidget);
    expect(find.text('Open my earnings screen'), findsOneWidget);
  });
}
