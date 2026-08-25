import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/api_client.dart';
import '../../core/token_storage.dart';

class VideoStreamSource {
  VideoStreamSource({required this.uri, required Map<String, String> headers})
    : headers = Map.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
}

abstract interface class VideoStreamSourceLoader {
  Future<VideoStreamSource> prepare(int mediaId);
}

class DioVideoStreamSourceLoader implements VideoStreamSourceLoader {
  DioVideoStreamSourceLoader(this._dio, this._tokenStorage);

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<VideoStreamSource> prepare(int mediaId) async {
    // 네이티브 재생 전 Dio의 401 갱신 경로를 통한 최신 access token 확보
    final response = await _dio.head<void>(
      '/media/$mediaId/original',
      options: Options(responseType: ResponseType.plain),
    );
    final accessToken = await _tokenStorage.readAccessToken();

    if (accessToken == null) {
      throw StateError('영상 스트리밍에 사용할 access token이 없습니다.');
    }

    return VideoStreamSource(
      uri: response.realUri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}

abstract interface class VideoPlaybackController
    implements ValueListenable<VideoPlayerValue> {
  Widget buildView();

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

class PluginVideoPlaybackController implements VideoPlaybackController {
  PluginVideoPlaybackController(VideoStreamSource source)
    : _controller = VideoPlayerController.networkUrl(
        source.uri,
        httpHeaders: source.headers,
      );

  final VideoPlayerController _controller;

  @override
  VideoPlayerValue get value => _controller.value;

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume);

  @override
  Future<void> dispose() => _controller.dispose();
}

typedef VideoPlaybackControllerFactory =
    VideoPlaybackController Function(VideoStreamSource source);

final videoStreamSourceLoaderProvider = Provider<VideoStreamSourceLoader>((
  ref,
) {
  return DioVideoStreamSourceLoader(
    ref.watch(dioProvider),
    ref.watch(tokenStorageProvider),
  );
});

final videoPlaybackControllerFactoryProvider =
    Provider<VideoPlaybackControllerFactory>((ref) {
      return PluginVideoPlaybackController.new;
    });
