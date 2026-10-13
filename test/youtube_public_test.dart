import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/youtube_public.dart';

void main() {
  const videoId = 'abcD123xyZ0';

  String html({
    Map<String, dynamic>? initial,
    String description = '작품 번호 2711759',
    bool withConfig = true,
  }) {
    final player = {
      'videoDetails': {
        'title': 'A Short with } and quotes " inside',
        'shortDescription': description,
      },
      'playabilityStatus': {'status': 'OK'},
    };
    final config = {
      'INNERTUBE_API_KEY': 'public-web-key',
      'INNERTUBE_CONTEXT': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.test',
          'hl': 'en', 'gl': 'US',
        },
      },
    };
    return '<html><script>var ytInitialPlayerResponse = ' +
        jsonEncode(player) + ';</script>' +
        '<script>var ytInitialData = ' + jsonEncode(initial ?? {}) +
        ';</script>' +
        (withConfig ? '<script>ytcfg.set(' + jsonEncode(config) + ');</script>' : '') +
        '</html>';
  }

  http.Response watchResponse(String htmlText) => http.Response.bytes(
      utf8.encode(htmlText), 200,
      headers: {'content-type': 'text/html; charset=utf-8'});

  Map<String, dynamic> section(String token) => {
    'contents': {
      'twoColumnWatchNextResults': {
        'results': {
          'results': {
            'contents': [
              {
                'itemSectionRenderer': {
                  'targetId': 'comments-section',
                  'contents': [
                    {
                      'continuationItemRenderer': {
                        'continuationEndpoint': {
                          'continuationCommand': {'token': token},
                        },
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
      },
    },
  };

  test('no user API key: extracts old and new comment structures', () async {
    final requestedTokens = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        expect(request.url.host, 'www.youtube.com');
        return watchResponse(html(initial: section('comments-one')));
      }
      expect(request.url.path, '/youtubei/v1/next');
      expect(request.url.queryParameters['key'], 'public-web-key');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final token = payload['continuation'] as String;
      requestedTokens.add(token);
      if (token == 'comments-one') {
        return http.Response(jsonEncode({
          'onResponseReceivedEndpoints': [
            {
              'appendContinuationItemsAction': {
                'continuationItems': [
                  {
                    'commentThreadRenderer': {
                      'comment': {
                        'commentRenderer': {
                          'contentText': {
                            'runs': [{'text': '번호 '}, {'text': '2711759'}],
                          },
                        },
                      },
                    },
                  },
                  {
                    'continuationItemRenderer': {
                      'continuationEndpoint': {
                        'continuationCommand': {'token': 'comments-two'},
                      },
                    },
                  },
                ],
              },
            },
          ],
          'frameworkUpdates': {
            'entityBatchUpdate': {
              'mutations': [
                {
                  'entityKey': 'comment_entity_2',
                  'payload': {
                    'commentEntityPayload': {
                      'properties': {
                        'content': {'content': '고정 댓글 112233'},
                      },
                    },
                  },
                },
              ],
            },
          },
        }), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({
        'onResponseReceivedEndpoints': [
          {
            'appendContinuationItemsAction': {
              'continuationItems': [
                {
                  'commentRenderer': {
                    'contentText': {'simpleText': '추가 번호 445566'},
                  },
                },
                {
                  'commentRenderer': {
                    'contentText': {'simpleText': '고정 댓글 112233'},
                  },
                },
              ],
            },
          },
        ],
      }), 200, headers: {'content-type': 'application/json'});
    });

    final data = await YoutubePublicClient(client).fetch(videoId);
    expect(data.title, contains('quotes'));
    expect(data.description, contains('2711759'));
    expect(data.comments, containsAll(['번호 2711759', '고정 댓글 112233',
        '추가 번호 445566']));
    expect(data.comments.length, 3);
    expect(requestedTokens, ['comments-one', 'comments-two']);
    client.close();
  });

  test('falls back to initial next request for comments continuation', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return watchResponse(html(description: ''));
      }
      final json = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(json);
      if (requests.length == 1) {
        return http.Response(jsonEncode(section('continuation-from-next')),
            200, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({
        'frameworkUpdates': {
          'entityBatchUpdate': {
            'mutations': [
              {'payload': {
                'commentEntityPayload': {
                  'properties': {'content': {'content': '1234567'}}
                }
              }}
            ]
          }
        }
      }), 200, headers: {'content-type': 'application/json'});
    });
    final data = await YoutubePublicClient(client).fetch(videoId);
    expect(requests.first['videoId'], videoId);
    expect(requests.last['continuation'], 'continuation-from-next');
    expect(data.comments, ['1234567']);
    client.close();
  });

  test('clearly fails when public web configuration is unavailable', () async {
    final client = MockClient((request) async =>
        watchResponse(html(initial: section('one'), withConfig: false)));
    expect(() => YoutubePublicClient(client).fetch(videoId),
        throwsFormatException);
    client.close();
  });

  test('does not pretend empty comments were successfully loaded', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return watchResponse(html(
          initial: section('comments-one'), description: ''));
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    expect(() => YoutubePublicClient(client).fetch(videoId),
        throwsFormatException);
    client.close();
  });
}
