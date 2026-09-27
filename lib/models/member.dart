import 'package:flutter/material.dart';

class EfocMember {
  final String id;
  final String name;
  final Color color;
  final bool isMe;
  final String? avatarUrl;

  const EfocMember({
    required this.id,
    required this.name,
    required this.color,
    this.isMe = false,
    this.avatarUrl,
  });
}