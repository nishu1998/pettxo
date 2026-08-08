class SupportFaqItem {
  const SupportFaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

class SupportFaqSection {
  const SupportFaqSection({required this.title, required this.items});

  final String title;
  final List<SupportFaqItem> items;
}

const List<SupportFaqSection> supportFaqSections = <SupportFaqSection>[
  SupportFaqSection(
    title: 'Account & Profile',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'How do I update my profile details?',
        answer:
            'Open Profile or Settings to update your display information, pet details, service details, and contact methods connected to your account.',
      ),
      SupportFaqItem(
        question: 'How do I delete my account?',
        answer:
            'Use Account & Security inside Settings to request account deletion. Pettxo may keep limited records where required for bookings, payments, safety, or legal compliance.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Booking a Service',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'Why can’t I book a slot I selected?',
        answer:
            'A slot can become unavailable if another customer reserves it first, the provider updates availability, or the service is paused. Refresh and try again.',
      ),
      SupportFaqItem(
        question: 'When is my booking confirmed?',
        answer:
            'A booking becomes fully confirmed after the provider accepts it and any required payment is completed successfully inside Pettxo.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Payments',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'Why did my payment fail?',
        answer:
            'Payment failures can happen because of bank approval issues, expired payment windows, or network interruptions. You can try again if the booking is still eligible.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Cancellations & Refunds',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'How are refunds handled?',
        answer:
            'Refund timing depends on the booking state, provider acceptance, and the payment partner. Open your booking details for the latest refund status.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Provider / Service Issues',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'What should I do if a provider is unavailable?',
        answer:
            'Open the booking details first for the latest lifecycle status. If the issue still needs review, raise a support ticket with your booking ID and what happened.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Safety & Verification',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'How does Pettxo handle safety concerns?',
        answer:
            'Pettxo can review safety reports, provider verification issues, and suspicious activity. Include as much detail as possible when you contact support.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Notifications',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'Why am I not receiving notifications?',
        answer:
            'Check your in-app notification settings, device notification permissions, and background restrictions. Some alerts also depend on network availability.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Technical Problems',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'What should I include in a technical issue ticket?',
        answer:
            'Share the screen name, the action you took, what you expected, what happened instead, and whether the issue is repeatable. Screenshots help when available.',
      ),
    ],
  ),
  SupportFaqSection(
    title: 'Privacy & Account Deletion',
    items: <SupportFaqItem>[
      SupportFaqItem(
        question: 'How is my support information used?',
        answer:
            'Support tickets are used only for customer assistance, safety review, moderation, operational follow-up, and compliance where needed.',
      ),
    ],
  ),
];
