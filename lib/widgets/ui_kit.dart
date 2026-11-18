import 'package:flutter/material.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

/// 화면 안 묶음 제목. 설명(caption)은 한 줄 정도로 짧게.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.caption, this.trailing});
  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: text.bodySmall?.copyWith(fontSize: 13)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 연한 바탕의 안내 문구(아이콘 + 문장). 경고가 아니라 알아 두면 좋은 정보에 쓴다.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PathfinderTheme.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: PathfinderTheme.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: PathfinderTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 번호가 붙은 짧은 단계 안내(① 올리기 ② 확인 ③ 저장 …).
class StepStrip extends StatelessWidget {
  const StepStrip(this.steps, {super.key});
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, s) in steps.indexed) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PathfinderTheme.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                s,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: PathfinderTheme.ink,
                ),
              ),
            ],
          ),
          if (i < steps.length - 1)
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: PathfinderTheme.muted,
            ),
        ],
      ],
    );
  }
}

/// 둥근 사각 배경 위 아이콘.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(icon, size: size * .5, color: primary),
    );
  }
}

/// 아이콘 · 제목 · 설명 · 오른쪽 표시로 된 누를 수 있는 카드.
/// 화면 낭독기에는 제목을 버튼 이름으로, 설명을 따로 읽어 준다.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing = Icons.chevron_right,
    this.onTap,
    this.minHeight = 76,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final IconData trailing;
  final VoidCallback? onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      button: onTap != null,
      label: title,
      hint: subtitle,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: PathfinderTheme.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    IconBadge(icon!),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: PathfinderTheme.ink,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: PathfinderTheme.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    trailing,
                    size: 22,
                    color: trailing == Icons.chevron_right
                        ? PathfinderTheme.muted
                        : primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
