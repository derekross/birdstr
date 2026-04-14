import 'package:flutter/material.dart';

import '../../models/observation.dart';
import '../../services/nostr_service.dart';
import '../../services/social_service.dart';

/// Confirm/Dispute buttons + verification counts for an observation.
class VerificationButtons extends StatefulWidget {
  const VerificationButtons({super.key, required this.observation});

  final Observation observation;

  @override
  State<VerificationButtons> createState() => _VerificationButtonsState();
}

class _VerificationButtonsState extends State<VerificationButtons> {
  int _confirmed = 0;
  int _disputed = 0;
  bool _loading = true;
  bool _hasVoted = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final counts = await SocialService.instance.getVerificationCounts(
      widget.observation.eventId,
    );
    if (mounted) {
      setState(() {
        _confirmed = counts.confirmed;
        _disputed = counts.disputed;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    if (_hasVoted || !NostrService.instance.isAuthenticated) return;
    setState(() => _hasVoted = true);

    final result = await SocialService.instance.confirmObservation(
      observationEventId: widget.observation.eventId,
      observationPubkey: widget.observation.pubkey,
    );

    if (result != null && mounted) {
      setState(() => _confirmed++);
    }
  }

  Future<void> _dispute() async {
    if (_hasVoted || !NostrService.instance.isAuthenticated) return;
    setState(() => _hasVoted = true);

    final result = await SocialService.instance.disputeObservation(
      observationEventId: widget.observation.eventId,
      observationPubkey: widget.observation.pubkey,
    );

    if (result != null && mounted) {
      setState(() => _disputed++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final isOwnObservation =
        widget.observation.pubkey == NostrService.instance.publicKey;

    return Row(
      children: [
        // Confirm button
        _VoteChip(
          icon: Icons.check_circle_outline,
          activeIcon: Icons.check_circle,
          label: '$_confirmed',
          color: Colors.green,
          onPressed: (!_hasVoted && !isOwnObservation) ? _confirm : null,
          isActive: _hasVoted && _confirmed > 0,
        ),
        const SizedBox(width: 8),
        // Dispute button
        _VoteChip(
          icon: Icons.cancel_outlined,
          activeIcon: Icons.cancel,
          label: '$_disputed',
          color: Colors.red,
          onPressed: (!_hasVoted && !isOwnObservation) ? _dispute : null,
          isActive: _hasVoted && _disputed > 0,
        ),
      ],
    );
  }
}

class _VoteChip extends StatelessWidget {
  const _VoteChip({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? color.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withAlpha(onPressed != null ? 80 : 30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 16,
              color: color.withAlpha(onPressed != null || isActive ? 255 : 80),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withAlpha(
                  onPressed != null || isActive ? 255 : 80,
                ),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
