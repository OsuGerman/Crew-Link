import 'package:freezed_annotation/freezed_annotation.dart';

part 'beta_feedback.g.dart';
part 'beta_feedback.freezed.dart';

@freezed
class BetaFeedback with _$BetaFeedback {
  const factory BetaFeedback({
    required String userId,
    required String category,
    required String message,
    required DateTime submittedAt,
    @Default('') String screenContext,
    @Default('') String buildVersion,
  }) = _BetaFeedback;

  factory BetaFeedback.fromJson(Map<String, dynamic> json) =>
      _$BetaFeedbackFromJson(json);
}

enum FeedbackCategory { bug, ux, performance, feature, other }

extension FeedbackCategoryLabel on FeedbackCategory {
  String get label => switch (this) {
        FeedbackCategory.bug => 'Bug',
        FeedbackCategory.ux => 'UX / Usability',
        FeedbackCategory.performance => 'Performance',
        FeedbackCategory.feature => 'Feature-Wunsch',
        FeedbackCategory.other => 'Sonstiges',
      };
}
