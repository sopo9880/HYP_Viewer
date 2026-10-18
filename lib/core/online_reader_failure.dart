import 'dart:async';
import 'dart:io';

/// A stage and safe error code for diagnostics, independent of site wording.
enum OnlineReaderStage { metadata, routing, image, reader }

/// Carries only a work ID and trusted diagnostic metadata. Source response
/// bodies, cookies and signed image URLs are never retained in diagnostics.
/// FormatException inheritance preserves the existing reader contract.
class OnlineReaderFailure extends FormatException {
  final String code;
  final OnlineReaderStage stage;
  final String workId;
  final int? httpStatus;
  final String? actualType;
  final String? host;
  final int? page;
  /// Numeric-only, verified for display; never the raw server payload.
  final String? returnedWorkId;
  final bool retried;

  OnlineReaderFailure({
    required this.code,
    required this.stage,
    required this.workId,
    required String description,
    this.httpStatus,
    this.actualType,
    this.host,
    this.page,
    this.returnedWorkId,
    this.retried = false,
  }) : super(description +
        (httpStatus == null ? '' : ' · HTTP ' + httpStatus.toString()));

  static String jsonType(Object? value) {
    if (value == null) return 'null';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    if (value is String) return 'string';
    if (value is num) return 'number';
    if (value is bool) return 'boolean';
    return 'unknown';
  }

  /// Classify network/image exceptions without embedding raw exception text.
  static OnlineReaderFailure classify(Object error, {
    required String workId,
    required OnlineReaderStage stage,
    String? host,
    int? page,
  }) {
    if (error is OnlineReaderFailure) return error;
    final raw = error.toString();
    final prefix = stage == OnlineReaderStage.image ? 'IMAGE'
        : stage == OnlineReaderStage.routing ? 'ROUTING' : 'META';
    if (error is TimeoutException || raw.contains('TimeoutException')) {
      return OnlineReaderFailure(
        code: prefix + '_TIMEOUT', stage: stage, workId: workId,
        host: host, page: page,
        description: '서버 요청 시간이 초과됐어.');
    }
    if (error is SocketException ||
        raw.contains('Failed host lookup') ||
        raw.contains('No address associated with hostname') ||
        raw.contains('Name or service not known')) {
      return OnlineReaderFailure(
        code: prefix + '_DNS_FAILURE', stage: stage, workId: workId,
        host: host, page: page, description: '서버 DNS 조회 실패');
    }
    final statusText = RegExp(r'(?:HTTP[\s:]*|응답하지 않았어:\s*)(\d{3})')
        .firstMatch(raw)?.group(1);
    final status = statusText == null ? null : int.tryParse(statusText);
    if (status != null) {
      return OnlineReaderFailure(
        code: prefix + '_HTTP_ERROR', stage: stage, workId: workId,
        httpStatus: status, host: host, page: page,
        description: '서버가 오류 응답을 반환했어.');
    }
    if (error is FormatException) {
      final text = error.message;
      if (stage == OnlineReaderStage.image &&
          text.contains('이미지가 아닌 파일')) {
        return OnlineReaderFailure(
          code: 'IMAGE_CONTENT_TYPE', stage: stage, workId: workId,
          host: host, page: page,
          description: '서버가 이미지가 아닌 파일을 반환했어.');
      }
      if (text.contains('너무 커') || text.contains('크기를 초과')) {
        return OnlineReaderFailure(
          code: prefix + '_SIZE_LIMIT', stage: stage, workId: workId,
          host: host, page: page, description: '서버 응답이 너무 커.');
      }
      if (stage == OnlineReaderStage.routing) {
        return OnlineReaderFailure(
          code: 'ROUTING_FORMAT_CHANGED', stage: stage, workId: workId,
          host: host, page: page,
          description: '서버 이미지 주소 규칙을 해석하지 못했어.');
      }
      if (stage == OnlineReaderStage.image) {
        return OnlineReaderFailure(
          code: 'IMAGE_FORMAT_INVALID', stage: stage, workId: workId,
          host: host, page: page,
          description: '서버 이미지 데이터 형식을 해석하지 못했어.');
      }
    }
    return OnlineReaderFailure(
      code: stage == OnlineReaderStage.image ? 'IMAGE_REQUEST_FAILED'
          : stage == OnlineReaderStage.routing ? 'ROUTING_FORMAT_CHANGED'
          : stage == OnlineReaderStage.reader ? 'READER_UNEXPECTED'
          : 'META_REQUEST_FAILED',
      stage: stage, workId: workId, host: host, page: page,
      description: '읽기 중 예상하지 못한 오류가 발생했어.');
  }
}
