class ExportPreset {
  final String name;
  final String description;
  final String iconName;
  final int width;
  final int height;
  final int fps;
  final String aspectRatio;
  final String quality;
  final String format;

  const ExportPreset({
    required this.name,
    required this.description,
    required this.iconName,
    required this.width,
    required this.height,
    required this.fps,
    required this.aspectRatio,
    this.quality = 'high',
    this.format = 'mp4',
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'width': width, 'height': height,
    'fps': fps, 'aspect_ratio': aspectRatio,
    'quality': quality, 'format': format,
  };

  static const List<ExportPreset> available = [
    ExportPreset(name: 'YouTube', description: '1920x1080, 30fps', iconName: 'youtube', width: 1920, height: 1080, fps: 30, aspectRatio: '16:9'),
    ExportPreset(name: 'TikTok', description: '1080x1920, 30fps', iconName: 'tiktok', width: 1080, height: 1920, fps: 30, aspectRatio: '9:16'),
    ExportPreset(name: 'Instagram Reel', description: '1080x1920, 30fps', iconName: 'instagram', width: 1080, height: 1920, fps: 30, aspectRatio: '9:16'),
    ExportPreset(name: 'Instagram Square', description: '1080x1080, 30fps', iconName: 'instagram', width: 1080, height: 1080, fps: 30, aspectRatio: '1:1'),
    ExportPreset(name: 'Twitter/X', description: '1280x720, 30fps', iconName: 'twitter', width: 1280, height: 720, fps: 30, aspectRatio: '16:9'),
    ExportPreset(name: 'HD 1080p', description: '1920x1080, 24fps', iconName: 'film', width: 1920, height: 1080, fps: 24, aspectRatio: '16:9'),
    ExportPreset(name: 'HD 720p', description: '1280x720, 30fps', iconName: 'film', width: 1280, height: 720, fps: 30, aspectRatio: '16:9'),
    ExportPreset(name: '4K Ultra', description: '3840x2160, 60fps', iconName: 'film', width: 3840, height: 2160, fps: 60, quality: 'ultra', aspectRatio: '16:9'),
  ];
}

abstract class ProjectTemplate {
  String get name;
  String get description;
  int get width;
  int get height;
  int get fps;
  String get aspectRatio;

  Map<String, dynamic> generateTimeline();

  static final List<ProjectTemplate> all = [
    _VerticalVideoTemplate(),
    _HorizontalVideoTemplate(),
    _SquareVideoTemplate(),
  ];
}

class _VerticalVideoTemplate extends ProjectTemplate {
  @override
  String get name => 'عمودي (Vertical 9:16)';
  @override
  String get description => 'مثالي لـ TikTok، YouTube Shorts، Reels';
  @override
  int get width => 1080;
  @override
  int get height => 1920;
  @override
  int get fps => 30;
  @override
  String get aspectRatio => '9:16';

  @override
  Map<String, dynamic> generateTimeline() => {
    'project_name': 'مشروع عمودي جديد',
    'settings': {'width': width, 'height': height, 'fps': fps, 'aspect_ratio': aspectRatio},
    'tracks': {
      'video': [{'id': 'v_main', 'name': 'Video 1', 'index': 0, 'clips': []}],
      'audio': [{'id': 'a_main', 'name': 'Audio 1', 'index': 0, 'clips': []}],
      'subtitles': [{'id': 'sub_main', 'clips': []}],
      'overlays': [{'id': 'ov_main', 'clips': []}],
      'text': [{'id': 'txt_main', 'clips': []}],
    },
    'playheadSec': 0,
    'zoomLevel': 30,
  };
}

class _HorizontalVideoTemplate extends ProjectTemplate {
  @override
  String get name => 'أفقي (Horizontal 16:9)';
  @override
  String get description => 'مثالي لـ YouTube، Vimeo';
  @override
  int get width => 1920;
  @override
  int get height => 1080;
  @override
  int get fps => 30;
  @override
  String get aspectRatio => '16:9';

  @override
  Map<String, dynamic> generateTimeline() => _VerticalVideoTemplate().generateTimeline()
    ..['project_name'] = 'مشروع أفقي جديد'
    ..['settings']['width'] = width
    ..['settings']['height'] = height;
}

class _SquareVideoTemplate extends ProjectTemplate {
  @override
  String get name => 'مربع (Square 1:1)';
  @override
  String get description => 'مثالي لـ Instagram، Facebook';
  @override
  int get width => 1080;
  @override
  int get height => 1080;
  @override
  int get fps => 30;
  @override
  String get aspectRatio => '1:1';

  @override
  Map<String, dynamic> generateTimeline() => _VerticalVideoTemplate().generateTimeline()
    ..['project_name'] = 'مشروع مربع جديد'
    ..['settings']['width'] = width
    ..['settings']['height'] = height;
}
