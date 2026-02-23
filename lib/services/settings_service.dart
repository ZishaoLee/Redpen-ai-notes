import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_config.dart';

/// 设置服务 — 管理 API Key / Base URL / 模型名称等用户配置的持久化存储。
///
/// 使用 [SharedPreferences] 实现本地存储，
/// 继承 [ChangeNotifier] 以配合 Provider 进行状态管理。
///
/// V3 Update: 引入模型仓库 (Model Repository)，支持多模型管理与快速切换
class SettingsService extends ChangeNotifier {
  // Legacy Keys
  static const _keyApiKey = 'api_key';
  static const _keyOpenAIApiKey = 'openai_api_key';
  static const _keyGeminiApiKey = 'gemini_api_key';
  static const _keyOpenAIModelName = 'openai_model_name';
  static const _keyGeminiModelName = 'gemini_model_name';
  static const _keyOpenAIBaseUrl = 'openai_base_url';

  static const _keyWorkspace = 'current_workspace';
  static const _keyLastSaveSubfolder = 'last_save_subfolder';
  static const _keyRecentFolders = 'recent_folders_v1';

  // V2 Keys
  static const _keyVisionConfig = 'vision_config_v2';
  static const _keyEditConfig = 'edit_config_v2';
  static const _keyVisionPromptId = 'vision_prompt_id';
  static const _keyEditPromptId = 'edit_prompt_id';

  // V3 Keys
  static const _keySavedModels = 'saved_models_v3';

  /// Documents 基准路径（Android 标准文档目录）。
  static const documentsBasePath = '/storage/emulated/0/Documents';

  String _currentWorkspace = 'Math1';
  String _lastSaveSubfolder = '';
  List<String> _recentFolders = [];

  // Active Configs (can be custom or copied from repository)
  late AIConfig _visionConfig;
  late AIConfig _editConfig;

  // Model Repository
  List<AIConfig> _savedModels = [];

  String _activeVisionPromptId = '';
  String _activeEditPromptId = '';

  late final Future<void> _initFuture;

  String get currentWorkspace => _currentWorkspace;
  String get lastSaveSubfolder => _lastSaveSubfolder;
  List<String> get recentFolders => List.unmodifiable(_recentFolders);

  AIConfig get visionConfig => _visionConfig;
  AIConfig get editConfig => _editConfig;
  List<AIConfig> get savedModels => List.unmodifiable(_savedModels);

  String get activeVisionPromptId => _activeVisionPromptId;
  String get activeEditPromptId => _activeEditPromptId;

  /// 当前工作区的完整路径。
  String get workspacePath => '$documentsBasePath/$_currentWorkspace';

  /// 等待初始化加载完成
  Future<void> ensureLoaded() => _initFuture;

  SettingsService() {
    _visionConfig = AIConfig.defaultConfig();
    _editConfig = AIConfig.defaultConfig().copyWith(
        provider: 'gemini',
        modelName: 'gemini-2.0-flash',
        name: 'Gemini (Default)');
    _initFuture = _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentWorkspace = prefs.getString(_keyWorkspace) ?? 'Math1';
    _lastSaveSubfolder = prefs.getString(_keyLastSaveSubfolder) ?? '';
    _recentFolders = prefs.getStringList(_keyRecentFolders) ?? [];

    // 1. Load Repository
    final savedJson = prefs.getStringList(_keySavedModels);
    if (savedJson != null) {
      _savedModels =
          savedJson.map((str) => AIConfig.fromJson(jsonDecode(str))).toList();
    } else {
      // Initialize with defaults if empty
      _savedModels = [
        AIConfig.defaultConfig(),
        AIConfig.defaultConfig().copyWith(
            provider: 'gemini',
            modelName: 'gemini-2.0-flash',
            name: 'Gemini Flash',
            baseUrl: 'https://generativelanguage.googleapis.com'),
      ];
      _saveRepository(prefs);
    }

    // 2. Load Active Configs
    final visionJson = prefs.getString(_keyVisionConfig);
    if (visionJson != null) {
      try {
        _visionConfig = AIConfig.fromJson(jsonDecode(visionJson));
      } catch (e) {
        debugPrint('Error loading vision config: $e');
      }
    } else {
      final legacyProvider = prefs.getString('vision_provider') ?? 'openai';
      _visionConfig = _migrateConfig(prefs, legacyProvider);
    }

    final editJson = prefs.getString(_keyEditConfig);
    if (editJson != null) {
      try {
        _editConfig = AIConfig.fromJson(jsonDecode(editJson));
      } catch (e) {
        debugPrint('Error loading edit config: $e');
      }
    } else {
      final legacyProvider = prefs.getString('edit_provider') ?? 'gemini';
      _editConfig = _migrateConfig(prefs, legacyProvider);
    }

    _activeVisionPromptId = prefs.getString(_keyVisionPromptId) ?? '';
    _activeEditPromptId = prefs.getString(_keyEditPromptId) ?? '';

    notifyListeners();
  }

  AIConfig _migrateConfig(SharedPreferences prefs, String provider) {
    String apiKey = '';
    String model = '';
    String baseUrl = '';

    if (provider == 'openai') {
      apiKey = prefs.getString(_keyOpenAIApiKey) ??
          prefs.getString(_keyApiKey) ??
          '';
      model = prefs.getString(_keyOpenAIModelName) ?? 'gpt-4o';
      baseUrl =
          prefs.getString(_keyOpenAIBaseUrl) ?? 'https://api.openai.com/v1';
    } else {
      apiKey = prefs.getString(_keyGeminiApiKey) ??
          prefs.getString(_keyApiKey) ??
          '';
      model = prefs.getString(_keyGeminiModelName) ?? 'gemini-2.0-flash';
      baseUrl = 'https://generativelanguage.googleapis.com';
    }

    return AIConfig(
      name: '${provider.toUpperCase()} (Legacy)',
      provider: provider,
      apiKey: apiKey,
      modelName: model,
      baseUrl: baseUrl,
    );
  }

  Future<void> _saveRepository([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    final list = _savedModels.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keySavedModels, list);
    notifyListeners();
  }

  // ── Repository Management ──

  Future<void> addSavedModel(AIConfig config) async {
    _savedModels.add(config);
    await _saveRepository();
  }

  Future<void> updateSavedModel(AIConfig config) async {
    final index = _savedModels.indexWhere((m) => m.id == config.id);
    if (index != -1) {
      _savedModels[index] = config;
      await _saveRepository();

      // Auto-update active configs if they match the ID
      bool changed = false;
      if (_visionConfig.id == config.id) {
        _visionConfig = config;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _keyVisionConfig, jsonEncode(_visionConfig.toJson()));
        changed = true;
      }
      if (_editConfig.id == config.id) {
        _editConfig = config;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyEditConfig, jsonEncode(_editConfig.toJson()));
        changed = true;
      }
      if (changed) notifyListeners();
    }
  }

  Future<void> removeSavedModel(String id) async {
    _savedModels.removeWhere((m) => m.id == id);
    await _saveRepository();
  }

  Future<void> reorderModels(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _savedModels.removeAt(oldIndex);
    _savedModels.insert(newIndex, item);
    await _saveRepository();
  }

  // ── Active Config Setters ──

  Future<void> setVisionConfig(AIConfig config) async {
    if (_visionConfig.id != config.id) {
      debugPrint(
          '[Model Switch] Vision: ${_visionConfig.name} (${_visionConfig.id}) -> ${config.name} (${config.id}) at ${DateTime.now()}');
    }
    _visionConfig = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVisionConfig, jsonEncode(config.toJson()));
    notifyListeners();
  }

  Future<void> setEditConfig(AIConfig config) async {
    if (_editConfig.id != config.id) {
      debugPrint(
          '[Model Switch] Edit: ${_editConfig.name} (${_editConfig.id}) -> ${config.name} (${config.id}) at ${DateTime.now()}');
    }
    _editConfig = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEditConfig, jsonEncode(config.toJson()));
    notifyListeners();
  }

  // ── Other Setters ──

  Future<void> setCurrentWorkspace(String workspace) async {
    _currentWorkspace = workspace.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWorkspace, _currentWorkspace);
    notifyListeners();
  }

  Future<void> setLastSaveSubfolder(String path) async {
    _lastSaveSubfolder = path.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSaveSubfolder, _lastSaveSubfolder);
    notifyListeners();
  }

  Future<void> addRecentFolder(String path) async {
    final cleanPath = path.trim();
    if (cleanPath.isEmpty) return;

    _recentFolders.remove(cleanPath);
    _recentFolders.insert(0, cleanPath);

    if (_recentFolders.length > 10) {
      _recentFolders = _recentFolders.sublist(0, 10);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyRecentFolders, _recentFolders);
    notifyListeners();
  }

  Future<void> setActiveVisionPromptId(String id) async {
    if (_activeVisionPromptId == id) return;
    _activeVisionPromptId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVisionPromptId, _activeVisionPromptId);
    notifyListeners();
  }

  Future<void> setActiveEditPromptId(String id) async {
    if (_activeEditPromptId == id) return;
    _activeEditPromptId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEditPromptId, _activeEditPromptId);
    notifyListeners();
  }

  Future<void> clearAll() async {
    _currentWorkspace = 'Math1';
    _visionConfig = AIConfig.defaultConfig();
    _editConfig = AIConfig.defaultConfig().copyWith(provider: 'gemini');
    _activeVisionPromptId = '';
    _activeEditPromptId = '';
    _lastSaveSubfolder = '';
    _recentFolders = [];
    _savedModels = [
      AIConfig.defaultConfig(),
      AIConfig.defaultConfig().copyWith(
          provider: 'gemini',
          modelName: 'gemini-2.0-flash',
          name: 'Gemini Flash'),
    ];

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _saveRepository(prefs); // Re-save defaults

    notifyListeners();
  }
}
