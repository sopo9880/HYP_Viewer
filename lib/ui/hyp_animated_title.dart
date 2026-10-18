import 'dart:async';
import 'package:flutter/material.dart';

/// How an overflowing work title should reveal its hidden text.
///
/// The default remains an ellipsis until the reader taps the title. Verified
/// candidate results are the only surface that loops automatically. Full
/// titles and reduced-motion environments never animate.
enum HypTitleMotion { onTap, automatic, static }

/// A one-line title that scrolls *within its own bounds*, without moving the
/// card or stealing taps from the cover, selection checkbox, or action menu.
class HypAnimatedTitle extends StatefulWidget {
  final String title;
  final TextStyle? style;
  final HypTitleMotion motion;
  final VoidCallback? onTapOverride;
  final bool tooltip;

  const HypAnimatedTitle({
    super.key,
    required this.title,
    this.style,
    this.motion = HypTitleMotion.onTap,
    this.onTapOverride,
    this.tooltip = true,
  });

  @override
  State<HypAnimatedTitle> createState() => _HypAnimatedTitleState();
}

class _HypAnimatedTitleState extends State<HypAnimatedTitle> {
  final ScrollController _scroll = ScrollController();
  Timer? _delay;
  Completer<void>? _waiter;
  int _generation = 0;
  bool _moving = false;

  void _cancelWait() {
    _delay?.cancel();
    _delay = null;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> _wait(Duration duration) {
    _cancelWait();
    final waiter = Completer<void>();
    _waiter = waiter;
    _delay = Timer(duration, () {
      _delay = null;
      if (!waiter.isCompleted) waiter.complete();
      if (identical(_waiter, waiter)) _waiter = null;
    });
    return waiter.future;
  }

  void _stop() {
    _generation++;
    _cancelWait();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _moving = false;
  }

  @override
  void didUpdateWidget(covariant HypAnimatedTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.motion != widget.motion ||
        oldWidget.style != widget.style) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    _scroll.dispose();
    super.dispose();
  }

  bool _allowed() {
    if (!mounted || widget.motion == HypTitleMotion.static) return false;
    if (!TickerMode.of(context)) return false;
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) return false;
    return true;
  }

  bool _stillCurrent(int run) => mounted && run == _generation && _allowed();

  Duration _duration(double distance) => Duration(
      milliseconds: (distance / 38 * 1000).round().clamp(850, 16000).toInt());

  Future<void> _animate(int run, {required bool repeat}) async {
    try {
      while (_stillCurrent(run) && _scroll.hasClients) {
        final end = _scroll.position.maxScrollExtent;
        if (end < 1) break;
        await _wait(const Duration(milliseconds: 700));
        if (!_stillCurrent(run) || !_scroll.hasClients) break;
        await _scroll.animateTo(end,
            duration: _duration(end), curve: Curves.linear);
        if (!_stillCurrent(run)) break;
        await _wait(const Duration(milliseconds: 1000));
        if (!_stillCurrent(run) || !_scroll.hasClients) break;
        await _scroll.animateTo(0,
            duration: const Duration(milliseconds: 430),
            curve: Curves.easeOutCubic);
        if (!repeat) break;
        await _wait(const Duration(milliseconds: 1300));
      }
    } catch (_) {
      // A cancelled scroll (navigation, resize or disposal) is harmless.
    } finally {
      if (mounted && run == _generation && !repeat) {
        setState(() => _moving = false);
      }
    }
  }

  void _playOnce() {
    if (!_allowed() || widget.motion != HypTitleMotion.onTap) return;
    _stop();
    setState(() => _moving = true);
    final run = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stillCurrent(run)) unawaited(_animate(run, repeat: false));
    });
  }

  void _startAutomatic() {
    if (_moving || !_allowed()) return;
    _moving = true;
    final run = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stillCurrent(run)) unawaited(_animate(run, repeat: true));
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rawText = widget.title;
      final title = rawText.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final available = constraints.maxWidth;
      final enabled = _allowed();
      final painter = TextPainter(
        text: TextSpan(text: title, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout(maxWidth: double.infinity);
      final titleWidth = painter.width;
      final titleHeight = painter.height;
      painter.dispose();
      final overflows = available.isFinite && available > 0 &&
          titleWidth > available + 1;

      if (widget.motion == HypTitleMotion.automatic &&
          enabled && overflows && !_moving) {
        _startAutomatic();
      }
      // Never run animations when all text fits, and always offer the full
      // title to semantics and mouse hover independently of visual clipping.
      final scrolling = overflows && enabled && _moving;
      final label = scrolling
          ? SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Text(title, maxLines: 1, softWrap: false, style: widget.style),
            )
          : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              softWrap: false, style: widget.style);
      Widget child = SizedBox(
        width: available.isFinite ? available : null,
        height: titleHeight,
        child: label,
      );
      // An ordinary title tap must never bubble through to the cover/card
      // reader action, even when the text happens to fit without scrolling.
      final titleTap = widget.onTapOverride ??
          (widget.motion == HypTitleMotion.onTap
              ? (enabled && overflows ? _playOnce : () {}) : null);
      if (titleTap != null) {
        child = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: titleTap,
            child: child,
          ),
        );
      }
      if (widget.tooltip && title.isNotEmpty) {
        child = Tooltip(
          message: rawText,
          waitDuration: const Duration(milliseconds: 450),
          child: child,
        );
      }
      return Semantics(
        label: rawText,
        button: titleTap != null,
        onTap: titleTap,
        excludeSemantics: true,
        child: child,
      );
    },
  );
}
