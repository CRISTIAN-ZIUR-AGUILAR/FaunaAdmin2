import 'dart:async';
import 'package:flutter/widgets.dart';

class NavSafe {
  static void to(BuildContext context, String route, {Object? arguments}) {
    final nav = Navigator.of(context);
    scheduleMicrotask(() {
      if (!nav.mounted) return;
      if (ModalRoute.of(nav.context)?.settings.name == route) return;
      nav.pushNamed(route, arguments: arguments);
    });
  }

  static void replace(BuildContext context, String route, {Object? arguments}) {
    final nav = Navigator.of(context);
    scheduleMicrotask(() {
      if (!nav.mounted) return;
      if (ModalRoute.of(nav.context)?.settings.name == route) return;
      nav.pushReplacementNamed(route, arguments: arguments);
    });
  }

  static void toAndRemoveAll(BuildContext context, String route, {Object? arguments}) {
    final nav = Navigator.of(context);
    scheduleMicrotask(() {
      if (!nav.mounted) return;
      nav.pushNamedAndRemoveUntil(route, (r) => false, arguments: arguments);
    });
  }

  static void pop(BuildContext context, [Object? result]) {
    final nav = Navigator.of(context);
    scheduleMicrotask(() {
      if (!nav.mounted) return;
      if (nav.canPop()) nav.pop(result);
    });
  }
}
