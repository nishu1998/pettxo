import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/support_faq_content.dart';
import '../../data/support_repository.dart';
import '../../domain/models/support_models.dart';
import '../widgets/support_widgets.dart';
import 'create_support_ticket_screen.dart';
import 'my_support_tickets_screen.dart';
import 'support_ticket_detail_screen.dart';

class HelpSupportScreen extends StatelessWidget {
  HelpSupportScreen({super.key});

  final SupportRepository _repository = SupportRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SupportScreenHeader(
              title: 'Help & Support',
              subtitle:
                  'Find quick answers, review your tickets, or contact Pettxo support.',
            ),
            Expanded(
              child: StreamBuilder<List<SupportTicket>>(
                stream: _repository.watchMyTickets(limit: 3),
                builder: (context, snapshot) {
                  final recentTickets =
                      snapshot.data ?? const <SupportTicket>[];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.quiz_outlined,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Frequently Asked Questions',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ...supportFaqSections.map(
                              (section) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _FaqSection(section: section),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.support_agent_rounded,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Contact Support',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            MySupportTicketsScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text('View all'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Use support tickets for account, booking, payment, provider, safety, and technical issues.',
                              style: TextStyle(
                                color: AppColors.textGrey,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CreateSupportTicketScreen(),
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.add_comment_outlined),
                              label: const Text('Raise a Support Ticket'),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'My Support Tickets',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (snapshot.hasError)
                              const Text(
                                'We could not load your recent tickets right now.',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  height: 1.45,
                                ),
                              )
                            else if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                recentTickets.isEmpty)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            else if (recentTickets.isEmpty)
                              const Text(
                                'You haven’t raised any support tickets yet.',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  height: 1.45,
                                ),
                              )
                            else
                              ...recentTickets.map(
                                (ticket) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SupportTicketListTile(
                                    ticket: ticket,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              SupportTicketDetailScreen(
                                                ticketId: ticket.ticketId,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  const _FaqSection({required this.section});

  final SupportFaqSection section;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textGrey,
        title: Text(
          section.title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        children: section.items
            .map(
              (item) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.question,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.answer,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
