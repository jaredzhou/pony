///|
/// Parses a raw request value (path param, query, header, form field)
/// into a typed value. Used as the constraint of the typed accessors
/// `Context::param`, `Context::query`, `Context::header` and
/// `Context::form`, so callers pick the target type at the call site:
///
/// ```mbt nocheck
/// let id : Int = ctx.param("id") // parse failure -> InvalidValue (400)
///
/// let name : String = ctx.param("name") // identity, never fails
/// ```
///
/// This is a local mirror of `@string.FromStr` (which lacks a `String`
/// impl that pony cannot add from outside). Implement it for your own
/// types to use them with the typed accessors:
///
/// ```mbt nocheck
/// pub impl @pony.FromStr for MyType with fn from_str(s) {
///   ...
/// }
/// ```
///
/// # Example
/// ```mbt check
/// test {
///   let n : Int = FromStr::from_str("42") catch { _ => -1 }
///   inspect(n, content="42")
///   let b : Bool = FromStr::from_str("true") catch { _ => false }
///   inspect(b, content="true")
/// }
/// ```
pub(open) trait FromStr {
  fn from_str(String) -> Self raise
}

///|
pub impl FromStr for String with fn from_str(s) {
  s
}

///|
pub impl FromStr for Int with fn from_str(s) {
  @string.from_str(s)
}

///|
pub impl FromStr for Int64 with fn from_str(s) {
  @string.from_str(s)
}

///|
pub impl FromStr for UInt with fn from_str(s) {
  @string.from_str(s)
}

///|
pub impl FromStr for UInt64 with fn from_str(s) {
  @string.from_str(s)
}

///|
pub impl FromStr for Double with fn from_str(s) {
  @string.from_str(s)
}

///|
pub impl FromStr for Bool with fn from_str(s) {
  @string.from_str(s)
}
