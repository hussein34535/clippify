import 'package:flutter/foundation.dart';

import '../results/rendered_clip.dart';

/// SharedPreferences key holding the directory of the last successful export.
/// Nothing writes it yet (v1) — AutoEditResultsScreen owns its own export
/// flow and is owned by another agent.
const String kLastOutputDirPrefKey = 'last_output_dir';

/// Session-scoped in-memory sink for auto-edit results on mobile.
///
/// TODO(mobile-v2): populate from the wizard flow once the progress→results
/// hand-off exposes a hook we can listen to without touching files owned by
/// other agents. Until then [instance] stays empty and ResultsPageMobile
/// renders an honest empty-state.
class InMemoryResultsStore extends ChangeNotifier {
  InMemoryResultsStore._();

  static final InMemoryResultsStore instance = InMemoryResultsStore._();

  List<RenderedClipData> _lastClips = const [];
  String? _compiledUrl;

  List<RenderedClipData> get lastClips => _lastClips;
  String? get compiledUrl => _compiledUrl;
  bool get hasResults => _lastClips.isNotEmpty || _compiledUrl != null;

  void setResults(List<RenderedClipData> clips, {String? compiledUrl}) {
    _lastClips = List<RenderedClipData>.unmodifiable(clips);
    _compiledUrl = compiledUrl;
    notifyListeners();
  }

  void clear() {
    _lastClips = const [];
    _compiledUrl = null;
    notifyListeners();
  }
}
