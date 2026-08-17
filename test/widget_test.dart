import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_gallery/app.dart';

void main() {
  testWidgets('앱 기동 시 홈 화면 렌더링', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FamilyGalleryApp()),
    );

    expect(find.text('가족 갤러리'), findsWidgets);
  });
}
