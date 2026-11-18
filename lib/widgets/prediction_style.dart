import 'package:flutter/material.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

/// 예측 단계별 색. 색만으로 뜻을 전하지 않도록 늘 글자(안정·적정…)와 함께 쓴다.
Color levelColor(PredictionLevel level) => switch (level) {
  PredictionLevel.safe => const Color(0xFF2E7D57),
  PredictionLevel.fit => const Color(0xFF2266A8),
  PredictionLevel.reach => const Color(0xFFB86E00),
  PredictionLevel.hard => const Color(0xFFB0443A),
  PredictionLevel.unknown => const Color(0xFF7D8B88),
};

/// 지원 조합의 칸 이름(상향·적정·안정·가군…)에 맞는 색. 정시 군은 중립색.
Color slotColor(String slot) {
  for (final l in PredictionLevel.values) {
    if (l.label == slot) return levelColor(l);
  }
  return PathfinderTheme.accent;
}

/// 글자 + 연한 바탕의 작은 표시(안정·적정·가군 …).
class LevelBadge extends StatelessWidget {
  const LevelBadge(this.label, {super.key, required this.color, this.width});
  final String label;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 단계별 개수를 한 줄 막대와 범례로 보여 준다.
class LevelDistribution extends StatelessWidget {
  const LevelDistribution(this.counts, {super.key});
  final Map<PredictionLevel, int> counts;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final l in PredictionLevel.values)
        if ((counts[l] ?? 0) > 0) l,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, l) in shown.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: counts[l]!,
                      child: ColoredBox(color: levelColor(l)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final l in shown)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: levelColor(l),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${l.label} ${counts[l]}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PathfinderTheme.ink,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
