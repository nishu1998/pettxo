import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/support_repository.dart';
import '../../domain/models/support_models.dart';
import '../widgets/support_widgets.dart';
import 'create_support_ticket_screen.dart';
import 'support_ticket_detail_screen.dart';

class MySupportTicketsScreen extends StatelessWidget {
  MySupportTicketsScreen({super.key});

  final SupportRepository _repository = SupportRepository();

  Future<void> _refresh() => _repository.refreshMyTickets();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SupportScreenHeader(
              title: 'My Support Tickets',
              subtitle:
                  'Track replies, status updates, and past conversations.',
            ),
            Expanded(
              child: StreamBuilder<List<SupportTicket>>(
                stream: _repository.watchMyTickets(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const SupportStatePane(
                      icon: Icons.support_agent_outlined,
                      title: 'Tickets are unavailable',
                      message:
                          'We could not load your support tickets right now.',
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  final tickets = snapshot.data ?? const <SupportTicket>[];
                  if (tickets.isEmpty) {
                    return SupportStatePane(
                      icon: Icons.inbox_outlined,
                      title: 'No support tickets yet',
                      message: 'You haven’t raised any support tickets yet.',
                      actionLabel: 'Raise a ticket',
                      onAction: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CreateSupportTicketScreen(),
                          ),
                        );
                      },
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: AppColors.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      itemCount: tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final ticket = tickets[index];
                        return SupportTicketListTile(
                          ticket: ticket,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SupportTicketDetailScreen(
                                  ticketId: ticket.ticketId,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateSupportTicketScreen(),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Raise ticket'),
      ),
    );
  }
}
