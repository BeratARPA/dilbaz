import 'dart:io';

/// Fails when line coverage of hand-written `lib/` code is below a minimum.
///
/// Usage: `dart run tool/check_coverage.dart [lcov.info] [minimum-percent]`
/// Generated files (`*.g.dart`, `*.freezed.dart`) are excluded.
void main(List<String> args) {
  final lcov = File(args.isNotEmpty ? args[0] : 'coverage/lcov.info');
  final minimum = args.length > 1 ? double.parse(args[1]) : 90.0;
  final libFile = RegExp('(^|/)lib/');

  var found = 0;
  var hit = 0;
  var include = false;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3).replaceAll(r'\', '/');
      include =
          libFile.hasMatch(path) &&
          !path.endsWith('.g.dart') &&
          !path.endsWith('.freezed.dart');
    } else if (include && line.startsWith('DA:')) {
      found++;
      if (int.parse(line.substring(3).split(',')[1]) > 0) hit++;
    }
  }

  final percent = found == 0 ? 0.0 : 100 * hit / found;
  stdout.writeln(
    'Line coverage (lib): ${percent.toStringAsFixed(1)}% ($hit/$found)',
  );
  if (percent < minimum) {
    stderr.writeln('Below the required $minimum%.');
    exitCode = 1;
  }
}
