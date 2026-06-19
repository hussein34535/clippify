class Workspace {
  final String id;
  final String name;
  final String description;
  final Map<String, double> fractions;

  const Workspace({
    required this.id,
    required this.name,
    required this.description,
    required this.fractions,
  });
}

class WorkspaceManager {
  String _currentId = 'editing';

  final Map<String, Workspace> _workspaces = {
    'editing': const Workspace(
      id: 'editing',
      name: 'Editing',
      description: 'Focus on timeline',
      fractions: {'left': 0.2, 'right': 0.25, 'bottom': 0.45},
    ),
    'color': const Workspace(
      id: 'color',
      name: 'Color',
      description: 'Focus on color grading',
      fractions: {'left': 0.15, 'right': 0.35, 'bottom': 0.3},
    ),
    'audio': const Workspace(
      id: 'audio',
      name: 'Audio',
      description: 'Focus on audio',
      fractions: {'left': 0.2, 'right': 0.2, 'bottom': 0.65},
    ),
    'effects': const Workspace(
      id: 'effects',
      name: 'Effects',
      description: 'Focus on effects',
      fractions: {'left': 0.25, 'right': 0.3, 'bottom': 0.4},
    ),
    'minimal': const Workspace(
      id: 'minimal',
      name: 'Minimal',
      description: 'Minimum panels',
      fractions: {'left': 0.1, 'right': 0.15, 'bottom': 0.25},
    ),
  };

  String get currentId => _currentId;
  Workspace get current => _workspaces[_currentId] ?? _workspaces['editing']!;
  Map<String, double> get fractions => current.fractions;

  void switchTo(String id) {
    if (_workspaces.containsKey(id)) {
      _currentId = id;
    }
  }
}
