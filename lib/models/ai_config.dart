import 'package:uuid/uuid.dart';

class AIConfig {
  String id;
  String name; // User friendly name
  String provider; // 'openai' or 'gemini'
  String apiKey;
  String modelName;
  String baseUrl;
  List<String> backupBaseUrls;
  int latency; // Last measured latency in ms, -1 if unknown

  AIConfig({
    String? id,
    this.name = 'Default Model',
    required this.provider,
    required this.apiKey,
    required this.modelName,
    required this.baseUrl,
    this.backupBaseUrls = const [],
    this.latency = -1,
  }) : id = id ?? const Uuid().v4();

  factory AIConfig.defaultConfig() {
    return AIConfig(
      name: 'OpenAI (Default)',
      provider: 'openai',
      apiKey: '',
      modelName: 'gpt-4o',
      baseUrl: 'https://api.openai.com/v1',
      backupBaseUrls: [],
    );
  }

  // Deep copy
  AIConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? apiKey,
    String? modelName,
    String? baseUrl,
    List<String>? backupBaseUrls,
    int? latency,
  }) {
    return AIConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      baseUrl: baseUrl ?? this.baseUrl,
      backupBaseUrls: backupBaseUrls ?? List.from(this.backupBaseUrls),
      latency: latency ?? this.latency,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'apiKey': apiKey,
      'modelName': modelName,
      'baseUrl': baseUrl,
      'backupBaseUrls': backupBaseUrls,
      'latency': latency,
    };
  }

  factory AIConfig.fromJson(Map<String, dynamic> json) {
    return AIConfig(
      id: json['id'],
      name: json['name'] ?? 'Unnamed Model',
      provider: json['provider'] ?? 'openai',
      apiKey: json['apiKey'] ?? '',
      modelName: json['modelName'] ?? '',
      baseUrl: json['baseUrl'] ?? '',
      backupBaseUrls: (json['backupBaseUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      latency: json['latency'] ?? -1,
    );
  }
}
