import 'package:univ_pathfinder/models/extraction_result.dart';

abstract class ExtractionService {
  Future<ExtractionResult> extract({required String sourceIdentifier});
  bool get isReady;
}

class ExtractionServiceException implements Exception {
  final String message;
  const ExtractionServiceException(this.message);
  @override
  String toString() => 'ExtractionServiceException: $message';
}
