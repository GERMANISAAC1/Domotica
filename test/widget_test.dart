import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domotica/main.dart';

void main() {
  testWidgets('La app arranca', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      DomoticaApp(notifier: DispositivosNotifier([], prefs)),
    );
    await tester.pump();
    expect(find.text('Control'), findsWidgets);
  });
}
