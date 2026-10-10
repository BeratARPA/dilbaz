import 'package:dilbaz_app/features/placement/presentation/level_text.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('a level reads as one level, a range or a level and above (I-04)', () {
    expect(levelText(trStrings, LevelEstimate.at(CefrLevel.a2)), 'A2');
    expect(
      levelText(trStrings, LevelEstimate.between(CefrLevel.a1, CefrLevel.a2)),
      trStrings.levelRange('A1', 'A2'),
    );
    expect(
      levelText(trStrings, LevelEstimate.between(CefrLevel.b2, CefrLevel.c2)),
      trStrings.levelAndAbove('B2'),
    );
    expect(levelText(trStrings, LevelEstimate.at(CefrLevel.c2)), 'C2');
  });
}
