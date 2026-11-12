///|
/// Register a `GET` route.
///
/// Equivalent to `add(HttpMethod::Get, pattern, ...)`.
pub fn Router::get(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Get, pattern, name~, mws~, handler)
}

///|
/// Register a `POST` route.
///
/// Equivalent to `add(HttpMethod::Post, pattern, ...)`.
pub fn Router::post(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Post, pattern, name~, mws~, handler)
}

///|
/// Register a `PUT` route.
///
/// Equivalent to `add(HttpMethod::Put, pattern, ...)`.
pub fn Router::put(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Put, pattern, name~, mws~, handler)
}

///|
/// Register a `DELETE` route.
///
/// Equivalent to `add(HttpMethod::Delete, pattern, ...)`.
pub fn Router::delete(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Delete, pattern, name~, mws~, handler)
}

///|
/// Register a `PATCH` route.
///
/// Equivalent to `add(HttpMethod::Patch, pattern, ...)`.
pub fn Router::patch(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Patch, pattern, name~, mws~, handler)
}

///|
/// Register a `HEAD` route.
///
/// Equivalent to `add(HttpMethod::Head, pattern, ...)`.
pub fn Router::head(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Head, pattern, name~, mws~, handler)
}

///|
/// Register an `OPTIONS` route.
///
/// Equivalent to `add(HttpMethod::Options, pattern, ...)`.
pub fn Router::options(
  self : Router,
  pattern : String,
  name~ : String = "",
  mws~ : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Options, pattern, name~, mws~, handler)
}
