import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// Plain list of what Efoc keeps about you and who can see it.
class WhatWeStoreScreen extends StatelessWidget {
  const WhatWeStoreScreen({super.key});

  static const _items = [
    (
      'Your login',
      'Either your email, or just a username with a recovery code. The code '
          'is stored scrambled (hashed), so nobody can read it, not even us. '
          'Your email is never shown to other members.',
    ),
    (
      'Your profile',
      'Display name, username and avatar. Members of your Logs see these.',
    ),
    (
      'Your clips',
      'Videos and captions you post, seen only by members of that Log. '
          'Raw clips stay on the server for about a day, then are deleted.',
    ),
    (
      'Daily vlogs',
      'The stitched video for each Log and day. It includes everyone\'s '
          'clips, so it stays with the Log. The server keeps it up to 7 '
          'days, and whoever runs Efoc keeps a backup copy offline.',
    ),
    (
      'Chat',
      'Messages and reactions you send in a Log, seen by its members.',
    ),
    (
      'Your devices',
      'A notification token for each phone or browser, so reminders reach '
          'you. Removed when you sign out there.',
    ),
    (
      'Card games',
      'Your user id and moves while a table is open. Nothing else.',
    ),
    (
      'Not stored',
      'Your phone number, contacts, location or real name (unless you '
          'type it as your display name).',
    ),
    (
      'Deleting',
      'Account › Delete account removes your login, profile, clips, '
          'messages and files. Logs you own go to another member, or are '
          'deleted if you\'re the only one in them.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EfocColors.bg,
      appBar: AppBar(
        backgroundColor: EfocColors.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('What we store'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (_, i) {
          final (title, body) = _items[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
