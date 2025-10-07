// lib/utils/normalize.dart
import 'package:diacritic/diacritic.dart';

String normalize(String s) {
  return removeDiacritics(s).toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}
