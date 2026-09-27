import '../../core/solo_ai.dart';

class ButerBreaEnGrieneTsiisAI extends SoloAI {
  ButerBreaEnGrieneTsiisAI(super.difficulty);

  /// board: List<int> 0=empty 1=host 2=joiner; aiPiece = 2
  void takeTurn(List<int> board) {
    scheduleMove(() {
      final move = _pickMove(board, 2);
      if (move == -1) return;
      net.injectMessage('BUT_MOVE', {'i': move, 'piece': 2});
    });
  }

  int _pickMove(List<int> board, int piece) {
    final empties = [for (int i = 0; i < 9; i++) if (board[i] == 0) i];
    if (empties.isEmpty) return -1;

    switch (difficulty) {
      case SoloDifficulty.easy:
        // 70% random, 30% play winning/blocking move
        if (rng.nextDouble() < 0.7) return empties[rng.nextInt(empties.length)];
        return _bestMove(board, piece, depth: 1);
      case SoloDifficulty.medium:
        // Play winning move if available, else random
        return _bestMove(board, piece, depth: 2);
      case SoloDifficulty.hard:
        return _minimax(board, piece, true).move;
    }
  }

  int _bestMove(List<int> board, int piece, {required int depth}) {
    // Check immediate win
    for (int i = 0; i < 9; i++) {
      if (board[i] != 0) continue;
      board[i] = piece;
      if (_winner(board) == piece) { board[i] = 0; return i; }
      board[i] = 0;
    }
    if (depth >= 2) {
      // Block opponent win
      final opp = piece == 1 ? 2 : 1;
      for (int i = 0; i < 9; i++) {
        if (board[i] != 0) continue;
        board[i] = opp;
        if (_winner(board) == opp) { board[i] = 0; return i; }
        board[i] = 0;
      }
    }
    final empties = [for (int i = 0; i < 9; i++) if (board[i] == 0) i];
    return empties.isEmpty ? -1 : empties[rng.nextInt(empties.length)];
  }

  ({int move, int score}) _minimax(List<int> board, int piece, bool maximising) {
    final w = _winner(board);
    if (w == 2) return (move: -1, score: 10);
    if (w == 1) return (move: -1, score: -10);
    final empties = [for (int i = 0; i < 9; i++) if (board[i] == 0) i];
    if (empties.isEmpty) return (move: -1, score: 0);

    int best = maximising ? -100 : 100;
    int bestMove = empties[0];
    for (final i in empties) {
      board[i] = maximising ? 2 : 1;
      final score = _minimax(board, piece, !maximising).score;
      board[i] = 0;
      if (maximising ? score > best : score < best) { best = score; bestMove = i; }
    }
    return (move: bestMove, score: best);
  }

  int _winner(List<int> board) {
    const lines = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
    for (final l in lines) {
      if (board[l[0]] != 0 && board[l[0]] == board[l[1]] && board[l[1]] == board[l[2]])
        return board[l[0]];
    }
    return 0;
  }
}
