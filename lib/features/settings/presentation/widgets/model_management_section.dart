import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/utils/download_utils.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';

/// Local AI model download & management for the Settings screen.
///
/// Owns its own download state and reuses [ModelDownloadRepository] (the exact
/// same flow used during onboarding's "AI mode" step). Renders three states:
///   * ready          — model is on disk, shows size + "Ready" and a Remove action
///   * not-downloaded — a Download button
///   * downloading    — a live progress bar + percentage
class ModelManagementSection extends StatefulWidget {
  const ModelManagementSection({super.key});

  @override
  State<ModelManagementSection> createState() => _ModelManagementSectionState();
}

class _ModelManagementSectionState extends State<ModelManagementSection> {
  bool _isDownloading = false;
  bool _isDownloaded = false;
  bool _isChecking = true;
  double _downloadProgress = 0.0;
  String? _sizeStr;

  final ModelDownloadRepository _downloadRepository =
      ModelDownloadRepositoryImpl();

  @override
  void initState() {
    super.initState();
    _checkInitialDownloadState();
  }

  Future<void> _checkInitialDownloadState() async {
    final downloaded = await _downloadRepository.isModelDownloaded();
    final size = downloaded ? await _getModelSize() : null;
    if (!mounted) return;
    setState(() {
      _isDownloaded = downloaded;
      _sizeStr = size;
      _isChecking = false;
    });
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      await _downloadRepository.downloadModel(
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = computeDownloadProgress(received, total);
          });
        },
      );

      final size = await _getModelSize();
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isDownloaded = true;
        _sizeStr = size;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      debugPrint('Model download failed: $e');
      _showSnack('Download failed. Please try again.');
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await _confirmDelete();
    if (confirmed != true) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Model delete failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _isDownloaded = false;
      _sizeStr = null;
      _downloadProgress = 0.0;
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
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf');
      if (await file.exists()) {
        final bytes = await file.length();
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
            'Qwen2.5 1.5B — runs offline, no API cost.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStateBody(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildStateBody(AppColors colors) {
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

    if (_isDownloading) {
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
                '${(_downloadProgress * 100).toInt()}%',
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
              value: _downloadProgress,
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
              '${_sizeStr ?? '0.9 GB'} · Ready',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _deleteModel,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(
              'Remove',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
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
          'Download model (~0.9 GB)',
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
