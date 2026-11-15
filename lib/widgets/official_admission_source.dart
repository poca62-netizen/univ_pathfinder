import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/services/kakao_map.dart';

/// Official 2028 admission-plan pages checked on 2026-11-06 (also listed on the data-sources screen).
const officialPlanLinks2028 = {
  '서울대': 'https://admission.snu.ac.kr/undergraduate/notice?bbsidx=168854&md=v',
  '연세대(서울)': 'https://admission.yonsei.ac.kr/seoul/admission/html/counsel/noticeView.asp?BBS_NO=3493',
  '고려대(서울)': 'https://oku.korea.ac.kr/oku/cms/FR_BBS_CON/BoardView.do?BBS_SEQ=1791&BOARD_SEQ=5&CONTENTS_NO=1&MENU_ID=750&SITE_NO=2',
  '경희대': 'https://iphak.khu.ac.kr/detail.do?board_seq=17147&categoryid=0&menuurl=wvOt10B5et6zMa%2FM59G%2BxQ%3D%3D&pageNo=1',
  '숭실대': 'https://iphak.ssu.ac.kr/board/exam_view.asp?number=23',
};

class AdmissionTrackReview extends StatelessWidget {
  const AdmissionTrackReview({super.key, required this.track});
  final AdmissionTrack track;

  @override
  Widget build(BuildContext context) {
    if (track.officialReview.isEmpty) {
      return const Text('전형별 원문 대조 미확인');
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('공식 시행계획 대조 근거'),
      subtitle: Text('확인일 ${track.officialReview['확인일']}'),
      children: [
        for (final field in track.officialReview.entries.where(
          (entry) => entry.key != '확인일',
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: Text('${field.key} · ${field.value}'),
            ),
          ),
        if (track.university == '서울대')
          SelectableText(
            '서울대 배포본 재게시 · https://jinhak.jje.go.kr/board.do?act=read&bbsid=030500&bbsidx=3394&page=1&searchType=TITLE',
          ),
      ],
    );
  }
}

class OfficialAdmissionSource extends StatelessWidget {
  const OfficialAdmissionSource({
    super.key,
    required this.university,
    required this.year,
  });

  final String university;
  final int? year;

  @override
  Widget build(BuildContext context) {
    final source = year == 2028 ? officialPlanLinks2028[university] : null;
    if (source == null) return const Text('대학별 공식 원문 링크 미확인');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('2028학년도 공식 시행계획 · 링크 확인일 2026-11-06'),
        const Text('전형 상세·일정은 최종 모집요강에서 확인하세요.'),
        TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('입학처 시행계획 열기'),
          onPressed: () {
            if (openAdmissionSource(Uri.parse(source))) return;
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('입학처 시행계획 링크'),
                content: SelectableText(source),
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: source));
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        // The selectable URL stays available for manual copying.
                      }
                    },
                    child: const Text('링크 복사'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
