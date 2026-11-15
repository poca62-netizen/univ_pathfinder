class DocumentFileLimits {
  static const imageBytes = 5 * 1024 * 1024;
  static const pdfBytes = 20 * 1024 * 1024;
  static const maxPdfPages = 20;
  static int maxBytes(String mime) =>
      mime == 'application/pdf' ? pdfBytes : imageBytes;
  static String? validate(int size, String mime) {
    if (size <= 0) return '빈 파일은 처리할 수 없습니다.';
    if (size > maxBytes(mime)) {
      return mime == 'application/pdf'
          ? 'PDF는 20MB 이하여야 합니다.'
          : '이미지는 5MB 이하여야 합니다.';
    }
    return null;
  }
}
