import 'app_localizations.dart';

class StringsSuderseeslach {
  final String gameName;
  final String gameDesc;
  final String placeShips;
  final String horizontal;
  final String vertical;
  final String yourWaters;
  final String enemyWaters;
  final String waitingOpponent;
  final String opponentTurn;
  final String yourTurn;
  final String placingShip;
  final String cells;
  final String winsExcl;
  final String yourTurnShoot;
  final String shipLemsteraak;
  final String shipGrutteTjalk;
  final String shipPream;
  final String shipSkutsje;
  final String shipFjouwerMaster;
  final String resetBoard;
  final String rules;

  const StringsSuderseeslach({
    required this.gameName,
    required this.gameDesc,
    required this.placeShips,
    required this.horizontal,
    required this.vertical,
    required this.yourWaters,
    required this.enemyWaters,
    required this.waitingOpponent,
    required this.opponentTurn,
    required this.yourTurn,
    required this.placingShip,
    required this.cells,
    required this.winsExcl,
    required this.yourTurnShoot,
    required this.shipLemsteraak,
    required this.shipGrutteTjalk,
    required this.shipPream,
    required this.shipSkutsje,
    required this.shipFjouwerMaster,
    required this.resetBoard,
    required this.rules,
  });

  factory StringsSuderseeslach.of(AppLang l) => switch (l) {
    AppLang.fy => StringsSuderseeslach.fy(),
    AppLang.nl => StringsSuderseeslach.nl(),
    AppLang.en => StringsSuderseeslach.en(),
  };

  factory StringsSuderseeslach.fy() => const StringsSuderseeslach(
    gameName:        'Suderseeslach',
    gameDesc:        'Sink de float',
    placeShips:      'Set jo skippen del',
    horizontal:      '↔ Rjocht',
    vertical:        '↕ Omheech',
    yourWaters:      'Dyn Wetters',
    enemyWaters:     'Fijanlike Wetters',
    waitingOpponent: 'Wachtsje op tsjinstanner…',
    opponentTurn:    'Beurt fan tsjinstanner…',
    yourTurn:        'Dyn beurt!',
    placingShip:     '{name} ({len} fjilden)',
    cells:           'fjilden',
    winsExcl:        '{player} wint!',
    yourTurnShoot:   'Dyn beurt — tikje op it fijanlike fjild',
    shipLemsteraak:    'Lemsteraak',
    shipGrutteTjalk:   'Grutte tjalk',
    shipPream:         'Pream',
    shipSkutsje:       'Skûtsje',
    shipFjouwerMaster: 'Fjouwer-master',
    resetBoard:      'Opnij',
    rules:             'Plak dyn skippen op dyn boerd, dan skieten om bar op it boerd fan de tsjinstanner. Raak alle skippen fan de tsjinstanner earst om te winnen!',
  );

  factory StringsSuderseeslach.nl() => const StringsSuderseeslach(
    gameName:        'Zuiderzeeslag',
    gameDesc:        'Vloot zinken',
    placeShips:      'Zet uw schepen neer',
    horizontal:      '↔ Horiz',
    vertical:        '↕ Vert',
    yourWaters:      'Jouw Wateren',
    enemyWaters:     'Vijandelijke Wateren',
    waitingOpponent: 'Wachten op tegenstander…',
    opponentTurn:    'Beurt van tegenstander…',
    yourTurn:        'Jouw beurt!',
    placingShip:     '{name} ({len} vakjes)',
    cells:           'vakjes',
    winsExcl:        '{player} wint!',
    yourTurnShoot:   'Jouw beurt — tik op het vijandelijke veld',
    shipLemsteraak:    'Lemsteraak',
    shipGrutteTjalk:   'Grutte tjalk',
    shipPream:         'Pream',
    shipSkutsje:       'Skûtsje',
    shipFjouwerMaster: 'Fjouwer-master',
    resetBoard:      'Opnieuw',
    rules:             'Plaats je schepen op je bord, dan om de beurt schieten op het bord van de tegenstander. Tref alle schepen van de tegenstander als eerste om te winnen!',
  );

  factory StringsSuderseeslach.en() => const StringsSuderseeslach(
    gameName:        'Sea Battle',
    gameDesc:        'Sink the fleet',
    placeShips:      'Place your ships',
    horizontal:      '↔ Horiz',
    vertical:        '↕ Vert',
    yourWaters:      'Your Waters',
    enemyWaters:     'Enemy Waters',
    waitingOpponent: 'Waiting for opponent…',
    opponentTurn:    'Opponent\'s turn…',
    yourTurn:        'Your turn!',
    placingShip:     '{name} ({len} cells)',
    cells:           'cells',
    winsExcl:        '{player} wins!',
    yourTurnShoot:   'Your turn — tap enemy grid',
    shipLemsteraak:    'Lemsteraak',
    shipGrutteTjalk:   'Grutte tjalk',
    shipPream:         'Pream',
    shipSkutsje:       'Skûtsje',
    shipFjouwerMaster: 'Fjouwer-master',
    resetBoard:      'Reset',
    rules:             'Place your ships on your board, then take turns shooting at your opponent\'s board. Sink all of your opponent\'s ships first to win!',
  );
}
