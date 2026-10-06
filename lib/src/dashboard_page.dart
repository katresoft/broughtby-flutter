import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The webview page that shows the dashboard.
///
/// The page's only job is to open the given address. The content is
/// rendered on the server, so there's no business logic here — a screen
/// changing on the server doesn't require a new app release.
class BroughtByDashboardPage extends StatefulWidget {
  const BroughtByDashboardPage({required this.url, this.title, this.refreshUrl, super.key});

  final Uri url;
  final String? title;

  /// Fetches a fresh address for a retry.
  ///
  /// The address the page opens with is short-lived. Reloading it after a
  /// failure would often fail again, for a different reason.
  final Future<Uri?> Function()? refreshUrl;

  @override
  State<BroughtByDashboardPage> createState() => _BroughtByDashboardPageState();
}

class _BroughtByDashboardPageState extends State<BroughtByDashboardPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

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
          onWebResourceError: (WebResourceError error) {
            // An image or a font failing doesn't make the page unusable.
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _failed = true;
                _loading = false;
              });
            }
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

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _loading = true;
    });

    Uri? fresh;
    try {
      fresh = await widget.refreshUrl?.call();
    } catch (_) {
      // Falls back to the address the page was opened with.
    }
    if (!mounted) return;
    await _controller.loadRequest(fresh ?? widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: widget.title == null ? null : Text(widget.title!)),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          // Covers the platform's own error page. The SDK ships no copy of
          // its own, so the way back is an icon, labelled by Flutter.
          if (_failed)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.refresh),
                    tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
                    onPressed: _retry,
                  ),
                ),
              ),
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
