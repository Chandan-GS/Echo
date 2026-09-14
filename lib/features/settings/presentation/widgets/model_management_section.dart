import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';

/// Local AI model download & management for the Settings screen.
///
/// The download itself is tracked by the shared [ModelDownloadService], not
/// local State — a plain Future keeps running when this widget is disposed
/// (e.g. the user switches Settings tabs mid-download), but local State
/// doesn't survive that, so the progress bar used to reset on return even
/// though the download was still going. Renders three states:
///   * ready          — model is on disk, shows size + "Ready" and a Remove action
///   * not-downloaded — a Download button
///   * downloading    — a live progress bar + percentage, from the shared service
class ModelManagementSection extends StatefulWidget {
  const ModelManagementSection({super.key});

  @override
  State<ModelManagementSection> createState() => _ModelManagementSectionState();
}

class _ModelManagementSectionState extends State<ModelManagementSection> {
  bool _isDownloaded = false;
  bool _isChecking = true;
  String? _sizeStr;

  final ModelDownloadRepository _downloadRepository =
      createOfflineModelRepository();

  @override
  void initState() {
    super.initState();
    ModelDownloadService.instance.state.addListener(_onDownloadStateChanged);
    _checkInitialDownloadState();
  }

  @override
  void dispose() {
    ModelDownloadService.instance.state.removeListener(_onDownloadStateChanged);
    super.dispose();
  }

  void _onDownloadStateChanged() {
    final phase = ModelDownloadService.instance.state.value.phase;
    if (phase == ModelDownloadPhase.done) {
      _refreshDownloadedState();
    } else if (phase == ModelDownloadPhase.error) {
      _showSnack('Download failed. Please try again.');
      ModelDownloadService.instance.acknowledge();
    }
  }

  Future<void> _refreshDownloadedState() async {
    final downloaded = await _downloadRepository.isModelDownloaded();
    final size = downloaded ? await _getModelSize() : null;
    if (!mounted) return;
    setState(() {
      _isDownloaded = downloaded;
      _sizeStr = size;
    });
  }

  Future<void> _checkInitialDownloadState() async {
    // A download already running (started from another screen before this one
    // mounted) takes priority over a disk check — the ValueListenableBuilder
    // below will immediately show its live progress.
    if (ModelDownloadService.instance.isDownloading) {
      if (!mounted) return;
      setState(() => _isChecking = false);
      return;
    }
    await _refreshDownloadedState();
    if (!mounted) return;
    setState(() => _isChecking = false);
  }

  void _startDownload() {
    ModelDownloadService.instance.startIfNeeded();
  }

  Future<void> _deleteModel() async {
    final confirmed = await _confirmDelete();
    if (confirmed != true) return;
    try {
      final path = await _downloadRepository.downloadedPathOrNull();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('Model delete failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _isDownloaded = false;
      _sizeStr = null;
    });
  }

  Future<bool?> _confirmDelete() {
    final colors = context.colors;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Remove local model?',
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'This frees up disk space. You can re-download it anytime, but '
          'offline briefings won\'t work until you do.',
          style: GoogleFonts.nunito(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Remove',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _getModelSize() async {
    try {
      final path = await _downloadRepository.downloadedPathOrNull();
      if (path != null) {
        final bytes = await File(path).length();
        final gb = bytes / (1024 * 1024 * 1024);
        return '${gb.toStringAsFixed(1)} GB';
      }
    } catch (_) {
      // Ignore
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 20, color: colors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Local model',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${offlineModelDisplayName()} — runs offline, no API cost.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<ModelDownloadState>(
            valueListenable: ModelDownloadService.instance.state,
            builder: (context, dlState, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildStateBody(colors, dlState),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateBody(AppColors colors, ModelDownloadState dlState) {
    if (_isChecking) {
      return SizedBox(
        key: const ValueKey('checking'),
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(colors.primaryGreen),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking…',
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (dlState.phase == ModelDownloadPhase.downloading) {
      return Column(
        key: const ValueKey('downloading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Downloading model…',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                '${(dlState.progress * 100).toInt()}%',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: dlState.progress,
              minHeight: 10,
              backgroundColor: colors.dividerColor,
              valueColor:
                  AlwaysStoppedAnimation<Color>(colors.primaryGreen),
            ),
          ),
        ],
      );
    }

    if (_isDownloaded) {
      return Row(
        key: const ValueKey('ready'),
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: colors.primaryGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_sizeStr ?? offlineModelSizeLabel()} · Ready',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          Material(
            color: Colors.redAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _deleteModel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Remove',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Not downloaded.
    return SizedBox(
      key: const ValueKey('download'),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _startDownload,
        icon: const Icon(Icons.download_rounded, size: 20),
        label: Text(
          'Download model (${offlineModelSizeLabel()})',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primaryGreen,
          foregroundColor: colors.textInverse,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
