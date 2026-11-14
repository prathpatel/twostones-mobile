/// Mock server response for /api/account endpoint.
String mockApiAccountResponse(String username) =>
    '''
{
  "id": "${username.toLowerCase()}",
  "username": "$username",
  "createdAt": 1290415680000,
  "seenAt": 1290415680000,
  "patron": true,
  "patronColor": 1,
  "perfs": {
    "blitz": {
      "games": 2340,
      "rating": 1681,
      "rd": 30,
      "prog": 10
    },
    "rapid": {
      "games": 2340,
      "rating": 1677,
      "rd": 30,
      "prog": 10
    },
    "classical": {
      "games": 2340,
      "rating": 1618,
      "rd": 30,
      "prog": 10
    }
  },
  "profile": {
    "country": "France",
    "location": "Lille",
    "bio": "test bio",
    "realName": "John Doe",
    "links": "http://test.com"
  }
}
''';

/// Mock server response for /api/mobile/games/user/:id (ND-JSON).
String mockUserRecentGameResponse(String username) =>
    '''
{"id":"Huk88k3D","rated":false,"speed":"blitz","perf":"blitz","size":19,"handicap":0,"komi":7.5,"createdAt":1673716450321,"lastMoveAt":1673716450321,"status":"noStart","players":{"white":{"user":{"name":"MightyNanook","id":"mightynanook"},"rating":1116,"provisional":true},"black":{"user":{"name":"$username","patron":true,"id":"${username.toLowerCase()}"},"rating":1772}},"winner":"black","clock":{"initial":300,"increment":0,"totalTime":300}}
{"id":"g2bzFol8","rated":true,"speed":"blitz","perf":"blitz","size":19,"handicap":0,"komi":7.5,"createdAt":1673553626465,"lastMoveAt":1673553936657,"status":"resign","players":{"white":{"user":{"name":"SchallUndRausch","id":"schallundrausch"},"rating":1751,"ratingDiff":-5},"black":{"user":{"name":"$username","patron":true,"id":"${username.toLowerCase()}"},"rating":1767,"ratingDiff":5}},"winner":"black","clock":{"initial":180,"increment":2,"totalTime":260},"lastMove":"dd"}
{"id":"9WLmxmiB","rated":true,"speed":"blitz","perf":"blitz","size":9,"handicap":0,"komi":7.5,"createdAt":1673553299064,"lastMoveAt":1673553615438,"status":"resign","players":{"white":{"user":{"name":"Dr-Alaakour","id":"dr-alaakour"},"rating":1806,"ratingDiff":5},"black":{"user":{"name":"$username","patron":true,"id":"${username.toLowerCase()}"},"rating":1772,"ratingDiff":-5}},"winner":"white","clock":{"initial":180,"increment":0,"totalTime":180},"lastMove":"ee"}
''';

/// Mock server response for /api/account/playing.
String mockAccountOngoingGamesResponse() =>
    '''
{
  "nowPlaying": [
    {
      "gameId": "rCRw1AuO",
      "fullId": "rCRw1AuOvonq",
      "color": "black",
      "size": 9,
      "board": "${'.' * 40}b${'.' * 40}",
      "hasMoved": true,
      "isMyTurn": false,
      "lastMove": "ee",
      "opponent": {
        "id": "philippe",
        "rating": 1790,
        "username": "Philippe"
      },
      "perf": "correspondence",
      "rated": false,
      "secondsLeft": 1209600,
      "source": "friend",
      "speed": "correspondence"
    }
  ]
}
''';

/// Mock server response for /tournament/featured endpoint.
const mockFeaturedTournamentsResponse = '''
{
  "featured": [
    {
      "id": "AbCdEfGh",
      "fullName": "Hourly Blitz Arena",
      "clock": {"limit": 300, "increment": 0},
      "rated": true,
      "createdBy": "lichess",
      "minutes": 57,
      "perf": {"key": "blitz", "name": "Blitz", "position": 1},
      "schedule": {"freq": "hourly", "speed": "blitz"},
      "variant": "standard",
      "startsAt": 1700000000000,
      "finishesAt": 1700003420000,
      "nbPlayers": 100
    }
  ]
}
''';
