import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../pages/settings_page.dart';
import '../services/llm_service.dart';
import '../services/settings_service.dart';
import '../services/prompt_service.dart';
import '../widgets/ai_sidebar_panel.dart';
import '../widgets/math_drawer.dart';

// ── 应用状态枚举 ─────────────────────────────────────────
enum AppState { idle, staging, analyzing, error }

/// 首页 — 选图暂存 → AI 批量分析 → 本地 MD 编辑 & 管理。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── 状态核心变量 ──
  AppState _appState = AppState.idle;
  String? _currentFilePath; // null = 未保存草稿, 非 null = 已保存文件
  bool _isEditing = false; // 是否在编辑器/文本阅读界面
  String? _errorMessage;
  String _streamingContent = ''; // 流式输出内容缓冲

  // ── AI 侧边栏状态 ──
  bool _showAISidebar = false;
  String _selectedTextForAI = '';
  TextSelection _lastSelection = TextSelection.collapsed(offset: 0);

  /// 多图暂存队列。
  List<XFile> _stagedImages = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  /// 当前工作区路径（快捷方式）。
  String get _workspacePath => context.read<SettingsService>().workspacePath;

  // ── 选图（暂存，不直接调用大模型） ────────────────────

  /// 从相册多选图片，加入暂存区。
  Future<void> _pickMultiFromGallery() async {
    final List<XFile> picked = await _picker.pickMultiImage(
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked.isEmpty) return;

    setState(() {
      _stagedImages.addAll(picked);
      _appState = AppState.staging;
      _isEditing = false; // 切到暂存面板
    });
  }

  /// 拍照单张，加入暂存区。
  Future<void> _pickFromCamera() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _stagedImages.add(picked);
      _appState = AppState.staging;
      _isEditing = false;
    });
  }

  /// 从暂存区移除指定索引的图片。
  void _removeStagedImage(int index) {
    setState(() {
      _stagedImages.removeAt(index);
      if (_stagedImages.isEmpty) {
        _appState = AppState.idle;
        _promptController.clear();
      }
    });
  }

  // ── 批量分析 ──────────────────────────────────────────

  Future<void> _startAnalysis() async {
    if (_stagedImages.isEmpty) return;

    final supplementaryPrompt = _promptController.text.trim();

    setState(() {
      _appState = AppState.analyzing;
      _errorMessage = null;
      _contentController.clear();
      _streamingContent = ''; // 重置流式缓冲
      _currentFilePath = null;
    });

    final settings = context.read<SettingsService>();
    final llm = context.read<LlmService>();
    final promptService = context.read<PromptService>();

    try {
      final activePrompt =
          promptService.getPrompt(settings.activeVisionPromptId);
      final systemPrompt = activePrompt?.content ?? '';

      final stream = llm.analyzeImagesStream(
        images: _stagedImages,
        settings: settings,
        promptContent: systemPrompt,
        supplementaryPrompt:
            supplementaryPrompt.isEmpty ? null : supplementaryPrompt,
      );

      stream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() {
            _streamingContent += chunk;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _contentController.text = _streamingContent;
            _stagedImages = []; // 清空暂存
            _appState = AppState.idle;
            _isEditing = true; // 进入文本编辑阅读
            _currentFilePath = null; // 全新未保存草稿
          });
          _promptController.clear();
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _appState = AppState.error;
            _errorMessage = error.toString();
          });
          _showErrorSnackBar('分析出错: $error');
        },
      );
    } catch (e) {
      setState(() {
        _appState = AppState.error;
        _errorMessage = e.toString();
      });
      _showErrorSnackBar(e.toString());
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFD32F2F),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '关闭',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  // ── 极简保存逻辑 ──────────────────────────────────────

  Future<void> _saveFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final content = _contentController.text;
    if (content.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('内容为空，无法保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_currentFilePath != null) {
      // ── 已有文件：静默覆写，不弹窗 ──
      try {
        final file = File(_currentFilePath!);
        await file.writeAsString(content);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已覆盖保存'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    } else {
      // ── 新文件：仅弹窗输入文件名，路径自动拼接到当前工作区 ──
      final nameController = TextEditingController(
        text: '笔记_${DateTime.now().millisecondsSinceEpoch}',
      );
      final fileName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存 Markdown'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '保存到: $_workspacePath/',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: '输入文件名（无需加 .md）',
                  helperText: '可加路径前缀新建文件夹，如: 微积分/极限测试',
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
              onPressed: () => Navigator.pop(ctx, nameController.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );

      if (fileName == null || fileName.trim().isEmpty) return;

      try {
        final fullPath = '$_workspacePath/${fileName.trim()}.md';
        final file = File(fullPath);

        // 确保父目录存在
        final parentDir = file.parent;
        if (!parentDir.existsSync()) {
          parentDir.createSync(recursive: true);
        }

        await file.writeAsString(content);
        if (mounted) {
          setState(() {
            _currentFilePath = file.path;
          });
        }
        messenger.showSnackBar(
          SnackBar(
            content:
                Text('保存成功: ${file.path.split(Platform.pathSeparator).last}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  // ── 从侧边栏打开文件 ──────────────────────────────────

  void _openFileFromDrawer(String content, String filePath) {
    setState(() {
      _contentController.text = content;
      _currentFilePath = filePath;
      _isEditing = true;
      _appState = AppState.idle;
      _errorMessage = null;
    });
  }

  // ── 返回主屏幕 ────────────────────────────────────────

  void _backToHome() {
    setState(() {
      _isEditing = false;
      _appState = _stagedImages.isNotEmpty ? AppState.staging : AppState.idle;
      _errorMessage = null;
    });
  }

  // ── 显示最新笔记 ──────────────────────────────────────

  void _openLatestNote() {
    try {
      final dir = Directory(_workspacePath);
      if (!dir.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('暂无保存的笔记'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('暂无保存的笔记'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      files
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latest = files.first;
      final content = latest.readAsStringSync();

      setState(() {
        _contentController.text = content;
        _currentFilePath = latest.path;
        _isEditing = true;
        _appState = AppState.idle;
        _errorMessage = null;
      });
    } catch (e) {
      _showErrorSnackBar('读取笔记失败: $e');
    }
  }

  // ── AI 侧边栏 ─────────────────────────────────────────

  void _openAISidebar() {
    final selection = _contentController.selection;
    final selectedText = selection.textInside(_contentController.text);

    if (selectedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先选中需要调优的文本'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _showAISidebar = true;
      _selectedTextForAI = selectedText;
      _lastSelection = selection;
    });
  }

  void _closeAISidebar() {
    setState(() {
      _showAISidebar = false;
    });
  }

  void _applyAIChange(String? newText) {
    if (newText == null) {
      _closeAISidebar();
      return;
    }

    final text = _contentController.text;
    final newContent = text.replaceRange(
      _lastSelection.start,
      _lastSelection.end,
      newText,
    );

    setState(() {
      _contentController.text = newContent;
      final newCursorPos = _lastSelection.start + newText.length;
      _contentController.selection = TextSelection.collapsed(
        offset: newCursorPos,
      );
      _showAISidebar = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已应用 AI 修改'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ── UI ─────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      drawer: MathDrawer(
        onFileSelected: _openFileFromDrawer,
        onDraftTap: () {
          setState(() {
            _contentController.clear();
            _currentFilePath = null;
            _isEditing = true;
            _appState = AppState.idle;
          });
        },
      ),
      appBar: _buildAppBar(colorScheme),
      body: _buildBody(colorScheme),
      bottomNavigationBar: _buildBottomBar(colorScheme),
      // 编辑状态下显示浮动 AI 调优按钮
      floatingActionButton: _isEditing && !_showAISidebar
          ? FloatingActionButton.extended(
              onPressed: _openAISidebar,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('AI 调优'),
              tooltip: '选中文本后点击进行 AI 调优',
            )
          : null,
    );
  }

  // ── AppBar ─────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    final bool showDrawerMenu = _isEditing ||
        _appState == AppState.staging ||
        _appState == AppState.analyzing;

    return AppBar(
      leading: showDrawerMenu
          ? IconButton(
              icon: const Icon(Icons.menu),
              tooltip: '文件树',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          : null,
      title: _isEditing
          ? _buildEditorTitle(colorScheme)
          : _appState == AppState.staging
              ? Text('暂存区 (${_stagedImages.length} 张)')
              : _appState == AppState.analyzing
                  ? const Text('AI 分析中…')
                  : const Text('RedPen'),
      centerTitle: _appState == AppState.idle && !_isEditing,
      actions: [
        if (_isEditing || _appState == AppState.staging)
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: '返回主屏',
            onPressed: _backToHome,
          ),
        // 编辑状态下显示保存按钮
        if (_isEditing)
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '保存',
            onPressed: _saveFile,
          ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '设置',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
        ),
      ],
    );
  }

  // ── Body 路由 ──────────────────────────────────────────

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isEditing) {
      return _buildEditorBody(colorScheme);
    }

    switch (_appState) {
      case AppState.staging:
        return _buildStagingBody(colorScheme);
      case AppState.analyzing:
        return _buildAnalyzingBody(colorScheme);
      case AppState.error:
        return _buildErrorBody(colorScheme);
      case AppState.idle:
        return _buildHomeBody(colorScheme);
    }
  }

  // ── BottomBar 路由 ─────────────────────────────────────

  Widget? _buildBottomBar(ColorScheme colorScheme) {
    // 编辑状态下底部绝对干净，给软键盘留出空间
    if (_isEditing) return null;
    if (_appState == AppState.staging) {
      return _buildStagingBottomBar(colorScheme);
    }
    return null;
  }

  // ── AppBar 编辑器标题 ──────────────────────────────────

  Widget _buildEditorTitle(ColorScheme colorScheme) {
    if (_currentFilePath != null && _currentFilePath!.isNotEmpty) {
      final fileName = _currentFilePath!.split(Platform.pathSeparator).last;
      final displayName = fileName.endsWith('.md')
          ? fileName.substring(0, fileName.length - 3)
          : fileName;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.orange.shade600,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '未保存',
            style: TextStyle(
              fontSize: 15,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
  }

  // ── 主屏幕（idle 状态） ───────────────────────────────

  Widget _buildHomeBody(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 品牌图标
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories,
                size: 44,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '拍照提取错题，智能生成 Markdown 笔记',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),

            // ── 核心操作区：方形卡片按钮 ──
            Row(
              children: [
                // 相册方块
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Card(
                      elevation: 0,
                      color: colorScheme.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _pickMultiFromGallery,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_library_rounded,
                              size: 48,
                              color: colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '相册',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 拍照方块
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Card(
                      elevation: 0,
                      color: colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _pickFromCamera,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              size: 48,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '拍照',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // ── 次要操作：轻量文字按钮 ──
            TextButton(
              onPressed: _openLatestNote,
              child: const Text(
                '查看最新笔记 / 草稿',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ── 暂存面板 (staging) ─────────────────────────────────
  // ═══════════════════════════════════════════════════════

  Widget _buildStagingBody(ColorScheme colorScheme) {
    return Column(
      children: [
        // 提示条
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colorScheme.primaryContainer.withOpacity(0.3),
          child: Text(
            '已添加 ${_stagedImages.length} 张图片，可继续添加或点击底部按钮开始分析',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
        // 图片网格预览
        Expanded(
          child: _stagedImages.isEmpty
              ? Center(
                  child: Text(
                    '暂存区为空',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _stagedImages.length,
                  itemBuilder: (ctx, index) {
                    return _buildStagedImageTile(index, colorScheme);
                  },
                ),
        ),
        // ── 补充说明输入框 ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border:
                Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
          ),
          child: TextField(
            controller: _promptController,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '添加补充说明 (如：仅提取第二题，忽略解析...)',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStagedImageTile(int index, ColorScheme colorScheme) {
    final xfile = _stagedImages[index];
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(xfile.path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeStagedImage(index),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
        // 序号
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  /// 暂存面板底部操作栏。
  Widget _buildStagingBottomBar(ColorScheme colorScheme) {
    final settings = context.watch<SettingsService>();
    final promptService = context.watch<PromptService>();
    // final activePrompt = promptService.getPrompt(settings.activeVisionPromptId);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 左侧操作组
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.photo_library, size: 20),
                    label: const Text('相册', maxLines: 1),
                    onPressed: _pickMultiFromGallery,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(64, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.camera_alt, size: 20),
                    label: const Text('拍照', maxLines: 1),
                    onPressed: _pickFromCamera,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(64, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧核心操作组：模式选择 + 分析按钮
            Flexible(
              flex: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 模式切换器
                  if (_stagedImages.isNotEmpty)
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: settings.activeVisionPromptId.isNotEmpty &&
                                    promptService.visionPrompts.any((p) =>
                                        p.id == settings.activeVisionPromptId)
                                ? settings.activeVisionPromptId
                                : (promptService.visionPrompts.isNotEmpty
                                    ? promptService.visionPrompts.first.id
                                    : null),
                            isExpanded: false, // 自适应宽度
                            icon: Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.primary,
                            ),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                settings.setActiveVisionPromptId(newValue);
                              }
                            },
                            items: promptService.visionPrompts.map((p) {
                              return DropdownMenuItem<String>(
                                value: p.id,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 80),
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text('分析', maxLines: 1), // 简化文字
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      elevation: 2,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: _stagedImages.isEmpty ? null : _startAnalysis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ── 分析中 (analyzing) ─────────────────────────────────
  // ═══════════════════════════════════════════════════════

  Widget _buildAnalyzingBody(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Card(
          elevation: 4,
          shadowColor: colorScheme.shadow.withOpacity(0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            height: 400, // 固定高度以展示滚动内容
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部图标 + 标题行
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 24,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI 引擎工作中',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '正在流式生成 Markdown...',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 进度条 (保留作为活跃指示器)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: colorScheme.primaryContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 流式内容预览区
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: _streamingContent.isEmpty
                        ? Center(
                            child: Text(
                              '正在连接模型...\n这可能需要几秒钟',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant
                                    .withOpacity(0.7),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            reverse: true, // 自动滚动到底部
                            child: Text(
                              _streamingContent,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                fontFamily: 'monospace',
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ── 错误状态 (error) ───────────────────────────────────
  // ═══════════════════════════════════════════════════════

  Widget _buildErrorBody(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              '分析失败',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '未知错误',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      // 回到暂存面板重试
                      _appState = _stagedImages.isNotEmpty
                          ? AppState.staging
                          : AppState.idle;
                    });
                  },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回'),
                ),
                const SizedBox(width: 12),
                if (_stagedImages.isNotEmpty)
                  FilledButton.icon(
                    onPressed: _startAnalysis,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ── 编辑器界面 ─────────────────────────────────────────
  // ═══════════════════════════════════════════════════════
  Widget _buildEditorBody(ColorScheme colorScheme) {
    return Row(
      children: [
        // 左侧编辑器
        Expanded(
          child: TextField(
            controller: _contentController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              fontFamily: 'monospace',
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              hintText: '在此编辑 Markdown 内容...',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ),
        ),
        // 右侧 AI 侧边栏
        if (_showAISidebar)
          AISidebarPanel(
            selectedText: _selectedTextForAI,
            onApplyChange: _applyAIChange,
            onClose: _closeAISidebar,
          ),
      ],
    );
  }
}
