import 'package:flutter/material.dart';

abstract final class TimelineConstants {
  TimelineConstants._();

  // Track heights
  static const double videoTrackHeight = 78;
  static const double audioTrackHeight = 58;
  static const double overlayTrackHeight = 48;
  static const double subtitleTrackHeight = 38;
  static const double textTrackHeight = 50;
  static const double nestedTrackHeight = 58;
  static const double trackGap = 4;
  static const double tracksBottomPadding = 12;

  // Sidebar
  static const double sidebarWidth = 110;

  // Zoom
  static const double minZoom = 1.0;
  static const double maxZoom = 500.0;
  static const double defaultZoom = 30.0;

  // Grid & Ruler
  static const int gridIntervalSec = 5;
  static const int rulerMajorTickInterval = 5;

  // Playhead
  static const double playheadWidth = 2;

  // Snap
  static const double snapTolerancePixels = 8.0;

  // Border
  static const double borderWidth = 0.5;

  // Track colors (with alpha)
  static const Color videoTrackColor = Color(0xFF7c6af7);
  static const Color audioTrackColor = Color(0xFF0d9488);
  static const Color overlayTrackColor = Color(0xFFc2410c);
  static const Color subtitleTrackColor = Color(0xFF059669);
  static const Color textTrackColor = Color(0xFFEC4899);
  static const Color nestedTrackColor = Color(0xFF7C3AED);

  // Toolbar
  static const double toolbarHeight = 48;

  // Thumbnail
  static const double thumbnailCellWidth = 60;
  static const int maxThumbnailCount = 50;
}
