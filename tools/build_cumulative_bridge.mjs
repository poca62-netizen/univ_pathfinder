import {readFile, writeFile} from 'node:fs/promises';
const path = 'assets/data/admission_comparison.json';
const data = JSON.parse(await readFile(path, 'utf8'));
// Official PDF p.1, observed three-semester values only. Excludes shaded future projections.
data.cumulativeBridge = {
  source: '부산광역시교육청학력개발원 · 2026-09-04 · 고2 1학기까지 누적 분석, 98개교 15,978명',
  url: 'https://www.pen.go.kr/upload/main/na/bbs_2286/ntt_1179461/doc_dff1vceec=b5vbb=4av27=a9va5=873fv3b4bv08e8_v1921.pdf',
  scope: '2025 고1 1·2학기와 2026 고2 1학기의 석차등급 과목 학점가중평균. 모든 과목 등록에 대한 사용자 확인 필요. 지역 표본의 근사 대응이며 대학 환산식이 아님.',
  nodes: [[1,1.28],[1.04,1.38],[1.08,1.47],[1.16,1.68],[1.24,1.87],[1.33,2.07],[1.42,2.25],[1.5,2.39],[1.66,2.66],[1.83,2.98],[2,3.30],[2.16,3.58],[2.33,3.87],[2.5,4.18],[2.66,4.45],[2.83,4.72],[3,5.03],[3.16,5.30],[3.33,5.58],[3.5,5.87],[3.66,6.12],[3.83,6.40],[4,6.71],[4.16,6.99],[4.33,7.28],[4.5,7.54],[4.66,7.80],[4.83,8.12],[5,9]],
};
await writeFile(path, JSON.stringify(data, null, 2)+'\n');
