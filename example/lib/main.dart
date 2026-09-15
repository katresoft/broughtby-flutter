import 'package:broughtby_flutter/broughtby_flutter.dart';
import 'package:flutter/material.dart';

/// A sample usage of the Broughtby SDK.
///
/// In a real app, `publicKey` is generated in the dashboard, and `jwt` is
/// the token your own session system (Supabase, Firebase, your own server)
/// issues — a fixed placeholder is used here for illustration.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BroughtBy.initialize(publicKey: 'bt_pk_example');

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Broughtby example',
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _code;
  String? _message;

  Future<void> _onSignedIn() async {
    // Pass your own JWT here once the user signs in.
    await BroughtBy.identify(jwt: 'the-users-session-token');
    final result = await BroughtBy.captureAttribution();
    setState(() => _message = result.toString());
  }

  Future<void> _fetchMyCode() async {
    final result = await BroughtBy.getAffiliate();
    if (result case BroughtByOk(:final value)) {
      setState(() => _code = value.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broughtby example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ElevatedButton(
              onPressed: _onSignedIn,
              child: const Text('I signed in'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchMyCode,
              child: const Text('Show my code'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              // The title is the app's own string; the SDK ships no copy.
              onPressed: () => BroughtBy.openDashboard(context, title: 'My earnings'),
              child: const Text('Open my earnings screen'),
            ),
            if (_code != null) Text('Your code: $_code'),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}
