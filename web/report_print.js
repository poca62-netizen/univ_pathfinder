// 진학 컨설팅 리포트 인쇄: 앱이 만든 HTML 문서를 새 창에 열고 인쇄 창을 띄운다.
// 문서는 앱이 텍스트를 이스케이프해 만든 것만 받는다. 외부로 보내지 않는다.
window.univPrintReport = function (html) {
  const win = window.open('', '_blank');
  if (!win) return false; // 팝업 차단
  win.document.open();
  win.document.write(html);
  win.document.close();
  win.focus();
  // 글꼴·레이아웃이 그려진 뒤 인쇄 창을 연다.
  setTimeout(function () { win.print(); }, 300);
  return true;
};
