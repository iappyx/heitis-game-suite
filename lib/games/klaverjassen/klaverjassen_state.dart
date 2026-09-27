import 'dart:math' as math;

// ── Suits & Ranks ─────────────────────────────────────────────────────────────

enum KSuit { hearts, diamonds, clubs, spades }

extension KSuitExt on KSuit {
  String get symbol => switch (this) {
    KSuit.hearts   => '♥',
    KSuit.diamonds => '♦',
    KSuit.clubs    => '♣',
    KSuit.spades   => '♠',
  };
  String get emoji => switch (this) {
    KSuit.hearts   => '❤️',
    KSuit.diamonds => '♦️',
    KSuit.clubs    => '♣️',
    KSuit.spades   => '♠️',
  };
  bool get isRed => this == KSuit.hearts || this == KSuit.diamonds;
  int get index  => KSuit.values.indexOf(this);
}

enum KRank { seven, eight, nine, ten, jack, queen, king, ace }

extension KRankExt on KRank {
  String get label => switch (this) {
    KRank.seven => '7', KRank.eight  => '8', KRank.nine  => '9',
    KRank.ten   => '10', KRank.jack  => 'J', KRank.queen => 'V',
    KRank.king  => 'H', KRank.ace   => 'A',
  };

  // Points when NOT trump
  int get normalPoints => switch (this) {
    KRank.ace   => 11,
    KRank.ten   => 10,
    KRank.king  => 4,
    KRank.queen => 3,
    KRank.jack  => 2,
    _           => 0,
  };

  // Points when trump
  int get trumpPoints => switch (this) {
    KRank.jack  => 20,
    KRank.nine  => 14,
    KRank.ace   => 11,
    KRank.ten   => 10,
    KRank.king  => 4,
    KRank.queen => 3,
    _           => 0,
  };

  // Rank order when NOT trump (higher = stronger); ace highest
  int get normalOrder => switch (this) {
    KRank.ace   => 7, KRank.ten  => 6, KRank.king  => 5, KRank.queen => 4,
    KRank.jack  => 3, KRank.nine => 2, KRank.eight => 1, KRank.seven => 0,
  };

  // Rank order when trump; J=highest, 9=second
  int get trumpOrder => switch (this) {
    KRank.jack  => 7, KRank.nine  => 6, KRank.ace   => 5, KRank.ten   => 4,
    KRank.king  => 3, KRank.queen => 2, KRank.eight => 1, KRank.seven => 0,
  };
}

// ── Card ──────────────────────────────────────────────────────────────────────

class KCard {
  final KSuit suit;
  final KRank rank;
  const KCard(this.suit, this.rank);

  bool isTrump(KSuit trump) => suit == trump;

  int points(KSuit trump) => isTrump(trump) ? rank.trumpPoints : rank.normalPoints;

  int order(KSuit trump) => isTrump(trump) ? rank.trumpOrder : rank.normalOrder;

  int encode() => suit.index * 8 + rank.index;

  factory KCard.decode(int v) => KCard(KSuit.values[v ~/ 8], KRank.values[v % 8]);

  @override bool operator ==(Object other) => other is KCard && suit == other.suit && rank == other.rank;
  @override int get hashCode => encode();
  @override String toString() => '${rank.label}${suit.symbol}';
}

// Full 32-card deck
List<KCard> kDeck() {
  final cards = <KCard>[];
  for (final s in KSuit.values) {
    for (final r in KRank.values) {
      cards.add(KCard(s, r));
    }
  }
  return cards;
}

// ── Roem (bonus points) ───────────────────────────────────────────────────────

class RoemResult {
  final int points;
  final String desc; // human-readable
  const RoemResult(this.points, this.desc);
}

// Calculate roem for the cards in a trick (played by one team)
List<RoemResult> calcRoem(List<KCard> trickCards, KSuit trump) {
  final results = <RoemResult>[];

  // Stuk: K + Q of trump = 20
  final hasKingTrump  = trickCards.any((c) => c.suit == trump && c.rank == KRank.king);
  final hasQueenTrump = trickCards.any((c) => c.suit == trump && c.rank == KRank.queen);
  if (hasKingTrump && hasQueenTrump) results.add(const RoemResult(20, 'Stuk'));

  // Sequences within the trick (need cards from same player's hand — simplified: all cards on table)
  // Group by suit
  for (final suit in KSuit.values) {
    final suitCards = trickCards.where((c) => c.suit == suit).toList();
    if (suitCards.length < 3) continue;
    // Sort by normal order
    suitCards.sort((a, b) => a.rank.index.compareTo(b.rank.index));
    // Find sequences
    for (int start = 0; start < suitCards.length; start++) {
      int len = 1;
      while (start + len < suitCards.length &&
             suitCards[start + len].rank.index ==
                 suitCards[start + len - 1].rank.index + 1) {
        len++;
      }
      if (len >= 3) {
        final pts = len == 3 ? 20 : len == 4 ? 50 : 70;
        // Check for H+V (king+queen) bonus in sequence
        results.add(RoemResult(pts, '$len-seq ${suit.symbol}'));
        start += len - 1; // skip past this sequence to avoid counting sub-sequences
      }
    }
  }

  // Four of a kind (7 through Ace, each = 100; four Jacks = 200)
  for (final rank in KRank.values) {
    if (trickCards.where((c) => c.rank == rank).length == 4) {
      final pts = rank == KRank.jack ? 200 : 100;
      results.add(RoemResult(pts, 'Vier ${rank.label}\'s'));
    }
  }

  return results;
}

// ── Game state ─────────────────────────────────────────────────────────────────

class KlaverjasState {
  final List<List<KCard>> hands; // 4 players
  List<KCard?> currentTrick;    // 4 cards (null = not played yet)
  int trickLeader;               // who leads current trick
  KSuit trump;
  int bidder;                    // who said 'play' this round
  int tricksPlayed;
  final List<int> teamPoints;   // [team0 pts, team1 pts]
  final List<int> teamRoem;     // [team0 roem, team1 roem]
  final List<int> matchScore;   // cumulative across rounds
  int totalRounds;

  KlaverjasState({
    required this.hands,
    required this.trump,
    required this.bidder,
    required this.trickLeader,
    this.tricksPlayed = 0,
    List<int>? teamPoints,
    List<int>? teamRoem,
    List<int>? matchScore,
    this.totalRounds = 0,
  }) : currentTrick = List.filled(4, null),
       teamPoints   = teamPoints ?? [0, 0],
       teamRoem     = teamRoem   ?? [0, 0],
       matchScore   = matchScore ?? [0, 0];

  // Player i is on team i%2 (0 and 2 are team 0; 1 and 3 are team 1)
  int teamOf(int player) => player % 2;

  bool get roundOver => tricksPlayed == 8;

  // Legal cards for a player to play, given current trick
  List<KCard> legalCards(int playerIdx) {
    final hand  = hands[playerIdx];
    final played = currentTrick.whereType<KCard>().toList();

    if (played.isEmpty) return List.from(hand); // first to play: anything

    final ledSuit   = currentTrick[trickLeader]!.suit;
    final sameSuit  = hand.where((c) => c.suit == ledSuit).toList();
    final trumpCards = hand.where((c) => c.isTrump(trump)).toList();

    // Can follow suit
    if (sameSuit.isNotEmpty) {
      // If trump was led, must try to overtrump (Rotterdams: always overtrump if possible)
      if (ledSuit == trump) {
        final highestTrumpPlayed = played
            .where((c) => c.isTrump(trump))
            .map((c) => c.rank.trumpOrder)
            .fold(-1, math.max);
        final overtrumpers = sameSuit.where((c) => c.rank.trumpOrder > highestTrumpPlayed).toList();
        if (overtrumpers.isNotEmpty) return overtrumpers; // must overtrump
      }
      return sameSuit; // follow suit
    }

    // Cannot follow suit — must trump (Rotterdams variant: always must trump if able)
    if (trumpCards.isNotEmpty) {
      // Must overtrump if possible
      final highestTrumpInTrick = played
          .where((c) => c.isTrump(trump))
          .map((c) => c.rank.trumpOrder)
          .fold(-1, math.max);
      if (highestTrumpInTrick >= 0) {
        final over = trumpCards.where((c) => c.rank.trumpOrder > highestTrumpInTrick).toList();
        if (over.isNotEmpty) return over;
        // Cannot overtrump — may undertrump
        return trumpCards;
      }
      return trumpCards; // no trump played yet — introeven
    }

    // No suit and no trump — play anything
    return List.from(hand);
  }

  // Who wins the current trick?
  int trickWinner() {
    final ledSuit = currentTrick[trickLeader]!.suit;
    int best = trickLeader;
    KCard bestCard = currentTrick[trickLeader]!;
    for (int i = 0; i < 4; i++) {
      final c = currentTrick[i];
      if (c == null) continue;
      if (_beats(c, bestCard, ledSuit)) {
        best     = i;
        bestCard = c;
      }
    }
    return best;
  }

  bool _beats(KCard challenger, KCard current, KSuit ledSuit) {
    final cTrump = challenger.isTrump(trump);
    final eTrump = current.isTrump(trump);
    if (cTrump && !eTrump)  return true;
    if (!cTrump && eTrump)  return false;
    if (cTrump && eTrump)   return challenger.rank.trumpOrder > current.rank.trumpOrder;
    // Neither trump
    if (challenger.suit != ledSuit) return false;
    if (current.suit != ledSuit)    return true;
    return challenger.rank.normalOrder > current.rank.normalOrder;
  }
}

// ── Bid decision ──────────────────────────────────────────────────────────────

bool shouldBid(List<KCard> hand, KSuit proposedTrump) {
  // Estimate expected points with this trump
  int estimate = 0;
  for (final c in hand) {
    estimate += c.points(proposedTrump);
  }
  // Also count strong trump cards
  final trumps = hand.where((c) => c.suit == proposedTrump).toList();
  final hasJack  = trumps.any((c) => c.rank == KRank.jack);
  final hasNel   = trumps.any((c) => c.rank == KRank.nine);

  if (hasJack && hasNel)  estimate += 20;
  if (hasJack)            estimate += 10;
  if (trumps.length >= 3) estimate += 8;

  // Bid if we estimate > 82 / 2 + 1 = 42 pts from our hand alone
  return estimate >= 35;
}

// ── CPU AI ────────────────────────────────────────────────────────────────────

class KlaverjasAI {
  final int playerIdx;

  KlaverjasAI(this.playerIdx);

  KCard chooseCard(KlaverjasState state) {
    final legal = state.legalCards(playerIdx);
    if (legal.length == 1) return legal.first;

    final played   = state.currentTrick.whereType<KCard>().toList();
    final teamMate = (playerIdx + 2) % 4;

    // If partner is currently winning the trick, play lowest safe card
    if (played.isNotEmpty) {
      final winner = _currentWinner(state, played);
      if (winner == teamMate) {
        // Partner winning — play lowest points
        return _lowestPoints(legal, state.trump);
      }
    }

    // Otherwise play highest to win
    return _highestStrength(legal, state.trump);
  }

  int _currentWinner(KlaverjasState state, List<KCard> played) {
    final ledSuit = state.currentTrick[state.trickLeader]!.suit;
    int best = state.trickLeader;
    KCard bestCard = state.currentTrick[state.trickLeader]!;
    for (int i = 0; i < 4; i++) {
      final c = state.currentTrick[i];
      if (c == null || i == state.trickLeader) continue;
      if (_beats(c, bestCard, ledSuit, state.trump)) {
        best = i; bestCard = c;
      }
    }
    return best;
  }

  bool _beats(KCard a, KCard b, KSuit led, KSuit trump) {
    final aT = a.suit == trump, bT = b.suit == trump;
    if (aT && !bT) return true;
    if (!aT && bT) return false;
    if (aT)        return a.rank.trumpOrder > b.rank.trumpOrder;
    if (a.suit != led) return false;
    if (b.suit != led) return true;
    return a.rank.normalOrder > b.rank.normalOrder;
  }

  KCard _lowestPoints(List<KCard> cards, KSuit trump) {
    return cards.reduce((a, b) => a.points(trump) <= b.points(trump) ? a : b);
  }

  KCard _highestStrength(List<KCard> cards, KSuit trump) {
    return cards.reduce((a, b) => a.order(trump) >= b.order(trump) ? a : b);
  }

  bool decideBid(List<KCard> hand, KSuit proposedTrump) => shouldBid(hand, proposedTrump);
}
