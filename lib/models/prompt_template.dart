enum PromptType { vision, edit }

class PromptTemplate {
  final String id;
  final String name;
  final PromptType type;
  final String content;
  final int lastUsed;

  PromptTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.content,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'content': content,
      'lastUsed': lastUsed,
    };
  }

  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      id: json['id'],
      name: json['name'],
      type: PromptType.values.firstWhere((e) => e.name == json['type'],
          orElse: () => PromptType.vision),
      content: json['content'],
      lastUsed: json['lastUsed'] ?? 0,
    );
  }

  PromptTemplate copyWith({
    String? name,
    String? content,
    int? lastUsed,
  }) {
    return PromptTemplate(
      id: id,
      name: name ?? this.name,
      type: type,
      content: content ?? this.content,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}
