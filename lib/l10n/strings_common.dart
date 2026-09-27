import 'app_localizations.dart';

class StringsCommon {
  // ── App / Lobby ───────────────────────────────────────────────────────────
  final String appTagline;
  final String yourName;
  final String hostBtn;
  final String joinBtn;
  final String cancelBtn;
  final String waitingForPlayers;  // "Waiting for players… (up to 4)"
  final String waitingForPlayers1; // "Waiting for 1 player…"
  final String waitingForHost;     // "Waiting for host to start…"
  final String searchingForHost;
  final String foundHost;          // "Found host — tap to connect:"
  final String connecting;
  final String connectedWaiting;   // "Connected! Waiting for host…"
  final String hostDisconnected;
  final String noHostsFound;
  final String couldNotConnect;
  final String startGame;          // "Start Game!"
  final String startN;             // "Start ({n} players)"  — use .fmt({'n':n})
  final String chooseGame;
  final String nextGameFirst;      // "Next game: {player} goes first"
  final String twoPlayersOnly;
  final String choosePhoto;
  final String takeSelfie;
  final String chooseFromGallery;
  final String cropPhoto;
  final String dragPinch;
  final String useThis;
  final String connectTo;        // 'Connect to {ip}'
  final String pickColour;

  // ── Waiting screen ────────────────────────────────────────────────────────
  final String playersConnected;   // "{n} player(s) connected!"
  final String hostPicked;         // "Host picked: {icon} {name}"
  final String waitingForHostStart;

  // ── Chat ──────────────────────────────────────────────────────────────────
  final String chatTitle;
  final String chatHint;
  final String isTyping;          // "{player} is typing…"

  // ── Game scaffold ─────────────────────────────────────────────────────────
  final String leaveGame;
  final String leaveGameContent;
  final String stay;
  final String gameSelect;
  final String lobby;
  final String leaving;

  // ── Game over / result ────────────────────────────────────────────────────
  final String itsADraw;
  final String wins;               // "{player} wins!" — use .fmt({'player': name})
  final String playAgain;

  // ── Reconnect dialog ──────────────────────────────────────────────────────
  final String reconnecting;
  final String waitingForReconnect;
  final String playerReconnected;
  final String playerDisconnectedAgain;
  final String couldNotRestart;    // "Could not restart: {err}"
  final String foundHostConnecting;
  final String rejoinConnected;    // "Connected! Rejoining…"
  final String connectionFailed;
  final String lostConnection;
  final String discoveryError;     // "Discovery error: {err}"
  final String timedOut;
  final String bothSameWifi;
  final String attempt;            // "Attempt {n}"
  final String retryNow;
  final String exitToLobby;

  // ── Snackbars ─────────────────────────────────────────────────────────────
  final String playerLeft;         // "{player} left — back to game select"
  final String playerLeftGame;     // "{player} left the game"
  final String playerLeftReturning; // "{player} left — returning to game select"
  final String hostLeft; // host went back to the start screen
  // About screen
  final String about;
  final String aboutMadeBy;
  final String aboutLicense;
  final String aboutCredits;
  final String aboutFont;
  final String aboutSounds;
  final String aboutPackages;
  final String aboutAllLicenses;
  final String aboutClose;
  // Connection help (which transport works when)
  final String connHelpTitle;
  final String connNeeds;
  final String connWorksWith;
  final String connFailsWhen;
  final String connWifiNeeds;
  final String connWifiWorks;
  final String connWifiFails;
  final String connBtNeeds;
  final String connBtWorks;
  final String connBtFails;
  final String connNearbyNeeds;
  final String connNearbyWorks;
  final String connNearbyFails;
  final String connGuideTitle;
  final String connGuideHome;
  final String connGuideRoad;
  final String connGuideMixed;
  final String connGuideApple;
  final String connAppleNoBt;
  final String connSameForAll;
  final String tabSubWifi;
  final String tabSubBluetooth;
  final String tabSubNearbyAndroid;
  final String tabSubNearbyApple;
  final String nearbyHint;
  // Hosted mode (browser players)
  final String webInviteTitle;
  final String webInviteHint;
  final String webInviteBtn;
  final String webCodeLabel;
  final String webCodeHint;
  final String webCodeWrong;
  final String connWebTitle;
  final String connWebNeeds;
  final String connWebWorks;
  final String connWebFails;
  final String connGuideFriends;
  final String playerAway;
  final String playerBack;
  final String playerWentSelect;   // "{player} went to Game Select"

  // ── Hotspot toggle ────────────────────────────────────────────────────────
  final String hotspotMode;
  final String hotspotHint;

  final String yourMove;          // "Your move"
  final String opponentTurn;      // "{player}'s turn…"
  final String yourTurnRoll;      // "Your turn — roll!"
  final String defaultPlayer;     // fallback name "Player"
  final String usingHotspot;      // "Using hotspot?"
  final String profiles;          // "X profiles"
  final String manageProfiles;    // "Manage Profiles"
  final String newProfile;        // "+ New Profile"

  // ── Transport / Bluetooth ─────────────────────────────────────────────────
  final String transportWifi;       // "WiFi"
  final String transportBluetooth;  // "Bluetooth"
  final String transportNearby;     // "Nearby"
  final String btSearching;         // "Searching for nearby devices…"
  final String btFoundHost;         // "Found host — tap to connect:"
  final String btConnectTo;         // "Connect to {name}"
  final String btPermissionTitle;   // "Bluetooth permission needed"
  final String btPermissionBody;    // explanation text
  final String btPermissionBtn;     // "Open Settings"
  final String btNotSupported;      // "Bluetooth not available on this device"
  final String draw;              // "Draw!"
  final String you;               // "You" — chat sender label
  final String winsLabel;         // " wins" — score suffix
  final String boxesLabel;        // " boxes" — score suffix
  final String pairsLabel;        // " pairs" — score suffix
  final String hue;               // colour slider label
  final String sat;               // colour slider label
  final String bri;               // colour slider label

  // ── Solo / AI ─────────────────────────────────────────────────────────────
  final String soloBtn;           // "Play Solo"
  final String soloTitle;         // "Solo Game"
  final String soloChooseGame;    // "Choose a game"
  final String soloDifficulty;    // "Difficulty"
  final String soloEasy;          // "Easy"
  final String soloMedium;        // "Medium"
  final String soloHard;          // "Hard"
  final String soloPlay;          // "Play!"
  final String soloComputerName;  // "Kompjûter" / "Computer" etc.
  final String soloOpponents;     // "Opponents"
  final String addComputers;     // "Add computer players?"
  final String humanPlayers;     // "human players"
  final String noComputers;      // "No computers"
  final String computer;         // "computer" (singular)
  final String computers;        // "computers" (plural)
  final String statsTitle;        // "Statistics"
  final String statsGame;         // "Game"
  final String statsWin;          // "W"
  final String statsLoss;         // "L"
  final String statsDraw;         // "D"
  final String statsPlayed;       // "GP"
  final String statsTotal;        // "Total"
  final String statsEmpty;        // "No stats yet — play some games!"
  final String statsClearTitle;   // "Clear all stats?"
  final String statsClearBody;    // "This will permanently delete all recorded results."
  final String statsClearConfirm; // "Clear"
  // Help / rules
  final String helpTitle;          // "How to play"
  final String helpClose;          // "Close"
  // Kleur-echo endurance
  final String kleurEchoEndurance;     // "Endurance" (solo mode label)
  final String kleurEchoBestScore;     // "Best: {n}"
  final String kleurEchoGameOver;      // "Game Over"
  final String kleurEchoScore;         // "Score: {n}"
  // ── Tournament ──────────────────────────────────────────────────────────
  final String tournament;          // "Tournament"
  final String tournamentMode;      // "Tournament Mode"
  final String tournamentResults;   // "Tournament Results"
  final String startTournament;     // "Start Tournament"
  final String numberOfRounds;      // "Number of rounds"
  final String abortTournament;     // "Abort tournament?"
  final String abort;               // "Abort"
  final String whoWon;              // "Who won?"
  final String backToLobby;         // "Back to Lobby"
  final String playAgainBtn;        // "Play Again"

  // ── Game browse / Stats ────────────────────────────────────────────────
  final String allFilter;           // "All" — browse filter
  final String browseTitle;         // "Browse" — browse screen title
  final String gamesPlayed;         // "games played"
  final String winRate;             // "win rate"
  final String favourite;           // "favourite"

  // ── Tournament results ─────────────────────────────────────────────────
  final String winsTheTournament;   // "wins the tournament!"
  final String takesTheLead;        // "takes the lead!"
  final String finalScore;          // "Final score: {n} {wins}"
  final String finalStandings;      // "FINAL STANDINGS"
  final String noWins;              // "No wins"
  final String roundByRound;        // "ROUND-BY-ROUND"
  final String standings;           // "STANDINGS"
  final String rounds;              // "ROUNDS"
  final String playBtn;             // "Play"
  final String nWins;               // "{n} win(s)" — e.g. "3 wins"
  final String goesFirst;           // "{player} goes first"

  // ── Tournament / game-over actions ──────────────────────────────────────
  final String recordResult;        // "Record Result"
  final String waitingForHostResult; // "Waiting for host…"
  final String roundNofM;           // "Round {n}/{m}"
  final String nPoints;             // "{n} pts"
  final String nRounds;             // "{n} rounds"

  // ── Game browse categories ──────────────────────────────────────────────
  final String catStrategy;         // "Strategy"
  final String catWord;             // "Word"
  final String catArcade;           // "Arcade"
  final String catPuzzle;           // "Puzzle"
  final String catClassic;          // "Classic"
  final String catCard;             // "Card"

  // ── Player restrictions ─────────────────────────────────────────────────
  final String singlePlayerOnly;    // "Solo only"

  // ── Transport-specific error hints ────────────────────────────────────
  final String wifiHint;            // shown when WiFi discovery/connect fails
  final String bluetoothHint;       // shown when Bluetooth discovery/connect fails
  final String connectionLostHint;  // "Check that both devices are nearby and try again"
  final String noHostFound;         // "No host found. Is the other device hosting a game?"
  final String turnOnWifi;          // "Turn on WiFi to connect"
  final String turnOnBluetooth;     // "Turn on Bluetooth to connect"

  // ── Kid-friendly exit labels ────────────────────────────────────────────
  final String pickNewGame;         // "Pick a new game"
  final String backToStart;         // "Back to start"

  // ── Tooltips ───────────────────────────────────────────────────────────
  final String muteTooltip;           // "Mute"
  final String unmuteTooltip;         // "Unmute"
  final String chatTooltip;           // "Chat"

  // ── Onboarding ──────────────────────────────────────────────────────────
  final String obWelcome;           // "Welcome to Heiti's Game Suite!"
  final String obSubtitle;          // "A collection of fun games…"
  final String obHost;              // "Start a game and invite friends nearby"
  final String obJoin;              // "Join a friend's game"
  final String obSolo;              // "Play alone against the computer"
  final String obReady;             // "Ready to play?"
  final String obLetsGo;            // "Let's go!"
  final String obSkip;              // "Skip"

  const StringsCommon({
    required this.appTagline,
    required this.yourName,
    required this.hostBtn,
    required this.joinBtn,
    required this.cancelBtn,
    required this.waitingForPlayers,
    required this.waitingForPlayers1,
    required this.waitingForHost,
    required this.searchingForHost,
    required this.foundHost,
    required this.connecting,
    required this.connectedWaiting,
    required this.hostDisconnected,
    required this.noHostsFound,
    required this.couldNotConnect,
    required this.startGame,
    required this.startN,
    required this.chooseGame,
    required this.nextGameFirst,
    required this.twoPlayersOnly,
    required this.choosePhoto,
    required this.takeSelfie,
    required this.chooseFromGallery,
    required this.cropPhoto,
    required this.dragPinch,
    required this.useThis,
    required this.connectTo,
    required this.pickColour,
    required this.playersConnected,
    required this.hostPicked,
    required this.waitingForHostStart,
    required this.chatTitle,
    required this.chatHint,
    required this.isTyping,
    required this.leaveGame,
    required this.leaveGameContent,
    required this.stay,
    required this.gameSelect,
    required this.lobby,
    required this.leaving,
    required this.itsADraw,
    required this.wins,
    required this.playAgain,
    required this.reconnecting,
    required this.waitingForReconnect,
    required this.playerReconnected,
    required this.playerDisconnectedAgain,
    required this.couldNotRestart,
    required this.foundHostConnecting,
    required this.rejoinConnected,
    required this.connectionFailed,
    required this.lostConnection,
    required this.discoveryError,
    required this.timedOut,
    required this.bothSameWifi,
    required this.attempt,
    required this.retryNow,
    required this.exitToLobby,
    required this.playerLeft,
    required this.playerLeftGame,
    required this.playerLeftReturning,
    required this.hostLeft,
    required this.about,
    required this.aboutMadeBy,
    required this.aboutLicense,
    required this.aboutCredits,
    required this.aboutFont,
    required this.aboutSounds,
    required this.aboutPackages,
    required this.aboutAllLicenses,
    required this.aboutClose,
    required this.connHelpTitle,
    required this.connNeeds,
    required this.connWorksWith,
    required this.connFailsWhen,
    required this.connWifiNeeds,
    required this.connWifiWorks,
    required this.connWifiFails,
    required this.connBtNeeds,
    required this.connBtWorks,
    required this.connBtFails,
    required this.connNearbyNeeds,
    required this.connNearbyWorks,
    required this.connNearbyFails,
    required this.connGuideTitle,
    required this.connGuideHome,
    required this.connGuideRoad,
    required this.connGuideMixed,
    required this.connGuideApple,
    required this.connAppleNoBt,
    required this.connSameForAll,
    required this.tabSubWifi,
    required this.tabSubBluetooth,
    required this.tabSubNearbyAndroid,
    required this.tabSubNearbyApple,
    required this.nearbyHint,
    required this.webInviteTitle,
    required this.webInviteHint,
    required this.webInviteBtn,
    required this.webCodeLabel,
    required this.webCodeHint,
    required this.webCodeWrong,
    required this.connWebTitle,
    required this.connWebNeeds,
    required this.connWebWorks,
    required this.connWebFails,
    required this.connGuideFriends,
    required this.playerAway,
    required this.playerBack,
    required this.playerWentSelect,
    required this.hotspotMode,
    required this.hotspotHint,
    required this.yourMove,
    required this.opponentTurn,
    required this.yourTurnRoll,
    required this.defaultPlayer,
    required this.usingHotspot,
    required this.profiles,
    required this.manageProfiles,
    required this.newProfile,
    required this.transportWifi,
    required this.transportBluetooth,
    required this.transportNearby,
    required this.btSearching,
    required this.btFoundHost,
    required this.btConnectTo,
    required this.btPermissionTitle,
    required this.btPermissionBody,
    required this.btPermissionBtn,
    required this.btNotSupported,
    required this.draw,
    required this.you,
    required this.winsLabel,
    required this.boxesLabel,
    required this.pairsLabel,
    required this.hue,
    required this.sat,
    required this.bri,
    required this.soloBtn,
    required this.soloTitle,
    required this.soloChooseGame,
    required this.soloDifficulty,
    required this.soloEasy,
    required this.soloMedium,
    required this.soloHard,
    required this.soloPlay,
    required this.soloComputerName,
    required this.soloOpponents,
    required this.addComputers,
    required this.humanPlayers,
    required this.noComputers,
    required this.computer,
    required this.computers,
    required this.statsTitle,
    required this.statsGame,
    required this.statsWin,
    required this.statsLoss,
    required this.statsDraw,
    required this.statsPlayed,
    required this.statsTotal,
    required this.statsEmpty,
    required this.statsClearTitle,
    required this.statsClearBody,
    required this.statsClearConfirm,
    required this.helpTitle,
    required this.helpClose,
    required this.kleurEchoEndurance,
    required this.kleurEchoBestScore,
    required this.kleurEchoGameOver,
    required this.kleurEchoScore,
    required this.tournament,
    required this.tournamentMode,
    required this.tournamentResults,
    required this.startTournament,
    required this.numberOfRounds,
    required this.abortTournament,
    required this.abort,
    required this.whoWon,
    required this.backToLobby,
    required this.playAgainBtn,
    required this.allFilter,
    required this.browseTitle,
    required this.gamesPlayed,
    required this.winRate,
    required this.favourite,
    required this.winsTheTournament,
    required this.takesTheLead,
    required this.finalScore,
    required this.finalStandings,
    required this.noWins,
    required this.roundByRound,
    required this.standings,
    required this.rounds,
    required this.playBtn,
    required this.nWins,
    required this.goesFirst,
    required this.recordResult,
    required this.waitingForHostResult,
    required this.roundNofM,
    required this.nPoints,
    required this.nRounds,
    required this.catStrategy,
    required this.catWord,
    required this.catArcade,
    required this.catPuzzle,
    required this.catClassic,
    required this.catCard,
    required this.singlePlayerOnly,
    required this.wifiHint,
    required this.bluetoothHint,
    required this.connectionLostHint,
    required this.noHostFound,
    required this.turnOnWifi,
    required this.turnOnBluetooth,
    required this.pickNewGame,
    required this.backToStart,
    required this.muteTooltip,
    required this.unmuteTooltip,
    required this.chatTooltip,
    required this.obWelcome,
    required this.obSubtitle,
    required this.obHost,
    required this.obJoin,
    required this.obSolo,
    required this.obReady,
    required this.obLetsGo,
    required this.obSkip,
  });

  factory StringsCommon.of(AppLang l) => switch (l) {
    AppLang.fy => StringsCommon.fy(),
    AppLang.nl => StringsCommon.nl(),
    AppLang.en => StringsCommon.en(),
  };

  factory StringsCommon.fy() => const StringsCommon(
    appTagline:              'Spylje tegearre — gjin ynternet nedich',
    yourName:                'Dyn namme…',
    hostBtn:                 'Host',
    joinBtn:                 'Meidwaan',
    cancelBtn:               '✕ Ôfbrekke',
    waitingForPlayers:       'Wachtsje op spilers… (oant 4)',
    waitingForPlayers1:      'Wachtsje op 1 spiler…',
    waitingForHost:          'Wachtsje op de host om te begjinnen…',
    searchingForHost:        'Sykje nei host…',
    foundHost:               'Host fûn — tikje om te ferbinen:',
    connecting:              'Ferbinen…',
    connectedWaiting:        'Ferbûn! Wachtsje op host…',
    hostDisconnected:        'Host ûntbûn. Probearje nochris.',
    noHostsFound:            'Gjin host fûn. Soargje dat beide op itselde WiFi sitte.',
    couldNotConnect:         'Koe net ferbine: {err}',
    startGame:               'Begjin Spultsje!',
    startN:                  'Begjin ({n} spilers)',
    chooseGame:              'Kies in spultsje',
    nextGameFirst:           'Folgjend spultsje: {player} begjint',
    twoPlayersOnly:          'Allinnich 2 spilers',
    choosePhoto:             'Foto kieze',
    takeSelfie:              'Selfie meitsje',
    chooseFromGallery:       'Út galery kieze',
    cropPhoto:               "Foto bysnij'e",
    dragPinch:               'Sleep & knip om te posysjonearjen',
    useThis:                 'Dit brûke',
    connectTo:               'Ferbine mei {ip}',
    pickColour:              'In kleur kieze',
    playersConnected:        '{n} spiler(s) ferbûn!',
    hostPicked:              'Host keas: {icon} {name}',
    waitingForHostStart:     'Wachtsje op host om te starten…',
    chatTitle:               'Prate',
    chatHint:                'Berjocht…',
    isTyping:                '{player} typt…',
    leaveGame:               'Spultsje ferlitte?',
    leaveGameContent:        "Kies wêr't jo hinne wolle:",
    stay:                    'Bliuwe',
    gameSelect:              'Spultsje kieze',
    lobby:                   'Lobby',
    leaving:                 'Fuortgean…',
    itsADraw:                "It is in Lykspul!",
    wins:                    '{player} wint!',
    playAgain:               'Nochris spylje',
    reconnecting:            'Opnij ferbinen…',
    waitingForReconnect:     'Wachtsje op oaren om opnij te ferbinen…',
    playerReconnected:       'Spiler opnij ferbûn!',
    playerDisconnectedAgain: 'Spiler wer ûntbûn.',
    couldNotRestart:         'Koe net opnij starte: {err}',
    foundHostConnecting:     'Host fûn, ferbinen…',
    rejoinConnected:         'Ferbûn! Weromgean…',
    connectionFailed:        'Ferbiningsflater.',
    lostConnection:          'Ferbining wer kwyt.',
    discoveryError:          'Ûntdekkingsflater: {err}',
    timedOut:                'Koe it oare tablet net fine.\nSoargje dat beide op itselde WiFi sitte.',
    bothSameWifi:            'Beide tablets moatte op itselde WiFi of hotspot sitte.',
    attempt:                 'Besykje {n}',
    retryNow:                'No nochris besykje',
    exitToLobby:             'Nei de Lobby',
    playerLeft:              '{player} fuortgien — werom nei spultsje kieze',
    playerLeftGame:          '{player} hat it spultsje ferlitten',
    playerLeftReturning:     '{player} fuortgien — werom nei spultsje kieze',
    hostLeft:                'De host is fuortgien — werom nei it begjinskerm',
    about:                   'Oer dizze app',
    aboutMadeBy:             'Makke troch iappyx',
    aboutLicense:            'Iepen boarne ûnder de MIT-lisinsje.',
    aboutCredits:            'Mei tank oan',
    aboutFont:               'Emoji: Noto Color Emoji — © Google, SIL Open Font License 1.1',
    aboutSounds:             'Lûdseffekten: Kenney (kenney.nl) — publyk domein (CC0)',
    aboutPackages:           'Boud mei Flutter, Roboto en iepenboarne-pakketten',
    aboutAllLicenses:        'Alle lisinsjes',
    aboutClose:              'Slute',
    connHelpTitle:           'Hokker ferbining?',
    connNeeds:               'Nedich',
    connWorksWith:           'Wurket mei',
    connFailsWhen:           'Wurket net as',
    connWifiNeeds:           'Itselde WiFi-netwurk, of de hotspot fan ien apparaat. Gjin ynternet nedich.',
    connWifiWorks:           'Elk apparaat: Android, Mac, iPhone en iPad — ek trochinoar.',
    connWifiFails:           'Gast- of iepenbiere WiFi dy\'t apparaten útinoar hâldt, of in router dy\'t it sykjen blokkearret. Brûk dan in hotspot.',
    connBtNeeds:             'Bluetooth oan en tastimming foar apparaten yn \'e buert. Gjin WiFi of router nedich.',
    connBtWorks:             'Android mei Android.',
    connBtFails:             'Der docht in Mac, iPhone of iPad mei, tastimming is wegere, of de apparaten binne te fier útinoar (sa\'n 10 m).',
    connNearbyNeeds:         'WiFi oanset (gjin netwurk nedich) en tastimming foar apparaten yn \'e buert.',
    connNearbyWorks:         'Android mei Android, of Apple mei Apple (Mac, iPhone, iPad).',
    connNearbyFails:         'Android- en Apple-apparaten trochinoar, WiFi stiet út, of tastimming is wegere.',
    connGuideTitle:          'Koartsein',
    connGuideHome:           'Thús: WiFi.',
    connGuideRoad:           'Ûnderweis, allinnich Android: Bluetooth of Nearby — beide wurkje prima.',
    connGuideMixed:          'Mac, iPhone of iPad tegearre mei Android: WiFi, of de hotspot fan in telefoan.',
    connGuideApple:          'Allinnich Apple-apparaten: Nearby of WiFi.',
    connAppleNoBt:           'Bluetooth-modus bestiet allinnich op Android. Spilest mei Android-apparaten, brûk dan WiFi.',
    connSameForAll:          'Elkenien moat deselde ferbining kieze.',
    tabSubWifi:              'Deselde WiFi of hotspot — wurket mei elk apparaat',
    tabSubBluetooth:         'Gjin WiFi nedich — allinnich Android',
    tabSubNearbyAndroid:     'Gjin router nedich — allinnich Android',
    tabSubNearbyApple:       'Gjin router nedich — allinnich Apple-apparaten',
    nearbyHint:              'Set WiFi oan op alle apparaten en jou tastimming. Wurket allinnich Android mei Android, of Apple mei Apple.',
    webInviteTitle:          'Spilers sûnder de app',
    webInviteHint:           'Scan mei de kamera fan in telefoan of tablet op deselde WiFi of hotspot. It spul iepenet yn \'e browser.',
    webInviteBtn:            'Browserspilers útnoegje',
    webCodeLabel:            'Koade',
    webCodeHint:             'Koade fan it skerm fan de host',
    webCodeWrong:            'Ferkearde koade — sjoch op it skerm fan de host',
    connWebTitle:            'Browser (sûnder app)',
    connWebNeeds:            'In host op it WiFi-ljepblêd en deselde WiFi of syn hotspot. Scan de QR-koade.',
    connWebWorks:            'Elk apparaat mei in browser (telefoan, tablet, kompjûter), ek tegearre mei app-spilers.',
    connWebFails:            'De host brûkt Bluetooth of Nearby, de koade is ferkeard, of gast-WiFi hâldt apparaten útinoar.',
    connGuideFriends:        'Freonen sûnder de app: host op WiFi, lit se de QR-koade scanne.',
    playerAway:              '{player} is fuort — wy wachtsje efkes oant dy weromkomt…',
    playerBack:              '{player} is werom',
    playerWentSelect:        '{player} gie nei Spultsje kieze',
    hotspotMode:             'Hotspot-modus',
    hotspotHint:             'Brûk dit as jo direkt ferbûn binne fia in hotspot',
    yourMove:                'Dyn beurt',
    opponentTurn:            '{player} is oan bar…',
    yourTurnRoll:            'Dyn beurt — goaie!',
    defaultPlayer:           'Spiler',
    usingHotspot:            'Hotspot brûke?',
    profiles:                'profilen',
    manageProfiles:          'Profilen beheare',
    newProfile:              'Nij profyl',
    transportWifi:           'WiFi',
    transportBluetooth:      'Bluetooth',
    transportNearby:         'Nearby (P2P)',
    btSearching:             'Sykje nei apparaten yn de buert…',
    btFoundHost:             'Host fûn — tikje om te ferbinen:',
    btConnectTo:             'Ferbine mei {name}',
    btPermissionTitle:       'Bluetooth-tastimming nedich',
    btPermissionBody:        'Dizze app hat Bluetooth en lokaasjetastimming nedich om apparaten yn de buert te finen. Gean nei Ynstellingen om dit yn te skeakeljen.',
    btPermissionBtn:         'Ynstellingen iepenje',
    btNotSupported:          'Bluetooth net beskikber op dit apparaat',
    draw:                    'Lykspul!',
    you:                     'Do',
    winsLabel:               ' wint',
    boxesLabel:              ' fakjes',
    pairsLabel:              ' paren',
    hue:                     'Tint',
    sat:                     'Kleur',
    bri:                     'Ljocht',
    soloBtn:                 'Allinne spylje',
    soloTitle:               'Solo Spultsje',
    soloChooseGame:          'Kies in spultsje',
    soloDifficulty:          'Swierrichheid',
    soloEasy:                'Maklik',
    soloMedium:              'Middelber',
    soloHard:                'Swier',
    soloPlay:                'Spylje!',
    soloComputerName:        'Kompjûter',
    soloOpponents:           'Tsjinstanners',
    addComputers:            'Kompjûterspilers tafoegje?',
    humanPlayers:            'spilers',
    noComputers:             'Gjin kompjûters',
    computer:                'kompjûter',
    computers:               'kompjûters',
    statsTitle:              'Statistiken',
    statsGame:               'Spultsje',
    statsWin:                'W',
    statsLoss:               'F',
    statsDraw:               'G',
    statsPlayed:             'GP',
    statsTotal:              'Totaal',
    statsEmpty:              'Noch gjin statistiken — spylje wat spultsjes!',
    statsClearTitle:         'Alle statistiken wiskje?',
    statsClearBody:          'Dit sil alle opnommen resultaten permanint fuortsmite.',
    statsClearConfirm:       'Wiskje',
    helpTitle:               'Hoe te spyljen',
    helpClose:               'Slute',
    kleurEchoEndurance:          'Úthâlding',
    kleurEchoBestScore:          'Bêste: {n}',
    kleurEchoGameOver:           'Spultsje oer',
    kleurEchoScore:              'Skoar: {n}',
    tournament:              'Toernoai',
    tournamentMode:          'Toernoai-modus',
    tournamentResults:       'Toernoai-resultaten',
    startTournament:         'Toernoai begjinne',
    numberOfRounds:          'Oantal rûnten',
    abortTournament:         'Toernoai ôfbrekke?',
    abort:                   'Ôfbrekke',
    whoWon:                  'Wa hat wûn?',
    backToLobby:             'Werom nei Lobby',
    playAgainBtn:            'Nochris spylje',
    allFilter:               'Alles',
    browseTitle:             'Blêdzje',
    gamesPlayed:             'spultsjes spile',
    winRate:                 'winstpersintaazje',
    favourite:               'favoryt',
    winsTheTournament:       'wint it toernoai!',
    takesTheLead:            'nimt de lieding!',
    finalScore:              'Einskoar: {n}',
    finalStandings:          'EINSTÂN',
    noWins:                  'Gjin winsten',
    roundByRound:            'PER RÛNTE',
    standings:               'STÂN',
    rounds:                  'RÛNTEN',
    playBtn:                 'Spylje',
    nWins:                   '{n} wûn',
    goesFirst:               '{player} begjint',
    recordResult:            'Resultaat fêstlizze',
    waitingForHostResult:    'Wachtsje op host…',
    roundNofM:               'Ronde {n}/{m}',
    nPoints:                 '{n} ptn',
    nRounds:                 '{n} rondes',
    catStrategy:             'Stratezjy',
    catWord:                 'Wurd',
    catArcade:               'Arcade',
    catPuzzle:               'Puzel',
    catClassic:              'Klassyk',
    catCard:                 'Kaart',
    singlePlayerOnly:        'Allinnich solo',
    wifiHint:                'Soargje dat alle apparaten op itselde WiFi-netwurk binne. Gast-WiFi of slagget it net? Brûk de hotspot fan ien apparaat.',
    bluetoothHint:           'Set Bluetooth oan op alle apparaten, jou tastimming en bliuw binnen sa\'n 10 m.',
    connectionLostHint:      'Kontrolearje dat beide apparaten tichtby binne en besykje it nochris',
    noHostFound:             'Gjin host fûn. Is it oare apparaat in spultsje oan it hosten?',
    turnOnWifi:              'Set WiFi oan om te ferbinen',
    turnOnBluetooth:         'Set Bluetooth oan om te ferbinen',
    pickNewGame:             'Oar spul',
    backToStart:             'Werom',
    muteTooltip:             'Lûd út',
    unmuteTooltip:           'Lûd oan',
    chatTooltip:             'Prate',
    obWelcome:               "Wolkom by Heiti's Game Suite!",
    obSubtitle:              'In samling fan leuke spultsjes foar mei freonen of allinnich',
    obHost:                  'Start in spultsje en nûgje freonen út',
    obJoin:                  'Doch mei oan it spultsje fan in freon',
    obSolo:                  'Spylje allinnich tsjin de kompjûter',
    obReady:                 'Klear om te spyljen?',
    obLetsGo:                'Wy gean los!',
    obSkip:                  'Oerslaan',
  );

  factory StringsCommon.nl() => const StringsCommon(
    appTagline:              'Speel samen — geen internet nodig',
    yourName:                'Jouw naam…',
    hostBtn:                 'Host',
    joinBtn:                 'Meedoen',
    cancelBtn:               '✕ Annuleren',
    waitingForPlayers:       'Wachten op spelers… (tot 4)',
    waitingForPlayers1:      'Wachten op 1 speler…',
    waitingForHost:          'Wachten op de host om te beginnen…',
    searchingForHost:        'Zoeken naar host…',
    foundHost:               'Host gevonden — tik om te verbinden:',
    connecting:              'Verbinden…',
    connectedWaiting:        'Verbonden! Wachten op host…',
    hostDisconnected:        'Host verbroken. Probeer opnieuw.',
    noHostsFound:            'Geen host gevonden. Zorg dat beide op hetzelfde WiFi zitten.',
    couldNotConnect:         'Kon niet verbinden: {err}',
    startGame:               'Start Spel!',
    startN:                  'Start ({n} spelers)',
    chooseGame:              'Kies een spel',
    nextGameFirst:           'Volgend spel: {player} begint',
    twoPlayersOnly:          'Alleen 2 spelers',
    choosePhoto:             'Foto kiezen',
    takeSelfie:              'Selfie maken',
    chooseFromGallery:       'Uit galerij kiezen',
    cropPhoto:               'Foto bijsnijden',
    dragPinch:               'Sleep & knijp om te positioneren',
    useThis:                 'Dit gebruiken',
    connectTo:               'Verbinden met {ip}',
    pickColour:              'Een kleur kiezen',
    playersConnected:        '{n} speler(s) verbonden!',
    hostPicked:              'Host koos: {icon} {name}',
    waitingForHostStart:     'Wachten op host om te starten…',
    chatTitle:               'Chat',
    chatHint:                'Bericht…',
    isTyping:                '{player} typt…',
    leaveGame:               'Spel verlaten?',
    leaveGameContent:        'Kies waar je naartoe wil:',
    stay:                    'Blijven',
    gameSelect:              'Spelkeuze',
    lobby:                   'Lobby',
    leaving:                 'Verlaten…',
    itsADraw:                'Gelijkspel!',
    wins:                    '{player} wint!',
    playAgain:               'Opnieuw spelen',
    reconnecting:            'Opnieuw verbinden…',
    waitingForReconnect:     'Wachten tot anderen opnieuw verbinden…',
    playerReconnected:       'Speler opnieuw verbonden!',
    playerDisconnectedAgain: 'Speler weer verbroken.',
    couldNotRestart:         'Kon niet opnieuw starten: {err}',
    foundHostConnecting:     'Host gevonden, verbinden…',
    rejoinConnected:         'Verbonden! Terugkeren…',
    connectionFailed:        'Verbinding mislukt.',
    lostConnection:          'Verbinding weer kwijt.',
    discoveryError:          'Zoekfout: {err}',
    timedOut:                'Kon het andere tablet niet vinden.\nZorg dat beide op hetzelfde WiFi zitten.',
    bothSameWifi:            'Beide tablets moeten op hetzelfde WiFi of hotspot zitten.',
    attempt:                 'Poging {n}',
    retryNow:                'Nu opnieuw proberen',
    exitToLobby:             'Naar de Lobby',
    playerLeft:              '{player} weg — terug naar spelkeuze',
    playerLeftGame:          '{player} heeft het spel verlaten',
    playerLeftReturning:     '{player} weg — terug naar spelkeuze',
    hostLeft:                'De host is gestopt — terug naar het startscherm',
    about:                   'Over deze app',
    aboutMadeBy:             'Gemaakt door iappyx',
    aboutLicense:            'Open source onder de MIT-licentie.',
    aboutCredits:            'Met dank aan',
    aboutFont:               'Emoji: Noto Color Emoji — © Google, SIL Open Font License 1.1',
    aboutSounds:             'Geluidseffecten: Kenney (kenney.nl) — publiek domein (CC0)',
    aboutPackages:           'Gebouwd met Flutter, Roboto en open-sourcepakketten',
    aboutAllLicenses:        'Alle licenties',
    aboutClose:              'Sluiten',
    connHelpTitle:           'Welke verbinding?',
    connNeeds:               'Nodig',
    connWorksWith:           'Werkt met',
    connFailsWhen:           'Werkt niet als',
    connWifiNeeds:           'Hetzelfde WiFi-netwerk, of de hotspot van één apparaat. Geen internet nodig.',
    connWifiWorks:           'Elk apparaat: Android, Mac, iPhone en iPad — ook door elkaar.',
    connWifiFails:           'Gast- of openbare WiFi die apparaten van elkaar scheidt, of een router die het zoeken blokkeert. Gebruik dan een hotspot.',
    connBtNeeds:             'Bluetooth aan en toestemming voor apparaten in de buurt. Geen WiFi of router nodig.',
    connBtWorks:             'Android met Android.',
    connBtFails:             'Er doet een Mac, iPhone of iPad mee, toestemming is geweigerd, of de apparaten zijn te ver uit elkaar (ongeveer 10 m).',
    connNearbyNeeds:         'WiFi aangezet (geen netwerk nodig) en toestemming voor apparaten in de buurt.',
    connNearbyWorks:         'Android met Android, of Apple met Apple (Mac, iPhone, iPad).',
    connNearbyFails:         'Android- en Apple-apparaten door elkaar, WiFi staat uit, of toestemming is geweigerd.',
    connGuideTitle:          'In het kort',
    connGuideHome:           'Thuis: WiFi.',
    connGuideRoad:           'Onderweg, alleen Android: Bluetooth of Nearby — beide werken prima.',
    connGuideMixed:          'Mac, iPhone of iPad samen met Android: WiFi, of de hotspot van een telefoon.',
    connGuideApple:          'Alleen Apple-apparaten: Nearby of WiFi.',
    connAppleNoBt:           'Bluetooth-modus bestaat alleen op Android. Speel je met Android-apparaten, gebruik dan WiFi.',
    connSameForAll:          'Iedereen moet dezelfde verbinding kiezen.',
    tabSubWifi:              'Zelfde WiFi of hotspot — werkt met elk apparaat',
    tabSubBluetooth:         'Geen WiFi nodig — alleen Android',
    tabSubNearbyAndroid:     'Geen router nodig — alleen Android',
    tabSubNearbyApple:       'Geen router nodig — alleen Apple-apparaten',
    nearbyHint:              'Zet WiFi aan op alle apparaten en geef toestemming. Werkt alleen Android met Android, of Apple met Apple.',
    webInviteTitle:          'Spelers zonder de app',
    webInviteHint:           'Scan met de camera van een telefoon of tablet op dezelfde WiFi of hotspot. Het spel opent in de browser.',
    webInviteBtn:            'Browserspelers uitnodigen',
    webCodeLabel:            'Code',
    webCodeHint:             'Code van het scherm van de host',
    webCodeWrong:            'Verkeerde code — kijk op het scherm van de host',
    connWebTitle:            'Browser (zonder app)',
    connWebNeeds:            'Een host op het WiFi-tabblad en dezelfde WiFi of zijn hotspot. Scan de QR-code.',
    connWebWorks:            'Elk apparaat met een browser (telefoon, tablet, computer), ook samen met app-spelers.',
    connWebFails:            'De host gebruikt Bluetooth of Nearby, de code is verkeerd, of gast-WiFi houdt apparaten gescheiden.',
    connGuideFriends:        'Vrienden zonder de app: host via WiFi en laat ze de QR-code scannen.',
    playerAway:              '{player} is weg — even wachten tot die terugkomt…',
    playerBack:              '{player} is terug',
    playerWentSelect:        '{player} ging naar Spelkeuze',
    hotspotMode:             'Hotspot-modus',
    hotspotHint:             'Gebruik dit als je direct verbonden bent via een hotspot',
    yourMove:                'Jouw beurt',
    opponentTurn:            '{player} is aan de beurt…',
    yourTurnRoll:            'Jouw beurt — gooi!',
    defaultPlayer:           'Speler',
    usingHotspot:            'Hotspot gebruiken?',
    profiles:                'profielen',
    manageProfiles:          'Profielen beheren',
    newProfile:              'Nieuw profiel',
    transportWifi:           'WiFi',
    transportBluetooth:      'Bluetooth',
    transportNearby:         'Nearby (P2P)',
    btSearching:             'Zoeken naar apparaten in de buurt…',
    btFoundHost:             'Host gevonden — tik om te verbinden:',
    btConnectTo:             'Verbinden met {name}',
    btPermissionTitle:       'Bluetooth-toestemming vereist',
    btPermissionBody:        'Deze app heeft Bluetooth- en locatietoestemming nodig om apparaten in de buurt te vinden. Ga naar Instellingen om dit in te schakelen.',
    btPermissionBtn:         'Instellingen openen',
    btNotSupported:          'Bluetooth niet beschikbaar op dit apparaat',
    draw:                    'Gelijkspel!',
    you:                     'Jij',
    winsLabel:               ' wint',
    boxesLabel:              ' vakjes',
    pairsLabel:              ' paren',
    hue:                     'Tint',
    sat:                     'Kleur',
    bri:                     'Helderheid',
    soloBtn:                 'Solo spelen',
    soloTitle:               'Solo Spel',
    soloChooseGame:          'Kies een spel',
    soloDifficulty:          'Moeilijkheid',
    soloEasy:                'Makkelijk',
    soloMedium:              'Gemiddeld',
    soloHard:                'Moeilijk',
    soloPlay:                'Spelen!',
    soloComputerName:        'Computer',
    soloOpponents:           'Tegenstanders',
    addComputers:            'Computerspelers toevoegen?',
    humanPlayers:            'spelers',
    noComputers:             'Geen computers',
    computer:                'computer',
    computers:               'computers',
    statsTitle:              'Statistieken',
    statsGame:               'Spel',
    statsWin:                'W',
    statsLoss:               'V',
    statsDraw:               'G',
    statsPlayed:             'GP',
    statsTotal:              'Totaal',
    statsEmpty:              'Nog geen statistieken — speel wat spelletjes!',
    statsClearTitle:         'Alle statistieken wissen?',
    statsClearBody:          'Dit verwijdert alle opgenomen resultaten permanent.',
    statsClearConfirm:       'Wissen',
    helpTitle:               'Hoe te spelen',
    helpClose:               'Sluiten',
    kleurEchoEndurance:          'Uithoudingsvermogen',
    kleurEchoBestScore:          'Beste: {n}',
    kleurEchoGameOver:           'Spel voorbij',
    kleurEchoScore:              'Score: {n}',
    tournament:              'Toernooi',
    tournamentMode:          'Toernooi-modus',
    tournamentResults:       'Toernooi-resultaten',
    startTournament:         'Toernooi starten',
    numberOfRounds:          'Aantal rondes',
    abortTournament:         'Toernooi afbreken?',
    abort:                   'Afbreken',
    whoWon:                  'Wie heeft gewonnen?',
    backToLobby:             'Terug naar Lobby',
    playAgainBtn:            'Opnieuw spelen',
    allFilter:               'Alle',
    browseTitle:             'Bladeren',
    gamesPlayed:             'gespeelde spellen',
    winRate:                 'winstpercentage',
    favourite:               'favoriet',
    winsTheTournament:       'wint het toernooi!',
    takesTheLead:            'neemt de leiding!',
    finalScore:              'Eindscore: {n}',
    finalStandings:          'EINDSTAND',
    noWins:                  'Geen overwinningen',
    roundByRound:            'PER RONDE',
    standings:               'STAND',
    rounds:                  'RONDES',
    playBtn:                 'Spelen',
    nWins:                   '{n} gewonnen',
    goesFirst:               '{player} begint',
    recordResult:            'Resultaat vastleggen',
    waitingForHostResult:    'Wachten op host…',
    roundNofM:               'Ronde {n}/{m}',
    nPoints:                 '{n} ptn',
    nRounds:                 '{n} rondes',
    catStrategy:             'Strategie',
    catWord:                 'Woord',
    catArcade:               'Arcade',
    catPuzzle:               'Puzzel',
    catClassic:              'Klassiek',
    catCard:                 'Kaart',
    singlePlayerOnly:        'Alleen solo',
    wifiHint:                'Zorg dat alle apparaten op hetzelfde WiFi-netwerk zitten. Gast-WiFi of lukt het niet? Gebruik de hotspot van één apparaat.',
    bluetoothHint:           'Zet Bluetooth aan op alle apparaten, geef toestemming en blijf binnen ongeveer 10 m.',
    connectionLostHint:      'Controleer dat beide apparaten dichtbij zijn en probeer opnieuw',
    noHostFound:             'Geen host gevonden. Is het andere apparaat een spel aan het hosten?',
    turnOnWifi:              'Zet WiFi aan om te verbinden',
    turnOnBluetooth:         'Zet Bluetooth aan om te verbinden',
    pickNewGame:             'Ander spel',
    backToStart:             'Terug',
    muteTooltip:             'Dempen',
    unmuteTooltip:           'Dempen uit',
    chatTooltip:             'Chat',
    obWelcome:               "Welkom bij Heiti's Game Suite!",
    obSubtitle:              'Een verzameling leuke spelletjes voor met vrienden of alleen',
    obHost:                  'Start een spel en nodig vrienden uit',
    obJoin:                  'Doe mee aan het spel van een vriend',
    obSolo:                  'Speel alleen tegen de computer',
    obReady:                 'Klaar om te spelen?',
    obLetsGo:                'We gaan!',
    obSkip:                  'Overslaan',
  );

  factory StringsCommon.en() => const StringsCommon(
    appTagline:              'Play together — no internet needed',
    yourName:                'Your name…',
    hostBtn:                 'Host',
    joinBtn:                 'Join',
    cancelBtn:               '✕ Cancel',
    waitingForPlayers:       'Waiting for players… (up to 4)',
    waitingForPlayers1:      'Waiting for 1 player…',
    waitingForHost:          'Waiting for host to start…',
    searchingForHost:        'Searching for host…',
    foundHost:               'Found host — tap to connect:',
    connecting:              'Connecting…',
    connectedWaiting:        'Connected! Waiting for host…',
    hostDisconnected:        'Host disconnected. Try again.',
    noHostsFound:            'No host found. Make sure both devices are on the same WiFi.',
    couldNotConnect:         'Could not connect: {err}',
    startGame:               'Start Game!',
    startN:                  'Start ({n} players)',
    chooseGame:              'Choose a game',
    nextGameFirst:           'Next game: {player} goes first',
    twoPlayersOnly:          '2 players only',
    choosePhoto:             'Choose photo',
    takeSelfie:              'Take a selfie',
    chooseFromGallery:       'Choose from gallery',
    cropPhoto:               'Crop photo',
    dragPinch:               'Drag & pinch to position',
    useThis:                 'Use this',
    connectTo:               'Connect to {ip}',
    pickColour:              'Pick a colour',
    playersConnected:        '{n} player(s) connected!',
    hostPicked:              'Host picked: {icon} {name}',
    waitingForHostStart:     'Waiting for host to start…',
    chatTitle:               'Chat',
    chatHint:                'Message…',
    isTyping:                '{player} is typing…',
    leaveGame:               'Leave game?',
    leaveGameContent:        'Choose where to go:',
    stay:                    'Stay',
    gameSelect:              'Game Select',
    lobby:                   'Lobby',
    leaving:                 'Leaving…',
    itsADraw:                "It's a Draw!",
    wins:                    '{player} wins!',
    playAgain:               'Play Again',
    reconnecting:            'Reconnecting…',
    waitingForReconnect:     'Waiting for others to reconnect…',
    playerReconnected:       'Player reconnected!',
    playerDisconnectedAgain: 'Player disconnected again.',
    couldNotRestart:         'Could not restart: {err}',
    foundHostConnecting:     'Found host, connecting…',
    rejoinConnected:         'Connected! Rejoining…',
    connectionFailed:        'Connection failed.',
    lostConnection:          'Lost connection again.',
    discoveryError:          'Discovery error: {err}',
    timedOut:                'Could not find the other tablet.\nMake sure both are on the same WiFi.',
    bothSameWifi:            'Both tablets need to be on the same WiFi or hotspot.',
    attempt:                 'Attempt {n}',
    retryNow:                'Retry now',
    exitToLobby:             'Exit to Lobby',
    playerLeft:              '{player} left — back to game select',
    playerLeftGame:          '{player} left the game',
    playerLeftReturning:     '{player} left — returning to game select',
    hostLeft:                'The host left — back to the start screen',
    about:                   'About this app',
    aboutMadeBy:             'Made by iappyx',
    aboutLicense:            'Open source under the MIT License.',
    aboutCredits:            'With thanks to',
    aboutFont:               'Emoji: Noto Color Emoji — © Google, SIL Open Font License 1.1',
    aboutSounds:             'Sound effects: Kenney (kenney.nl) — public domain (CC0)',
    aboutPackages:           'Built with Flutter, Roboto and open-source packages',
    aboutAllLicenses:        'All licenses',
    aboutClose:              'Close',
    connHelpTitle:           'Which connection?',
    connNeeds:               'Needs',
    connWorksWith:           'Works with',
    connFailsWhen:           'Doesn\'t work when',
    connWifiNeeds:           'The same WiFi network, or one device\'s hotspot. No internet needed.',
    connWifiWorks:           'Every device: Android, Mac, iPhone and iPad — also mixed.',
    connWifiFails:           'Guest or public WiFi that keeps devices apart, or a router that blocks discovery. Then use a hotspot.',
    connBtNeeds:             'Bluetooth on and permission for nearby devices. No WiFi or router needed.',
    connBtWorks:             'Android with Android.',
    connBtFails:             'A Mac, iPhone or iPad joins, permission is refused, or the devices are too far apart (about 10 m).',
    connNearbyNeeds:         'WiFi switched on (no network needed) and permission for nearby devices.',
    connNearbyWorks:         'Android with Android, or Apple with Apple (Mac, iPhone, iPad).',
    connNearbyFails:         'Android and Apple devices are mixed, WiFi is off, or permission is refused.',
    connGuideTitle:          'Quick guide',
    connGuideHome:           'At home: WiFi.',
    connGuideRoad:           'On the road, only Android: Bluetooth or Nearby — both work fine.',
    connGuideMixed:          'Mac, iPhone or iPad together with Android: WiFi, or a phone\'s hotspot.',
    connGuideApple:          'Only Apple devices: Nearby or WiFi.',
    connAppleNoBt:           'Bluetooth mode only exists on Android. To play with Android devices, use WiFi.',
    connSameForAll:          'Everyone must pick the same connection.',
    tabSubWifi:              'Same WiFi or hotspot — works with every device',
    tabSubBluetooth:         'No WiFi needed — Android only',
    tabSubNearbyAndroid:     'No router needed — Android only',
    tabSubNearbyApple:       'No router needed — Apple devices only',
    nearbyHint:              'Turn on WiFi on all devices and allow the permissions. Only works Android with Android, or Apple with Apple.',
    webInviteTitle:          'Players without the app',
    webInviteHint:           'Scan with the camera of a phone or tablet on the same WiFi or hotspot. The game opens in the browser.',
    webInviteBtn:            'Invite browser players',
    webCodeLabel:            'Code',
    webCodeHint:             'Code from the host\'s screen',
    webCodeWrong:            'Wrong code — check the host\'s screen',
    connWebTitle:            'Browser (no app)',
    connWebNeeds:            'A host on the WiFi tab and the same WiFi or its hotspot. Scan the QR code.',
    connWebWorks:            'Any device with a browser (phone, tablet, computer), also together with app players.',
    connWebFails:            'The host uses Bluetooth or Nearby, the code is wrong, or guest WiFi keeps devices apart.',
    connGuideFriends:        'Friends without the app: host on WiFi and let them scan the QR code.',
    playerAway:              '{player} dropped out — waiting a moment for them to come back…',
    playerBack:              '{player} is back',
    playerWentSelect:        '{player} went to Game Select',
    hotspotMode:             'Hotspot mode',
    hotspotHint:             'Use this when directly connected via a hotspot',
    yourMove:                'Your move',
    opponentTurn:            "{player}'s turn…",
    yourTurnRoll:            'Your turn — roll!',
    defaultPlayer:           'Player',
    usingHotspot:            'Using hotspot?',
    profiles:                'profiles',
    manageProfiles:          'Manage Profiles',
    newProfile:              'New Profile',
    transportWifi:           'WiFi',
    transportBluetooth:      'Bluetooth',
    transportNearby:         'Nearby (P2P)',
    btSearching:             'Searching for nearby devices…',
    btFoundHost:             'Found host — tap to connect:',
    btConnectTo:             'Connect to {name}',
    btPermissionTitle:       'Bluetooth permission needed',
    btPermissionBody:        'This app needs Bluetooth and location permission to find nearby devices. Go to Settings to enable this.',
    btPermissionBtn:         'Open Settings',
    btNotSupported:          'Bluetooth not available on this device',
    draw:                    'Draw!',
    you:                     'You',
    winsLabel:               ' wins',
    boxesLabel:              ' boxes',
    pairsLabel:              ' pairs',
    hue:                     'Hue',
    sat:                     'Sat',
    bri:                     'Bri',
    soloBtn:                 'Play Solo',
    soloTitle:               'Solo Game',
    soloChooseGame:          'Choose a game',
    soloDifficulty:          'Difficulty',
    soloEasy:                'Easy',
    soloMedium:              'Medium',
    soloHard:                'Hard',
    soloPlay:                'Play!',
    soloComputerName:        'Computer',
    soloOpponents:           'Opponents',
    addComputers:            'Add computer players?',
    humanPlayers:            'players',
    noComputers:             'No computers',
    computer:                'computer',
    computers:               'computers',
    statsTitle:              'Statistics',
    statsGame:               'Game',
    statsWin:                'W',
    statsLoss:               'L',
    statsDraw:               'D',
    statsPlayed:             'GP',
    statsTotal:              'Total',
    statsEmpty:              'No stats yet — play some games!',
    statsClearTitle:         'Clear all stats?',
    statsClearBody:          'This will permanently delete all recorded results.',
    statsClearConfirm:       'Clear',
    helpTitle:               'How to play',
    helpClose:               'Close',
    kleurEchoEndurance:          'Endurance',
    kleurEchoBestScore:          'Best: {n}',
    kleurEchoGameOver:           'Game Over',
    kleurEchoScore:              'Score: {n}',
    tournament:              'Tournament',
    tournamentMode:          'Tournament Mode',
    tournamentResults:       'Tournament Results',
    startTournament:         'Start Tournament',
    numberOfRounds:          'Number of rounds',
    abortTournament:         'Abort tournament?',
    abort:                   'Abort',
    whoWon:                  'Who won?',
    backToLobby:             'Back to Lobby',
    playAgainBtn:            'Play Again',
    allFilter:               'All',
    browseTitle:             'Browse',
    gamesPlayed:             'games played',
    winRate:                 'win rate',
    favourite:               'favourite',
    winsTheTournament:       'wins the tournament!',
    takesTheLead:            'takes the lead!',
    finalScore:              'Final score: {n}',
    finalStandings:          'FINAL STANDINGS',
    noWins:                  'No wins',
    roundByRound:            'ROUND-BY-ROUND',
    standings:               'STANDINGS',
    rounds:                  'ROUNDS',
    playBtn:                 'Play',
    nWins:                   '{n} wins',
    goesFirst:               '{player} goes first',
    recordResult:            'Record Result',
    waitingForHostResult:    'Waiting for host…',
    roundNofM:               'Round {n}/{m}',
    nPoints:                 '{n} pts',
    nRounds:                 '{n} rounds',
    catStrategy:             'Strategy',
    catWord:                 'Word',
    catArcade:               'Arcade',
    catPuzzle:               'Puzzle',
    catClassic:              'Classic',
    catCard:                 'Card',
    singlePlayerOnly:        'Solo only',
    wifiHint:                'Make sure all devices are on the same WiFi network. Guest WiFi or no luck? Use one device\'s hotspot.',
    bluetoothHint:           'Turn on Bluetooth on all devices, allow the permissions and stay within about 10 m.',
    connectionLostHint:      'Check that both devices are nearby and try again',
    noHostFound:             'No host found. Is the other device hosting a game?',
    turnOnWifi:              'Turn on WiFi to connect',
    turnOnBluetooth:         'Turn on Bluetooth to connect',
    pickNewGame:             'Pick a new game',
    backToStart:             'Back to start',
    muteTooltip:             'Mute',
    unmuteTooltip:           'Unmute',
    chatTooltip:             'Chat',
    obWelcome:               "Welcome to Heiti's Game Suite!",
    obSubtitle:              'A collection of fun games to play with friends or alone',
    obHost:                  'Start a game and invite friends nearby',
    obJoin:                  "Join a friend's game",
    obSolo:                  'Play alone against the computer',
    obReady:                 'Ready to play?',
    obLetsGo:                "Let's go!",
    obSkip:                  'Skip',
  );
}
