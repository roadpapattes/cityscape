// lib/core/widgets/creator_feedback_sheet.dart

import 'package:flutter/material.dart';
import '../../services/api/api_service.dart';

/// Opens a bottom sheet to send creator feedback
Future<void> openCreatorFeedbackSheet(
  BuildContext context, {
  int? escapeId,
  int? stepId,
  String? page,
}) async {
  final txt = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final padding = EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
        left: 16, right: 16, top: 16,
      );
      return Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Envoyer un feedback créateur',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: txt,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: "Décris le bug ou l'amélioration souhaitée…",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer'),
                  onPressed: () async {
                    final message = txt.text.trim();
                    if (message.length < 10) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Merci de détailler un peu (≥ 10 caractères).")),
                      );
                      return;
                    }
                    try {
                      await ApiService.instance.sendCreatorFeedback(
                        message: message,
                        escapeId: escapeId,
                        stepId: stepId,
                        page: page ?? 'creator_hub',
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Merci pour ton feedback !')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Envoi impossible : $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
