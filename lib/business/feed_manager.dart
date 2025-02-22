// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'package:envoy/business/local_storage.dart';
import 'package:envoy/business/video.dart';
import 'package:envoy/util/envoy_storage.dart';
import 'package:tor/tor.dart';
import 'package:webfeed/webfeed.dart';
import 'package:http_tor/http_tor.dart';
import 'package:envoy/business/blog_post.dart';
import 'package:envoy/business/scheduler.dart';

class FeedManager {
  static const vimeoToken = "141c53cdd50a0285e03885dc6f444f9a";
  static const vimeoAccountId = "210701027";

  List<Video> videos = [];
  List<BlogPost> blogs = [];

  static final FeedManager _instance = FeedManager._internal();

  factory FeedManager() {
    return _instance;
  }

  static Future<FeedManager> init() async {
    var singleton = FeedManager._instance;
    return singleton;
  }

  FeedManager._internal() {
    print("Instance of FeedManager created!");
    _restoreVideos();
    _restoreBlogs();

    _addVideosFromVimeo();

    HttpTor(Tor.instance, EnvoyScheduler().parallel)
        .get("https://foundationdevices.com/feed/")
        .then((response) {
      RssFeed feed = RssFeed.parse(response.body);
      _addBlogPostsFromRssFeed(feed);
    });
  }

  Future<Response> _getVimeoData(
      {int videosPerPage = 100, int page = 1}) async {
    String videoPerPageString = "?per_page=$videosPerPage";
    String pageString = "&page=$page";

    return await HttpTor(Tor.instance, EnvoyScheduler().parallel).get(
      "https://api.vimeo.com/users/$vimeoAccountId/videos$videoPerPageString$pageString",
      headers: {'authorization': "bearer $vimeoToken"},
    );
  }

  _addVideosFromVimeo() async {
    List<Video> currentVideos = [];

    final response = await _getVimeoData();

    final data = json.decode(response.body);
    final videos = (data['data'] as List);

    final lastPage = data["paging"]["last"];
    var lastNum = int.parse(lastPage[lastPage.length - 1]);

    currentVideos.addAll(_parseVideos(videos));

    if (lastNum > 1) {
      for (var i = 2; i <= lastNum; i++) {
        var response = await _getVimeoData(
          page: i,
        );

        final data = json.decode(response.body);
        final videos = (data['data'] as List);

        currentVideos.addAll(_parseVideos(videos));
      }
    }

    updateVideos(currentVideos);
  }

  List<Video> _parseVideos(List<dynamic> videos) {
    List<Video> currentVideos = [];

    videos.forEach((video) {
      var downloads = video["download"];

      Map<int, String> contentMap = {};

      for (var content in downloads) {
        contentMap[content['height']] = content["link"];
      }

      var orderString = "";

      List<String>? tags = [];

      var tagsLength = video["tags"].length;
      if (tagsLength >= 2) {
        orderString = video["tags"][1]["tag"];
      }

      tags.add(orderString);

      var order =
          orderString != "" ? int.tryParse(orderString.split('-').last) : null;

      currentVideos.add(Video(
        video["name"],
        video["description"],
        video["duration"],
        DateTime.parse(video["release_time"]),
        contentMap,
        video["player_embed_url"],
        video["link"],
        null,
        order,
        tags,
        thumbnailUrl: (video["pictures"])["sizes"][3]["link"],
      ));
    });

    return currentVideos;
  }

  _addBlogPostsFromRssFeed(RssFeed feed) async {
    List<BlogPost> currentBlogPosts = [];

    for (RssItem item in feed.items!) {
      var thumbnailUrl = item.content?.images.first;
      String htmlContent = item.content!.value;

      currentBlogPosts.add(BlogPost(
        item.title!,
        htmlContent, // Use the decoded HTML content
        item.pubDate!,
        item.link!,
        item.guid!,
        null,
        thumbnailUrl: thumbnailUrl,
      ));
    }
    updateBlogPosts(currentBlogPosts);
  }

  _dropVideos() {
    videos.clear();
  }

  _dropBlogs() {
    blogs.clear();
  }

  _restoreVideos() async {
    _dropVideos();

    var storedVideos = await EnvoyStorage().getAllVideos();
    for (var video in storedVideos!) {
      videos.add(video!);
    }
  }

  _restoreBlogs() async {
    _dropBlogs();

    var storedBlogs = await EnvoyStorage().getAllBlogPosts();
    for (var blog in storedBlogs!) {
      blogs.add(blog!);
    }
  }

  updateVideos(List<Video> currentVideos) async {
    for (var video in currentVideos) {
      for (var storedVideo in videos) {
        if (video.url == storedVideo.url && storedVideo.watched != null) {
          video.watched = storedVideo.watched;
        }
      }

      final thumbnail = await video.thumbnail;
      if (thumbnail == null || thumbnail.isEmpty) {
        _getVideoThumbnail(video);
      }
    }

    videos = currentVideos;
    storeVideos();
  }

  void _getVideoThumbnail(Video video) {
    HttpTor(Tor.instance, EnvoyScheduler().parallel)
        .get(video.thumbnailUrl!)
        .then((response) async {
      await LocalStorage()
          .saveFileBytes(video.thumbnailHash!, response.bodyBytes);
    });
  }

  updateBlogPosts(List<BlogPost> currentBlogPosts) async {
    for (var blog in currentBlogPosts) {
      for (var storedBlogPosts in blogs) {
        if (blog.url == storedBlogPosts.url && storedBlogPosts.read != null) {
          blog.read = storedBlogPosts.read;
          storeBlogPosts();
        }
      }

      final thumbnail = await blog.thumbnail;
      if (thumbnail == null || thumbnail.isEmpty) {
        _getBlogThumbnail(blog);
      }
    }

    blogs = currentBlogPosts;
    storeBlogPosts();
  }

  void _getBlogThumbnail(BlogPost blog) {
    HttpTor(Tor.instance, EnvoyScheduler().parallel)
        .get(blog.thumbnailUrl!)
        .then((response) async {
      await LocalStorage()
          .saveFileBytes(blog.thumbnailHash!, response.bodyBytes);
    });
  }

  storeVideos() {
    for (var video in videos) {
      EnvoyStorage().insertVideo(video);
    }
  }

  storeBlogPosts() {
    for (var BlogPost in blogs) {
      EnvoyStorage().insertBlogPost(BlogPost);
    }
  }
}
