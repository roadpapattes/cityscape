// lib/core/widgets/timer_badge.dart

import 'package:flutter/material.dart';
import '../../services/game_timer_service.dart';

class TimerBadge extends StatelessWidget {
  const TimerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GameTimer.instance,
      builder: (_, __) {
        if (!GameTimer.instance.isRunning) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            GameTimer.instance.elapsedText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
