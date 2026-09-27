import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../core/player.dart';
import '../games/boppeslach/boppeslach_screen.dart';
import '../games/buterbreaengrienetsiis/buterbreaengrienetsiis_screen.dart';
import '../games/fjouweropinrige/fjouweropinrige_screen.dart';
import '../games/skaken/skaken_screen.dart';
import '../games/damjen/damjen_screen.dart';
import '../games/suderseeslach/suderseeslach_screen.dart';
import '../games/puntenenfakjes/puntenenfakjes_screen.dart';
import '../games/unthaldspultsje/unthaldspultsje_screen.dart';
import '../games/kruske/kruske_screen.dart';
import '../games/rupsen/rupsen_screen.dart';
import '../games/rekkenje/rekkenje_screen.dart';
import '../games/rekkenje/rekkenje_state.dart';
import '../games/ludo/ludo_screen.dart';
import '../games/paddelduel/paddelduel_screen.dart';
import '../games/kleurecho/kleurecho_screen.dart';
import '../games/sudokuduel/sudokuduel_screen.dart';
import '../games/wurdspul/wurdspul_screen.dart';
import '../games/skofpuzzel/skofpuzzel_screen.dart';
import '../games/slange/slange_screen.dart';
import '../games/tekenjeenriede/tekenjeenriede_screen.dart';
import '../games/aaisykje/aaisykje_screen.dart';
import '../games/domino/domino_screen.dart';
import '../games/wabistdo/wabistdo_screen.dart';
import '../games/klaverjassen/klaverjassen_screen.dart';
import '../games/wurdsikerij/wurdsikerij_screen.dart';
import '../games/patience/patience_screen.dart';
import '../games/lofthockey/lofthockey_screen.dart';
import '../games/ienentritich/ienentritich_screen.dart';
import '../games/tikrazernij/tikrazernij_screen.dart';
import '../games/fluchtekenje/fluchtekenje_screen.dart';

class GameInfo {
  final String id, icon, name, desc;
  final int? maxPlayers; // null = no limit
  const GameInfo({required this.id, required this.icon, required this.name,
    required this.desc, this.maxPlayers});
}

List<GameInfo> get kGames => [
  GameInfo(id: 'boppeslach',        icon: '🎲', name: L.boppeslach.gameName,        desc: L.boppeslach.gameDesc),
  GameInfo(id: 'ludo',        icon: '🎯', name: L.ludo.gameName,        desc: L.ludo.gameDesc,          maxPlayers: 4),
  GameInfo(id: 'kruske',      icon: '✕',  name: L.kruske.gameName,      desc: L.kruske.gameDesc),
  GameInfo(id: 'rupsen',      icon: '🐛', name: L.rupsen.gameName,      desc: L.rupsen.gameDesc),
  GameInfo(id: 'rekkenje',   icon: '🧮', name: L.rekkenje.gameName,   desc: L.rekkenje.gameDesc),
  GameInfo(id: 'buterbreaengrienetsiis',   icon: '✕○', name: L.buterbreaengrienetsiis.gameName,   desc: L.buterbreaengrienetsiis.gameDesc,       maxPlayers: 2),
  GameInfo(id: 'fjouweropinrige',  icon: '🔵', name: L.fjouweropinrige.gameName,  desc: L.fjouweropinrige.gameDesc,         maxPlayers: 2),
  GameInfo(id: 'skaken',       icon: '♟',  name: L.skaken.gameName,       desc: L.skaken.gameDesc,     maxPlayers: 2),
  GameInfo(id: 'damjen',    icon: '🔴', name: L.damjen.gameName,    desc: L.damjen.gameDesc,    maxPlayers: 2),
  GameInfo(id: 'suderseeslach',  icon: '⚓', name: L.suderseeslach.gameName,  desc: L.suderseeslach.gameDesc,    maxPlayers: 2),
  GameInfo(id: 'puntenenfakjes',icon: '⬜', name: L.puntenenfakjes.gameName,desc: L.puntenenfakjes.gameDesc,  maxPlayers: 2),
  GameInfo(id: 'unthaldspultsje',      icon: '🃏', name: L.unthaldspultsje.gameName,      desc: L.unthaldspultsje.gameDesc,    maxPlayers: 2),
  GameInfo(id: 'paddelduel',        icon: '🏓', name: L.paddelduel.gameName,        desc: L.paddelduel.gameDesc,      maxPlayers: 2),
  GameInfo(id: 'kleurecho',       icon: '🔴', name: L.kleurecho.gameName,       desc: L.kleurecho.gameDesc,     maxPlayers: 2),
  GameInfo(id: 'sudokuduel',      icon: '🔢', name: L.sudokuduel.gameName,      desc: L.sudokuduel.gameDesc,    maxPlayers: 2),
  GameInfo(id: 'wurdspul',      icon: '🔤', name: L.wurdspul.gameName,      desc: L.wurdspul.gameDesc,      maxPlayers: 2),
  GameInfo(id: 'skofpuzzel',  icon: '🧩', name: L.skofpuzzel.gameName,  desc: L.skofpuzzel.gameDesc,  maxPlayers: 2),
  GameInfo(id: 'slange',          icon: '🐍', name: L.slange.gameName,          desc: L.slange.gameDesc,          maxPlayers: 2),
  GameInfo(id: 'tekenjeenriede',     icon: '🎨', name: L.tekenjeenriede.gameName,     desc: L.tekenjeenriede.gameDesc),
  GameInfo(id: 'aaisykje',       icon: '🥚', name: L.aaisykje.gameName,       desc: L.aaisykje.gameDesc,  maxPlayers: 2),
  GameInfo(id: 'domino',        icon: '🁣', name: L.domino.gameName,        desc: L.domino.gameDesc,   maxPlayers: 2),
  GameInfo(id: 'wabistdo',       icon: '🕵️', name: L.wabistdo.gameName,       desc: L.wabistdo.gameDesc,  maxPlayers: 2),
  GameInfo(id: 'klaverjassen',   icon: '🃏', name: L.klaverjassen.gameName,   desc: L.klaverjassen.gameDesc, maxPlayers: 2),
  GameInfo(id: 'wurdsikerij',    icon: '🔍', name: L.wurdsikerij.gameName,    desc: L.wurdsikerij.gameDesc,  maxPlayers: 4),
  GameInfo(id: 'patience',    icon: '🃏', name: L.patience.gameName,    desc: L.patience.gameDesc,   maxPlayers: 1),
  GameInfo(id: 'lofthockey',    icon: '🏒', name: L.lofthockey.gameName,    desc: L.lofthockey.gameDesc,   maxPlayers: 2),
  GameInfo(id: 'ienentritich',  icon: '🂡', name: L.ienentritich.gameName,  desc: L.ienentritich.gameDesc, maxPlayers: 4),
  GameInfo(id: 'tikrazernij',   icon: '👆', name: L.tikrazernij.gameName,   desc: L.tikrazernij.gameDesc,   maxPlayers: 4),
  GameInfo(id: 'fluchtekenje',   icon: '🖌', name: L.fluchtekenje.gameName,   desc: L.fluchtekenje.gameDesc,   maxPlayers: 4),
];

/// Builds the correct game screen widget for a given game id.
Widget buildGameScreen(String game, int firstPlayer, List<Player> players,
    [Map<String, dynamic>? extra]) {
  switch (game) {
    case 'boppeslach':         return BoppeslachScreen(players: players, firstPlayer: firstPlayer);
    case 'kruske':       return KruskeScreen(players: players, firstPlayer: firstPlayer);
    case 'rupsen':       return RupsenScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'ludo':         return LudoScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'rekkenje':
      final cfg = (extra != null && extra.containsKey('op'))
          ? RekkenjeConfig.fromJson(extra)
          : const RekkenjeConfig(op: RekkenjeOp.addition, maxVal: 20,
              rounds: 3, questionsPerRound: 10, secondsPerRound: 60);
      return RekkenjeScreen(players: players, firstPlayer: firstPlayer, config: cfg);
    case 'buterbreaengrienetsiis':    return ButerBreaEnGrieneTsiisScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'fjouweropinrige':   return FjouwerOpInRigeScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'skaken':        return SkakenScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'damjen':     return DamjenScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'suderseeslach':   return SuderseeslachScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'puntenenfakjes': return PuntenEnFakjesScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'unthaldspultsje':       return UnthaldspultsjeScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'paddelduel':         return PaddelduelScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'kleurecho':        return KleurEchoScreen(players: players, firstPlayer: firstPlayer);
    case 'sudokuduel':       return SudokuDuelScreen(players: players, firstPlayer: firstPlayer);
    case 'wurdspul':    return WurdspulScreen(players: players, firstPlayer: firstPlayer);
    case 'skofpuzzel': return SkofpuzzelScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'slange':        return SlangeScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'tekenjeenriede':   return TekenjeEnRiedeScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'aaisykje':      return AaisykjeScreen(players: players, firstPlayer: firstPlayer);
    case 'domino':       return DominoScreen(players: players, firstPlayer: firstPlayer);
    case 'wabistdo':      return WaBistDoScreen(players: players, firstPlayer: firstPlayer);
    case 'klaverjassen':  return KlaverjassenScreen(players: players, firstPlayer: firstPlayer);
    case 'wurdsikerij':   return WurdsikerijScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'patience':   return PatienceScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'lofthockey':   return LofthockeyScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'ienentritich': return IenEnTritichScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'tikrazernij':   return TikRazernijScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    case 'fluchtekenje':  return FluchTekenjeScreen(players: players, firstPlayer: firstPlayer, extra: extra);
    default:
      assert(false, 'Unknown game id: $game');
      return BoppeslachScreen(players: players, firstPlayer: firstPlayer);
  }
}
