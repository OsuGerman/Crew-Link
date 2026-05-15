import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/convoy/application/convoy_providers.dart';
import '../domain/beta_feedback.dart';

enum FeedbackSubmitState { idle, submitting, success, error }

class BetaFeedbackNotifier extends StateNotifier<FeedbackSubmitState> {
  BetaFeedbackNotifier({
    required this.userId,
    FirebaseFirestore? firestore,
  })  : _firestoreOverride = firestore,
        super(FeedbackSubmitState.idle);

  final String userId;
  final FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  Future<void> submit({
    required FeedbackCategory category,
    required String message,
    required String buildVersion,
    String screenContext = '',
  }) async {
    if (message.trim().isEmpty) return;
    state = FeedbackSubmitState.submitting;
    try {
      final feedback = BetaFeedback(
        userId: userId,
        category: category.name,
        message: message.trim(),
        submittedAt: DateTime.now(),
        screenContext: screenContext,
        buildVersion: buildVersion,
      );
      await _firestore
          .collection('beta_feedback')
          .add(feedback.toJson());
      state = FeedbackSubmitState.success;
    } catch (_) {
      state = FeedbackSubmitState.error;
      rethrow;
    }
  }

  void reset() => state = FeedbackSubmitState.idle;
}

final betaFeedbackProvider =
    StateNotifierProvider.autoDispose<BetaFeedbackNotifier, FeedbackSubmitState>(
  (ref) => BetaFeedbackNotifier(userId: ref.watch(selfMemberIdProvider)),
);
