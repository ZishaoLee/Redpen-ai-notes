import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

/// 本地 Markdown 文件树侧边栏。
///
/// 基准目录：`/storage/emulated/0/Documents/$currentWorkspace`。
/// 递归遍历文件夹，渲染为可折叠的树形列表。
/// 点击 `.md` 文件时回调 [onFileSelected]。
class MathDrawer extends StatefulWidget {
  /// 选中文件时的回调：(文件内容, 文件绝对路径)。
  final void Function(String content, String filePath) onFileSelected;

  /// 点击"未保存/暂存区"节点时的回调。
  final VoidCallback? onDraftTap;

  const MathDrawer({
    super.key,
    required this.onFileSelected,
    this.onDraftTap,
  });

  @override
  State<MathDrawer> createState() => _MathDrawerState();
}

class _MathDrawerState extends State<MathDrawer> {
  bool _loading = true;
  List<FileSystemEntity>? _entities;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 当前工作区的完整路径（动态读取 SettingsService）。
  String get _basePath => context.read<SettingsService>().workspacePath;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = Directory(_basePath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final entities = dir.listSync(recursive: false)
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      if (mounted) {
        setState(() {
          _entities = entities;
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

  // ── 切换/新建工作区 ───────────────────────────────────

  Future<void> _showWorkspaceDialog() async {
    final settings = context.read<SettingsService>();
    final controller = TextEditingController();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换 / 新建工作区'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前: ${settings.currentWorkspace}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入工作区文件夹名称',
                helperText: '例如: Math2、线代、概率论',
                helperMaxLines: 2,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty) return;

    await settings.setCurrentWorkspace(newName.trim());

    // 确保物理目录存在
    final dir = Directory(settings.workspacePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // 刷新文件树
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsService>();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // ── 顶部标题栏 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_special,
                          color: colorScheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          settings.currentWorkspace,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: '刷新文件树',
                        onPressed: _refresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.workspacePath,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showWorkspaceDialog,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('切换 / 新建工作区'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 未保存/暂存区节点 ──
            ListTile(
              leading: Icon(Icons.edit_note, color: Colors.orange.shade700),
              title: Text(
                '未保存 / 暂存区',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
              dense: true,
              onTap: () {
                Navigator.pop(context);
                widget.onDraftTap?.call();
              },
            ),
            const Divider(height: 1),

            // ── 文件树主体 ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('加载失败: $_error',
                                textAlign: TextAlign.center),
                          ),
                        )
                      : _entities == null || _entities!.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.folder_open,
                                      size: 48,
                                      color: colorScheme.onSurfaceVariant
                                          .withOpacity(0.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                    '暂无文件\n保存后的笔记会出现在这里',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _entities!.length,
                              itemBuilder: (ctx, i) =>
                                  _buildEntity(_entities![i], 0),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntity(FileSystemEntity entity, int depth) {
    if (entity is Directory) {
      return _buildDirectoryTile(entity, depth);
    } else if (entity is File && entity.path.endsWith('.md')) {
      return _buildFileTile(entity, depth);
    }
    return const SizedBox.shrink();
  }

  Widget _buildDirectoryTile(Directory dir, int depth) {
    final name = dir.path.split('/').last;
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(recursive: false)
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
    } catch (_) {
      children = [];
    }

    // 过滤：仅保留文件夹和 .md 文件
    children = children
        .where((e) => e is Directory || (e is File && e.path.endsWith('.md')))
        .toList();

    if (children.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.folder_outlined, size: 20),
        title: Text(name, style: const TextStyle(fontSize: 14)),
        dense: true,
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 16),
        onLongPress: () => _showDirOptions(dir),
      );
    }

    return GestureDetector(
      onLongPress: () => _showDirOptions(dir),
      child: ExpansionTile(
        leading: const Icon(Icons.folder, size: 20),
        title: Text(name, style: const TextStyle(fontSize: 14)),
        tilePadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 12),
        dense: true,
        children: children.map((e) => _buildEntity(e, depth + 1)).toList(),
      ),
    );
  }

  Widget _buildFileTile(File file, int depth) {
    final name = file.path.split('/').last;
    final displayName =
        name.endsWith('.md') ? name.substring(0, name.length - 3) : name;

    return ListTile(
      leading: const Icon(Icons.description_outlined, size: 20),
      title: Text(
        displayName,
        style: const TextStyle(fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      dense: true,
      contentPadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 12),
      onTap: () => _openFile(file),
      onLongPress: () => _showFileOptions(file),
    );
  }

  // ── 文件长按操作菜单 ──────────────────────────────────

  void _showFileOptions(File file) {
    final name = file.path.split('/').last;
    final displayName =
        name.endsWith('.md') ? name.substring(0, name.length - 3) : name;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _renameFile(file, displayName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('移动到…'),
              onTap: () {
                Navigator.pop(ctx);
                _moveFile(file, displayName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteFile(file, displayName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _moveFile(File file, String displayName) async {
    // 收集工作区内所有子目录（含根目录本身）
    final dirs = <Directory>[];
    final root = Directory(_basePath);
    dirs.add(root); // 根目录作为第一项
    _collectDirs(root, dirs);

    // 排除文件当前所在目录（移动到相同位置无意义）
    final currentParent = file.parent.path;
    final candidates = dirs.where((d) => d.path != currentParent).toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可移动的目标文件夹'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 将路径转成相对显示名（根目录显示为「/ 根目录」）
    String _relLabel(Directory d) {
      if (d.path == root.path) return '／ 根目录';
      return d.path.replaceFirst(_basePath, '').replaceAll('\\', '/');
    }

    final target = await showDialog<Directory>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移动「$displayName」到…'),
        contentPadding: const EdgeInsets.only(top: 12),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final d = candidates[i];
              return ListTile(
                leading: Icon(
                  d.path == root.path
                      ? Icons.folder_special
                      : Icons.folder_outlined,
                  size: 20,
                ),
                title: Text(
                  _relLabel(d),
                  style: const TextStyle(fontSize: 14),
                ),
                dense: true,
                onTap: () => Navigator.pop(ctx, d),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (target == null) return;

    try {
      final fileName = file.path.split('/').last;
      final newPath = '${target.path}/$fileName';
      if (File(newPath).existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('目标文件夹中已存在同名文件「$displayName」'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFFD32F2F),
            ),
          );
        }
        return;
      }
      await file.rename(newPath);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已移动至 ${_relLabel(target)}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('移动失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  /// 递归收集 [parent] 下所有子目录，结果追加到 [result]。
  void _collectDirs(Directory parent, List<Directory> result) {
    try {
      for (final entity in parent.listSync(recursive: false)) {
        if (entity is Directory) {
          result.add(entity);
          _collectDirs(entity, result);
        }
      }
    } catch (_) {}
  }

  Future<void> _renameFile(File file, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新文件名（无需加 .md）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == currentName) return;
    try {
      final dir = file.parent.path;
      await file.rename('$dir/$newName.md');
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重命名失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteFile(File file, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('将永久删除「$displayName」，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await file.delete();
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  // ── 文件夹长按操作菜单 ────────────────────────────────

  void _showDirOptions(Directory dir) {
    final name = dir.path.split('/').last;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _renameDir(dir, name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除文件夹', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteDir(dir, name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDir(Directory dir, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == currentName) return;
    try {
      final parent = dir.parent.path;
      await dir.rename('$parent/$newName');
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重命名失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteDir(Directory dir, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除文件夹'),
        content: Text('将永久删除「$name」及其所有内容，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await dir.delete(recursive: true);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  Future<void> _openFile(File file) async {
    try {
      final content = await file.readAsString();
      if (mounted) {
        Navigator.pop(context); // 关闭侧边栏
        widget.onFileSelected(content, file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('读取文件失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }
}
