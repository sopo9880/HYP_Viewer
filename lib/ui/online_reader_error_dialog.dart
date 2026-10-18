import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/online_reader_failure.dart';
import '../l10n/app_localizations.dart';

enum OnlineReaderErrorAction { retry, web }

/// Only trusted fields and fixed error codes can appear in copied reports.
/// Raw response bodies, signed image URLs and cookies are never included.
class OnlineReaderErrorText {
  static String stage(AppLocalizations l, OnlineReaderStage stage) {
    switch (stage) {
      case OnlineReaderStage.metadata: return l.readerOnlineStageMetadata;
      case OnlineReaderStage.routing: return l.readerOnlineStageRouting;
      case OnlineReaderStage.image: return l.readerOnlineStageImage;
      case OnlineReaderStage.reader: return l.readerOnlineStageReader;
    }
  }

  static String reason(AppLocalizations l, OnlineReaderFailure failure) {
    switch (failure.code) {
      case 'META_ID_INVALID':
      case 'META_ID_MISSING': return l.readerOnlineReasonIdMissing;
      case 'META_ID_MISMATCH': return l.readerOnlineReasonIdMismatch;
      case 'META_FILES_MISSING': return l.readerOnlineReasonFilesMissing;
      case 'META_FILES_TYPE': return l.readerOnlineReasonFilesType;
      case 'META_FILES_EMPTY': return l.readerOnlineReasonFilesEmpty;
      case 'META_PAGE_LIMIT': return l.readerOnlineReasonPageLimit;
      case 'META_JSON_INVALID': return l.readerOnlineReasonJsonInvalid;
      case 'META_RESPONSE_INVALID': return l.readerOnlineReasonMetaInvalid;
      case 'META_IMAGE_ENTRY_INVALID': return l.readerOnlineReasonEntryInvalid;
      case 'META_HTTP_ERROR':
      case 'ROUTING_HTTP_ERROR': return l.readerOnlineReasonMetaHttp;
      case 'META_DNS_FAILURE':
      case 'ROUTING_DNS_FAILURE':
      case 'IMAGE_DNS_FAILURE': return l.readerOnlineReasonDns;
      case 'META_TIMEOUT':
      case 'ROUTING_TIMEOUT':
      case 'IMAGE_TIMEOUT': return l.readerOnlineReasonTimeout;
      case 'META_SIZE_LIMIT':
      case 'ROUTING_SIZE_LIMIT':
      case 'IMAGE_SIZE_LIMIT': return l.readerOnlineReasonSize;
      case 'ROUTING_FORMAT_CHANGED': return l.readerOnlineReasonRouting;
      case 'ROUTING_HASH_INVALID': return l.readerOnlineReasonImageHash;
      case 'IMAGE_HTTP_ERROR': return l.readerOnlineReasonImageHttp;
      case 'IMAGE_HOST_BLOCKED':
      case 'META_HOST_BLOCKED': return l.readerOnlineReasonHostBlocked;
      case 'IMAGE_CONTENT_TYPE': return l.readerOnlineReasonContentType;
      case 'IMAGE_FORMAT_INVALID': return l.readerOnlineReasonImageFormat;
      default: return l.readerOnlineReasonUnexpected;
    }
  }

  static String report(AppLocalizations l, OnlineReaderFailure failure) {
    return <String>[
      l.readerOnlineFailureTitle,
      l.readerOnlineFieldWorkId + ': ' + failure.workId,
      l.readerOnlineFieldStage + ': ' + stage(l, failure.stage),
      l.readerOnlineFieldCode + ': ' + failure.code,
      if (failure.returnedWorkId != null)
        l.readerOnlineReturnedId + ': ' + failure.returnedWorkId!,
      if (failure.retried) l.readerOnlineRetried,
      if (failure.httpStatus != null)
        l.readerOnlineFieldHttp + ': HTTP ' + failure.httpStatus.toString(),
      if (failure.actualType != null)
        l.readerOnlineFieldType + ': ' + failure.actualType!,
      if (failure.page != null)
        l.readerOnlineFieldPage + ': ' + failure.page.toString(),
      if (failure.host != null)
        l.readerOnlineFieldHost + ': ' + failure.host!,
      l.readerOnlineFieldReason + ': ' + reason(l, failure),
    ].join('\n');
  }
}

Future<OnlineReaderErrorAction?> showOnlineReaderErrorDialog(
  BuildContext context, OnlineReaderFailure failure,
) => showDialog<OnlineReaderErrorAction>(
  context: context,
  builder: (_) => OnlineReaderErrorDialog(failure: failure),
);

class OnlineReaderErrorDialog extends StatefulWidget {
  final OnlineReaderFailure failure;
  const OnlineReaderErrorDialog({super.key, required this.failure});

  @override
  State<OnlineReaderErrorDialog> createState() =>
      _OnlineReaderErrorDialogState();
}

class _OnlineReaderErrorDialogState extends State<OnlineReaderErrorDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final error = widget.failure;
    final details = OnlineReaderErrorText.report(l, error);
    return AlertDialog(
      key: const Key('online-reader-failure-dialog'),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.orangeAccent),
        const SizedBox(width: 8),
        Flexible(child: Text(l.readerOnlineFailureTitle)),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.readerOnlineFailureIntro),
            const SizedBox(height: 14),
            SelectableText(details,
              key: const Key('online-reader-diagnostic-text')),
            const SizedBox(height: 12),
            Text(l.readerOnlineFailureHelp,
              style: Theme.of(context).textTheme.bodySmall),
          ],
        )),
      ),
      actions: [
        TextButton.icon(
          key: const Key('online-reader-copy-diagnostic'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: details));
            if (mounted) setState(() => _copied = true);
          },
          icon: const Icon(Icons.copy),
          label: Text(_copied ? l.readerOnlineCopied : l.readerOnlineCopy),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        OutlinedButton.icon(
          key: const Key('online-reader-retry'),
          onPressed: () => Navigator.of(context)
              .pop(OnlineReaderErrorAction.retry),
          icon: const Icon(Icons.refresh),
          label: Text(l.readerOnlineRetry),
        ),
        FilledButton.icon(
          key: const Key('online-reader-open-web'),
          onPressed: () => Navigator.of(context)
              .pop(OnlineReaderErrorAction.web),
          icon: const Icon(Icons.open_in_new),
          label: Text(l.readerOnlineWebReader),
        ),
      ],
    );
  }
}
