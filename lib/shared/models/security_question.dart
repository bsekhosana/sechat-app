class SecurityQuestion {
  final int id;
  final String questionText;

  SecurityQuestion({
    required this.id,
    required this.questionText,
  });

  factory SecurityQuestion.fromJson(Map<String, dynamic> json) {
    return SecurityQuestion(
      id: json['id'],
      questionText: json['question_text'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question_text': questionText,
    };
  }

  @override
  String toString() {
    return 'SecurityQuestion(id: $id, questionText: $questionText)';
  }
}
