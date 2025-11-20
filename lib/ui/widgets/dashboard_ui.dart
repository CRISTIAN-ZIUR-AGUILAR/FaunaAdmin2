import 'package:flutter/material.dart';

class CardShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool withShadow;

  const CardShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.withShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(.16)),
        boxShadow: withShadow
            ? [BoxShadow(blurRadius: 10, offset: const Offset(0, 2), color: Colors.black.withOpacity(0.05))]
            : null,
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget>? actions;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.actions,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: titleStyle)),
        if (actions != null) ...actions!,
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
