import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/llm_service.dart';
import '../services/settings_service.dart';
import '../services/prompt_service.dart';

/// 右侧边栏 AI 对话面板
class AISidebarPanel extends StatefulWidget {
  final String selectedText;
  final void Function(String? newText) onApplyChange;
  final VoidCallback onClose;

  const AISidebarPanel({
    super.key,
    required this.selectedText,
    required this.onApplyChange,
    required this.onClose,
  });

  @override
  State<AISidebarPanel> createState() => _AISidebarPanelState();
}

class _AISidebarPanelState extends State<AISidebarPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, String>> _chatHistory = [];
  String _currentDraft = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentDraft = widget.selectedText;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final instruction = _inputController.text.trim();
    if (instruction.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
      _chatHistory.add({'role': 'user', 'content': instruction});
      // 添加一个空的 assistant 消息占位，用于流式更新
      _chatHistory.add({'role': 'assistant', 'content': ''});
    });
    _inputController.clear();
    _scrollToBottom();

    final llm = context.read<LlmService>();
    final settings = context.read<SettingsService>();
    final promptService = context.read<PromptService>();

    // 获取当前选中的编辑提示词
    final activePromptId = settings.activeEditPromptId;
    final activePrompt = promptService.getPrompt(activePromptId);
    final systemPromptContent = activePrompt?.content ?? _buildSystemPrompt();

    try {
      final stream = llm.chatFixTextStream(
        originalText: widget.selectedText,
        history: _chatHistory.sublist(
            0, _chatHistory.length - 2), // 排除刚添加的 user 和 assistant 占位
        newInstruction: instruction,
        promptContent: systemPromptContent,
        settings: settings,
      );

      String accumulatedContent = '';

      stream.listen(
        (chunk) {
          accumulatedContent += chunk;
          if (!mounted) return;
          setState(() {
            // 更新最后一条消息（即 assistant 的回复）
            _chatHistory.last['content'] = accumulatedContent;
          });
          _scrollToBottom();
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _currentDraft = accumulatedContent;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _chatHistory.last['content'] = '❌ 修改失败: $e';
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatHistory.last['content'] = '❌ 请求异常: $e';
        _isLoading = false;
      });
    }
  }

  String _buildSystemPrompt() {
    return '''你是一个专业的文本编辑助手。用户会给你一段文本，并要求你对其进行修改。

**重要规则：**
1. 仅输出修改后的纯文本内容
2. 严禁输出任何解释、说明或多余文字
3. 严禁使用 Markdown 代码块（如 ```）包裹输出
4. 直接输出最终文本，不要添加任何前缀或后缀

用户的原始文本将作为上下文提供，请根据用户的指令进行精准修改。''';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(colorScheme),
          const Divider(height: 1),
          _buildOriginalPreview(colorScheme),
          const Divider(height: 1),
          _buildDraftPreview(colorScheme),
          const Divider(height: 1),
          Expanded(child: _buildChatArea(colorScheme)),
          const Divider(height: 1),
          _buildInputArea(colorScheme),
          _buildBottomBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final settings = context.watch<SettingsService>();
    final promptService = context.watch<PromptService>();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_fix_high,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 调优助手',
                  style: TextStyle(
                    fontSize: 14, // 稍微调小一点以容纳两行
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // 模式切换器
                SizedBox(
                  height: 24,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: settings.activeEditPromptId.isNotEmpty &&
                              promptService.editPrompts.any(
                                  (p) => p.id == settings.activeEditPromptId)
                          ? settings.activeEditPromptId
                          : (promptService.editPrompts.isNotEmpty
                              ? promptService.editPrompts.first.id
                              : null),
                      isDense: true,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                      ),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          settings.setActiveEditPromptId(newValue);
                        }
                      },
                      items: promptService.editPrompts.map((p) {
                        return DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildOriginalPreview(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.text_snippet_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '原始文本',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.selectedText.length} 字',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.3),
              ),
            ),
            child: Text(
              widget.selectedText,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftPreview(ColorScheme colorScheme) {
    final hasChanges = _currentDraft != widget.selectedText;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.edit_document,
                size: 16,
                color: hasChanges
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'AI 修改预览',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasChanges
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (hasChanges)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '已修改',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasChanges
                  ? colorScheme.primaryContainer.withOpacity(0.3)
                  : colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasChanges
                    ? colorScheme.primary.withOpacity(0.3)
                    : colorScheme.outlineVariant.withOpacity(0.3),
              ),
            ),
            child: hasChanges
                ? _buildHighlightedDiff(colorScheme)
                : Text(
                    '等待 AI 修改...',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedDiff(ColorScheme colorScheme) {
    // 简单的差异化高亮：显示完整修改后的文本
    return Text(
      _currentDraft,
      style: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: colorScheme.onSurface,
        fontFamily: 'monospace',
        backgroundColor: colorScheme.primaryContainer.withOpacity(0.3),
      ),
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildChatArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '对话记录',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _chatHistory.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_outlined,
                          size: 32,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '输入修改意见开始对话',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '如："精简一点"、"添加注释"',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                colorScheme.onSurfaceVariant.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _chatHistory.length,
                    itemBuilder: (context, index) {
                      final msg = _chatHistory[index];
                      final isUser = msg['role'] == 'user';
                      return _buildChatBubble(
                          msg['content'] ?? '', isUser, colorScheme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(
      String content, bool isUser, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isUser
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10).copyWith(
              topLeft:
                  isUser ? const Radius.circular(10) : const Radius.circular(2),
              topRight:
                  isUser ? const Radius.circular(2) : const Radius.circular(10),
            ),
          ),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isUser
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: '输入修改意见...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _isLoading
                ? colorScheme.surfaceContainerHighest
                : colorScheme.primary,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _isLoading ? null : _sendMessage,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: _isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Icons.send,
                        color: _isLoading
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onPrimary,
                        size: 18,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    final hasChanges = _currentDraft != widget.selectedText;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('退回'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                side: BorderSide(color: colorScheme.outline),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed:
                  hasChanges ? () => widget.onApplyChange(_currentDraft) : null,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('确定'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                backgroundColor: hasChanges
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: hasChanges
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
