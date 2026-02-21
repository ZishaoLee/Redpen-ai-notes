import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/prompt_service.dart';
import '../services/llm_service.dart';
import '../models/prompt_template.dart';
import '../models/ai_config.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '视觉模型', icon: Icon(Icons.image_search)),
              Tab(text: '编辑模型', icon: Icon(Icons.edit_note)),
              Tab(text: '模型管理', icon: Icon(Icons.dns)),
              Tab(text: '提示词', icon: Icon(Icons.library_books)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: '清除所有数据',
              onPressed: () => _confirmClearAll(context),
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            _VisionSettingsTab(),
            _EditSettingsTab(),
            _ModelManagerTab(),
            _PromptManagerTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('危险操作'),
        content: const Text('确定要清除所有 API Key、配置和提示词吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('彻底清除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<SettingsService>().clearAll();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已重置所有设置')));
    }
  }
}

// ── Vision Settings Tab ─────────────────────────────────

class _VisionSettingsTab extends StatelessWidget {
  const _VisionSettingsTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final promptService = context.watch<PromptService>();
    final visionPrompts = promptService.visionPrompts;
    final config = settings.visionConfig;
    final savedModels = settings.savedModels;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader(context, '视觉提取流配置'),
        const SizedBox(height: 16),

        _ModelSelector(
          label: '选择视觉模型',
          value: config.id,
          models: savedModels,
          onChanged: (modelId) {
            final selected = savedModels.firstWhere((m) => m.id == modelId,
                orElse: () => config);
            settings.setVisionConfig(selected);
          },
        ),
        const SizedBox(height: 12),
        _ModelInfoCard(config: config),

        const SizedBox(height: 20),

        // Default Prompt Selector
        DropdownButtonFormField<String>(
          value: settings.activeVisionPromptId.isNotEmpty &&
                  visionPrompts
                      .any((p) => p.id == settings.activeVisionPromptId)
              ? settings.activeVisionPromptId
              : (visionPrompts.isNotEmpty ? visionPrompts.first.id : null),
          decoration: const InputDecoration(
            labelText: '默认提取提示词',
            prefixIcon: Icon(Icons.description),
            helperText: '用于 "相册/拍照" 分析时的默认指令',
            border: OutlineInputBorder(),
          ),
          items: visionPrompts.map((p) {
            return DropdownMenuItem(
              value: p.id,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) settings.setActiveVisionPromptId(val);
          },
        ),
      ],
    );
  }
}

// ── Edit Settings Tab ───────────────────────────────────

class _EditSettingsTab extends StatelessWidget {
  const _EditSettingsTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final promptService = context.watch<PromptService>();
    final editPrompts = promptService.editPrompts;
    final config = settings.editConfig;
    final savedModels = settings.savedModels;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader(context, '局部调优流配置'),
        const SizedBox(height: 16),

        _ModelSelector(
          label: '选择编辑模型',
          value: config.id,
          models: savedModels,
          onChanged: (modelId) {
            final selected = savedModels.firstWhere((m) => m.id == modelId,
                orElse: () => config);
            settings.setEditConfig(selected);
          },
        ),
        const SizedBox(height: 12),
        _ModelInfoCard(config: config),

        const SizedBox(height: 20),

        // Default Prompt Selector
        DropdownButtonFormField<String>(
          value: settings.activeEditPromptId.isNotEmpty &&
                  editPrompts.any((p) => p.id == settings.activeEditPromptId)
              ? settings.activeEditPromptId
              : (editPrompts.isNotEmpty ? editPrompts.first.id : null),
          decoration: const InputDecoration(
            labelText: '默认调优提示词',
            prefixIcon: Icon(Icons.rule),
            helperText: '用于 "AI 调优" 对话框的默认指令',
            border: OutlineInputBorder(),
          ),
          items: editPrompts.map((p) {
            return DropdownMenuItem(
              value: p.id,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) settings.setActiveEditPromptId(val);
          },
        ),
      ],
    );
  }
}

// ── Model Manager Tab ───────────────────────────────────

class _ModelManagerTab extends StatelessWidget {
  const _ModelManagerTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final models = settings.savedModels;

    return Scaffold(
      body: models.isEmpty
          ? const Center(child: Text('暂无模型配置'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 10),
              itemCount: models.length,
              onReorder: (oldIndex, newIndex) {
                settings.reorderModels(oldIndex, newIndex);
              },
              itemBuilder: (ctx, i) {
                final model = models[i];
                return Card(
                  key: ValueKey(model.id),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: model.provider == 'openai'
                          ? Colors.green.shade100
                          : Colors.blue.shade100,
                      child: Icon(
                        model.provider == 'openai'
                            ? Icons.api
                            : Icons.psychology,
                        color: model.provider == 'openai'
                            ? Colors.green
                            : Colors.blue,
                        size: 20,
                      ),
                    ),
                    title: Text(model.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${model.provider.toUpperCase()} / ${model.modelName}'),
                        if (model.latency != -1)
                          Text('延迟: ${model.latency}ms',
                              style: TextStyle(
                                  color: model.latency < 200
                                      ? Colors.green
                                      : Colors.orange,
                                  fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showEditor(context, model),
                        ),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                    onLongPress: () => _confirmDelete(context, model),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, null),
        label: const Text('添加模型'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _showEditor(BuildContext context, AIConfig? model) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(24),
          child: _ModelConfigForm(
            config:
                model ?? AIConfig.defaultConfig().copyWith(name: 'New Model'),
            onSave: (newConfig) {
              final service = context.read<SettingsService>();
              if (model != null) {
                service.updateSavedModel(newConfig);
              } else {
                service.addSavedModel(newConfig);
              }
              Navigator.pop(context);
            },
            onDelete: model != null
                ? () {
                    context.read<SettingsService>().removeSavedModel(model.id);
                    Navigator.pop(context);
                  }
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AIConfig model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除 "${model.name}" 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<SettingsService>().removeSavedModel(model.id);
    }
  }
}

// ── Model Selector Widget ───────────────────────────────

class _ModelSelector extends StatelessWidget {
  final String label;
  final String value;
  final List<AIConfig> models;
  final ValueChanged<String> onChanged;

  const _ModelSelector({
    required this.label,
    required this.value,
    required this.models,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure the current value is in the list, otherwise add a temporary item
    final knownIds = models.map((m) => m.id).toSet();
    final items = [...models];

    // If current value is not in models (e.g. legacy or custom unsaved), we handle it visually?
    // For now, if not found, Dropdown will be null unless we add a dummy.
    // But SettingsService ensures active config has an ID.
    // If that ID is not in savedModels, we can't select it in Dropdown easily unless we add it.
    // Let's assume active config ID might not be in savedModels.

    String? dropdownValue = knownIds.contains(value) ? value : null;

    return DropdownButtonFormField<String>(
      value: dropdownValue,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.link),
        border: const OutlineInputBorder(),
        helperText: dropdownValue == null ? '当前配置未保存到仓库' : null,
      ),
      items: items.map((m) {
        return DropdownMenuItem(
          value: m.id,
          child: Text(m.name, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
      hint: const Text('选择模型...'),
    );
  }
}

class _ModelInfoCard extends StatelessWidget {
  final AIConfig config;
  const _ModelInfoCard({required this.config});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('提供商', config.provider.toUpperCase()),
            _row('模型', config.modelName),
            _row(
                'API Key',
                config.apiKey.isNotEmpty
                    ? '******${config.apiKey.substring(config.apiKey.length > 4 ? config.apiKey.length - 4 : 0)}'
                    : '未配置'),
            if (config.provider == 'openai') _row('Base URL', config.baseUrl),
            if (config.backupBaseUrls.isNotEmpty)
              _row('备用地址', '${config.backupBaseUrls.length} 个'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

// ── Shared Model Config Form (Add/Edit) ─────────────────

class _ModelConfigForm extends StatefulWidget {
  final AIConfig config;
  final ValueChanged<AIConfig> onSave;
  final VoidCallback? onDelete;

  const _ModelConfigForm({
    required this.config,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_ModelConfigForm> createState() => _ModelConfigFormState();
}

class _ModelConfigFormState extends State<_ModelConfigForm> {
  late TextEditingController _nameCtrl;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _baseUrlCtrl;
  final List<TextEditingController> _backupUrlCtrls = [];
  bool _obscureKey = true;
  String _provider = 'openai';
  bool _isTesting = false;
  int? _lastLatency;
  String? _testError;

  @override
  void initState() {
    super.initState();
    _provider = widget.config.provider;
    _nameCtrl = TextEditingController(text: widget.config.name);
    _apiKeyCtrl = TextEditingController(text: widget.config.apiKey);
    _modelCtrl = TextEditingController(text: widget.config.modelName);
    _baseUrlCtrl = TextEditingController(text: widget.config.baseUrl);

    for (var url in widget.config.backupBaseUrls) {
      _backupUrlCtrls.add(TextEditingController(text: url));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    for (var c in _backupUrlCtrls) c.dispose();
    super.dispose();
  }

  AIConfig _buildConfig() {
    return widget.config.copyWith(
      name: _nameCtrl.text.trim(),
      provider: _provider,
      apiKey: _apiKeyCtrl.text.trim(),
      modelName: _modelCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      backupBaseUrls: _backupUrlCtrls
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      latency: _lastLatency ?? widget.config.latency,
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testError = null;
      _lastLatency = null;
    });

    try {
      final config = _buildConfig();
      final llmService = LlmService();
      final latency = await llmService.testConnection(config);

      if (mounted) {
        setState(() {
          _lastLatency = latency;
          _isTesting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('连接成功! 延迟: ${latency}ms'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testError = e.toString();
          _isTesting = false;
        });
      }
    }
  }

  void _save() {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入模型名称')));
      return;
    }
    widget.onSave(_buildConfig());
  }

  void _addBackupUrl() {
    setState(() {
      _backupUrlCtrls.add(TextEditingController());
    });
  }

  void _removeBackupUrl(int index) {
    setState(() {
      final ctrl = _backupUrlCtrls.removeAt(index);
      ctrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOpenAI = _provider == 'openai';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.onDelete != null ? '编辑模型' : '添加模型',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name & Provider
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: '配置名称', hintText: '例如: 我的 GPT-4o'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: _provider,
                      items: const [
                        DropdownMenuItem(
                            value: 'openai', child: Text('OpenAI')),
                        DropdownMenuItem(
                            value: 'gemini', child: Text('Gemini')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _provider = val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // API Key
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Model Name
                TextField(
                  controller: _modelCtrl,
                  decoration: InputDecoration(
                    labelText: '模型名称 (Model ID)',
                    hintText: isOpenAI ? 'gpt-4o' : 'gemini-2.0-flash',
                  ),
                ),

                // Base URL (OpenAI only)
                if (isOpenAI) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Backup URLs
                  ExpansionTile(
                    title:
                        const Text('备用地址 (可选)', style: TextStyle(fontSize: 14)),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      ...List.generate(_backupUrlCtrls.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _backupUrlCtrls[index],
                                  decoration: InputDecoration(
                                      labelText: '备用地址 ${index + 1}'),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 20, color: Colors.grey),
                                onPressed: () => _removeBackupUrl(index),
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: _addBackupUrl,
                        icon: const Icon(Icons.add_link, size: 18),
                        label: const Text('添加备用地址'),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Test Result
                if (_isTesting)
                  const Row(children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('正在测试连接...')
                  ]),
                if (_testError != null)
                  Text('测试失败: $_testError',
                      style: const TextStyle(color: Colors.red)),
                if (_lastLatency != null)
                  Text('测试通过! 延迟: ${_lastLatency}ms',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (widget.onDelete != null)
              TextButton(
                  onPressed: widget.onDelete,
                  child:
                      const Text('删除此模型', style: TextStyle(color: Colors.red))),
            if (widget.onDelete == null) const SizedBox(),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            )
          ],
        )
      ],
    );
  }
}

// ── Prompt Manager Tab (Unchanged, just moved) ─────────────────────────

class _PromptManagerTab extends StatelessWidget {
  const _PromptManagerTab();

  @override
  Widget build(BuildContext context) {
    final promptService = context.watch<PromptService>();
    final prompts = promptService.prompts;

    return Scaffold(
      body: prompts.isEmpty
          ? const Center(child: Text('暂无自定义提示词'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: prompts.length,
              itemBuilder: (ctx, i) {
                final p = prompts[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: p.type == PromptType.vision
                        ? Colors.orange.shade100
                        : Colors.blue.shade100,
                    child: Icon(
                      p.type == PromptType.vision ? Icons.image : Icons.edit,
                      color: p.type == PromptType.vision
                          ? Colors.orange
                          : Colors.blue,
                      size: 20,
                    ),
                  ),
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    p.content.replaceAll('\n', ' ').substring(
                        0, p.content.length > 50 ? 50 : p.content.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showEditor(context, p),
                  ),
                  onLongPress: () => _confirmDelete(context, p),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, null),
        label: const Text('新建提示词'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _showEditor(BuildContext context, PromptTemplate? template) {
    showDialog(
      context: context,
      builder: (_) => _PromptEditorDialog(template: template),
    );
  }

  Future<void> _confirmDelete(BuildContext context, PromptTemplate p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提示词'),
        content: Text('确定要删除 "${p.name}" 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<PromptService>().deletePrompt(p.id);
    }
  }
}

class _PromptEditorDialog extends StatefulWidget {
  final PromptTemplate? template;
  const _PromptEditorDialog({this.template});

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _contentCtrl;
  PromptType _type = PromptType.vision;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template?.name ?? '');
    _contentCtrl = TextEditingController(text: widget.template?.content ?? '');
    _type = widget.template?.type ?? PromptType.vision;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.template != null;
    return Dialog(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? '编辑提示词' : '新建提示词',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: '模式名称'),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<PromptType>(
                  value: _type,
                  items: const [
                    DropdownMenuItem(
                        value: PromptType.vision, child: Text('视觉提取')),
                    DropdownMenuItem(
                        value: PromptType.edit, child: Text('局部调优')),
                  ],
                  onChanged:
                      isEditing ? null : (val) => setState(() => _type = val!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: '系统指令 (System Prompt)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final content = _contentCtrl.text;
    if (name.isEmpty || content.isEmpty) return;

    final service = context.read<PromptService>();
    if (widget.template != null) {
      await service.updatePrompt(widget.template!.id,
          name: name, content: content);
    } else {
      await service.addPrompt(name, _type, content);
    }
    if (mounted) Navigator.pop(context);
  }
}

Widget _buildSectionHeader(BuildContext context, String title) {
  return Row(
    children: [
      Container(width: 4, height: 16, color: Theme.of(context).primaryColor),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    ],
  );
}
