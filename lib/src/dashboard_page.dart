import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The webview page that shows the dashboard.
///
/// The page's only job is to open the given address. The content is
/// rendered on the server, so there's no business logic here — a screen
/// changing on the server doesn't require a new app release.
class BroughtByDashboardPage extends StatefulWidget {
  const BroughtByDashboardPage({required this.url, this.title, super.key});

  final Uri url;
  final String? title;

  @override
  State<BroughtByDashboardPage> createState() => _BroughtByDashboardPageState();
}

class _BroughtByDashboardPageState extends State<BroughtByDashboardPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          // Navigation away from the dashboard is blocked: the webview
          // opens inside the app, so it shouldn't be able to wander off to
          // an arbitrary site.
          onNavigationRequest: (NavigationRequest request) {
            return Uri.parse(request.url).host == widget.url.host
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: widget.title == null ? null : Text(widget.title!)),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
