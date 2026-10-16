/// Keeps a successfully saved link-finder draft until its user leaves Home.
/// Unsaved edits, a newly pasted link, and the API key are never discarded.
class FinderResetPolicy {
  List<String>? _saved;

  void recordSuccessfulSave(Iterable<String> fields) {
    _saved = List<String>.from(fields);
  }

  void reset() => _saved = null;

  bool consumeOnLeave(Iterable<String> currentFields) {
    final snapshot = _saved;
    _saved = null;
    if (snapshot == null) return false;
    final now = currentFields.toList(growable: false);
    if (snapshot.length != now.length) return false;
    for (var i = 0; i < snapshot.length; i++) {
      if (snapshot[i] != now[i]) return false;
    }
    return true;
  }
}
