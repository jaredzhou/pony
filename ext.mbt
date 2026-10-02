///|
/// Marker type for per-request extension data (e.g. request ID).
pub(all) struct RequestId {}

///|
/// Marker type for per-user extension data (e.g. authenticated user ID).
pub(all) struct UserId {}

///|
pub(all) suberror ExtError {
  /// The requested key was not present in the context.
  Missing
  /// The stored value could not be decoded into the requested type.
  DecodeError(key~ : String, msg~ : String)
} derive(Debug, Eq, ToJson)

///|
pub extend ExtError with @debug.Debug::{to_repr}

///|
pub extend ExtError with Eq::{not_equal, equal}

///|
pub extend ExtError with ToJson::{to_json}
