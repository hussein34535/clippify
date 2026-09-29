import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Saves a video file to the device gallery. Returns true on success.
Future<bool> saveToGallery(String filePath) async {
  try {
    await Gal.putVideo(filePath);
    return true;
  } catch (e) {
    debugPrint('[SaveHelpers] saveToGallery failed: $e');
    return false;
  }
}

/// Opens the system share sheet for a produced clip.
Future<void> shareClip(String filePath) async {
  try {
    final exists = await File(filePath).exists();
    if (!exists) {
      debugPrint('[SaveHelpers] shareClip: file not found: $filePath');
      return;
    }
    await Share.shareXFiles([XFile(filePath)]);
  } catch (e) {
    debugPrint('[SaveHelpers] shareClip failed: $e');
  }
}

/// Opens an external checkout URL (Stripe etc.). Returns true if launched.
Future<bool> openCheckout(String url) async {
  try {
    final uri = Uri.parse(url);
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[SaveHelpers] openCheckout failed: $e');
    return false;
  }
}
