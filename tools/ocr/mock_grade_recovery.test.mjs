import {test} from 'node:test';
import assert from 'node:assert/strict';
import {findMockGradeTargets,acceptMockGradeVotes} from '../../web/mock_grade_recovery.js';
function box(text,x,y){return {text_prediction:{text,confidence:.99},bounding_box:{points:[{x:x-.005,y:y-.004},{x:x+.005,y:y-.004},{x:x+.005,y:y+.004},{x:x-.005,y:y+.004}]}};}
function fixture(extra=[]){return {data:[{text_detections:[...['국어','수학','영어','한국사','사회','과학'].flatMap((s,i)=>[box(s,.1,.2+i*.04),box('220000',.6,.2+i*.04)]),box('3',.5,.2),box('2',.5,.24),box('8',.25,.2),box('7',.25,.24),...extra]}]};}
test('표 등급 열은 숫자 점수와 구분하고 누락된 두 영역만 선택',()=>{const targets=findMockGradeTargets(fixture());assert.deepEqual(targets.map(t=>t.subject),['영어','한국사']);assert.ok(targets.every(t=>Math.abs(t.x-.5)<.001));});
test('기존 영어 등급과 괄호 표현은 재인식 대상에서 제외',()=>{assert.deepEqual(findMockGradeTargets(fixture([box('6',.5,.28)])).map(t=>t.subject),['한국사']);assert.deepEqual(findMockGradeTargets(fixture([box('원점수에 의한 등급 (4)',.44,.32)])).map(t=>t.subject),['영어']);});
test('근거 없는 표와 잘못된 좌표는 추측하지 않는다',()=>{assert.deepEqual(findMockGradeTargets({}),[]);const r=fixture();r.data[0].text_detections=r.data[0].text_detections.filter(w=>w.text_prediction.text!=='한국사');assert.deepEqual(findMockGradeTargets(r),[]);});
test('충돌·낮은 신뢰도·단 한 번의 숫자는 반영하지 않는다',()=>{assert.equal(acceptMockGradeVotes([{text:'2',confidence:90}]),null);assert.equal(acceptMockGradeVotes([{text:'2',confidence:90},{text:'3',confidence:90}]),null);assert.equal(acceptMockGradeVotes([{text:'2',confidence:60},{text:'2',confidence:64}]),null);assert.equal(acceptMockGradeVotes([{text:'0',confidence:95},{text:'0',confidence:95}]),null);assert.deepEqual(acceptMockGradeVotes([{text:'7',confidence:85},{text:'7',confidence:70}]),{grade:7,confidence:85});});
