import 'dart:io';

import 'package:flutter/material.dart';

/// 文件夹选择器组件
///
/// 用于在保存对话框中选择存储子文件夹。
/// 以标签 (Tag/Chip) 形式展示最近使用的文件夹和所有扫描到的文件夹。
/// 替代 ExpansionTile 以避免动画冲突和崩溃问题。
class FolderSelector extends StatefulWidget {
  final String basePath;
  final String currentSubfolder;
  final ValueChanged<String> onFolderSelected;
  final List<String> recentFolders;

  const FolderSelector({
    super.key,
    required this.basePath,
    required this.currentSubfolder,
    required this.onFolderSelected,
    required this.recentFolders,
  });

  @override
  State<FolderSelector> createState() => _FolderSelectorState();
}

class _FolderSelectorState extends State<FolderSelector> {
  List<Directory> _allFolders = [];
  bool _loading = false;
  String? _error;
  bool _showAllFolders = false; // 是否显示所有文件夹

  @override
  void initState() {
    super.initState();
    // 初始不加载所有文件夹，除非最近列表为空或者用户点击展开
    // 但为了确保用户能看到所有选项，我们可以在后台静默加载，或者等用户点击
    // 这里选择直接加载，因为文件系统操作通常较快
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = Directory(widget.basePath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final entities = dir.listSync(recursive: false);
      final folders = entities.whereType<Directory>().toList();

      // 排序：按名称
      folders
          .sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

      if (mounted) {
        setState(() {
          _allFolders = folders;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _getRelativePath(Directory dir) {
    final path = dir.path;
    if (path.startsWith(widget.basePath)) {
      var rel = path.substring(widget.basePath.length);
      if (rel.startsWith(Platform.pathSeparator)) {
        rel = rel.substring(1);
      }
      return rel;
    }
    return dir.path.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 1. 准备最近使用的标签 (Tags)
    // 过滤掉空字符串（根目录单独处理）
    final recentTags = widget.recentFolders.where((f) => f.isNotEmpty).toList();

    // 2. 准备所有文件夹标签
    // 排除已经在最近列表中显示的，避免重复? 或者全部显示?
    // 通常"所有"应该包含所有。但为了视觉整洁，我们可以只在"所有"里显示不在"最近"里的?
    // 简单起见，全部显示，用户习惯看到完整列表。

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 头部标题栏 ──
        Row(
          children: [
            Icon(Icons.folder_open, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '存储位置 (标签)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '刷新文件夹列表',
              onPressed: _loadFolders,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── 根目录选项 (始终显示) ──
        ActionChip(
          avatar: Icon(
            widget.currentSubfolder.isEmpty
                ? Icons.home_filled
                : Icons.home_outlined,
            size: 16,
            color: widget.currentSubfolder.isEmpty
                ? colorScheme.onPrimaryContainer
                : colorScheme.primary,
          ),
          label: const Text('根目录'),
          backgroundColor: widget.currentSubfolder.isEmpty
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withOpacity(0.5),
          side: BorderSide.none,
          labelStyle: TextStyle(
            color: widget.currentSubfolder.isEmpty
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight:
                widget.currentSubfolder.isEmpty ? FontWeight.w600 : null,
          ),
          onPressed: () => widget.onFolderSelected(''),
        ),

        const SizedBox(height: 12),

        // ── 最近使用 (Recent Tags) ──
        if (recentTags.isNotEmpty) ...[
          Text(
            '最近使用',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recentTags.map((folder) {
              final isSelected = widget.currentSubfolder == folder;
              return ChoiceChip(
                label: Text(folder),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) widget.onFolderSelected(folder);
                },
                selectedColor: colorScheme.primaryContainer,
                backgroundColor:
                    colorScheme.surfaceContainerHighest.withOpacity(0.3),
                labelStyle: TextStyle(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],

        // ── 所有文件夹 (All Folders) ──
        InkWell(
          onTap: () {
            setState(() {
              _showAllFolders = !_showAllFolders;
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  '所有文件夹 (${_allFolders.length})',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showAllFolders ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),

        if (_loading && _allFolders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              '加载失败: $_error',
              style: TextStyle(color: colorScheme.error, fontSize: 11),
            ),
          ),

        // 可见性切换，不使用 ExpansionTile 动画以防 Crash
        if (_showAllFolders) ...[
          const SizedBox(height: 6),
          if (_allFolders.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '暂无子文件夹',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 200), // 限制高度，内部滚动
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allFolders.map((dir) {
                    final relPath = _getRelativePath(dir);
                    final isSelected = widget.currentSubfolder == relPath;
                    return ChoiceChip(
                      label: Text(relPath),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) widget.onFolderSelected(relPath);
                      },
                      selectedColor: colorScheme.primaryContainer,
                      backgroundColor:
                          colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
