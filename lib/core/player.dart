import 'package:flutter/material.dart';
import 'theme.dart';

class Player {
  final String id;
  final String name;
  final Color color;
  final String? avatarPath; // local file path, not sent over network

  const Player({required this.id, required this.name, required this.color, this.avatarPath});

  // avatarPath is intentionally NOT serialised — each device keeps its own photo
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color.value};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
    id: j['id'] as String,
    name: j['name'] as String,
    color: Color(j['color'] as int),
    // avatarPath stays null for remote players (they show color circle instead)
  );

  Player copyWith({String? avatarPath}) => Player(
    id: id, name: name, color: color, avatarPath: avatarPath ?? this.avatarPath);
}

class PlayerSetupState extends ChangeNotifier {
  String name = '';
  Color color = kPlayerColors[0];

  void setName(String v) { name = v; notifyListeners(); }
  void setColor(Color c) { color = c; notifyListeners(); }

  Player build(String idPrefix) => Player(
    id: '$idPrefix-${DateTime.now().millisecondsSinceEpoch}',
    name: name.isEmpty ? 'Player' : name,
    color: color,
  );
}
