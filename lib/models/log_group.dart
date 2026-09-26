import 'package:flutter/material.dart';

import 'member.dart';

class EfocLogGroup {
  final String id;
  final String name;
  final String ownerId;
  final Color avatarColor;
  final List<EfocMember> members;
  final bool isPersonal;

  const EfocLogGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.avatarColor,
    required this.members,
    this.isPersonal = false,
  });
}