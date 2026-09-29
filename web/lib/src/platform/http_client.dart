import 'package:http/http.dart' as http;

import 'http_client_io.dart' if (dart.library.js_interop) 'http_client_web.dart' as impl;

/// An HTTP client that, in the browser, sends credentials so the backend's
/// httpOnly refresh cookie travels with `/auth/refresh`.
http.Client createHttpClient() => impl.createHttpClient();

/// Whether this build keeps the refresh token only in the browser cookie.
bool get usesRefreshCookie => impl.usesRefreshCookie;
