///|
pub(all) struct ApiError {
  code : Int
  message : String
  details : Array[Map[String, String]]?
} derive(Debug, ToJson)

///|
pub extend ApiError with @debug.Debug::{to_repr}

///|
pub extend ApiError with ToJson::{to_json}

///|
pub let ok : Int = 0

///|
pub let cancelled : Int = 1

///|
pub let unknown : Int = 2

///|
pub let invalid_argument : Int = 3

///|
pub let deadline_exceeded : Int = 4

///|
pub let not_found : Int = 5

///|
pub let already_exists : Int = 6

///|
pub let permission_denied : Int = 7

///|
pub let resource_exhausted : Int = 8

///|
pub let failed_precondition : Int = 9

///|
pub let aborted : Int = 10

///|
pub let out_of_range : Int = 11

///|
pub let unimplemented : Int = 12

///|
pub let internal : Int = 13

///|
pub let unavailable : Int = 14

///|
pub let data_loss : Int = 15

///|
pub let unauthenticated : Int = 16

///|
pub fn ApiError::new(code : Int, message : String) -> ApiError {
  { code, message, details: None, }
}

///|
/// Convenience constructors for the 16 canonical `ApiError` codes.
/// Each one is equivalent to `ApiError::new(<code>, msg)` with the code
/// baked in, so the code cannot be mistyped. For custom codes, keep using
/// `ApiError::new` together with `register`.
pub fn ApiError::cancelled(msg : String) -> ApiError {
  ApiError::new(cancelled, msg)
}

///|
pub fn ApiError::unknown(msg : String) -> ApiError {
  ApiError::new(unknown, msg)
}

///|
pub fn ApiError::invalid_argument(msg : String) -> ApiError {
  ApiError::new(invalid_argument, msg)
}

///|
pub fn ApiError::deadline_exceeded(msg : String) -> ApiError {
  ApiError::new(deadline_exceeded, msg)
}

///|
pub fn ApiError::not_found(msg : String) -> ApiError {
  ApiError::new(not_found, msg)
}

///|
pub fn ApiError::already_exists(msg : String) -> ApiError {
  ApiError::new(already_exists, msg)
}

///|
pub fn ApiError::permission_denied(msg : String) -> ApiError {
  ApiError::new(permission_denied, msg)
}

///|
pub fn ApiError::resource_exhausted(msg : String) -> ApiError {
  ApiError::new(resource_exhausted, msg)
}

///|
pub fn ApiError::failed_precondition(msg : String) -> ApiError {
  ApiError::new(failed_precondition, msg)
}

///|
pub fn ApiError::aborted(msg : String) -> ApiError {
  ApiError::new(aborted, msg)
}

///|
pub fn ApiError::out_of_range(msg : String) -> ApiError {
  ApiError::new(out_of_range, msg)
}

///|
pub fn ApiError::unimplemented(msg : String) -> ApiError {
  ApiError::new(unimplemented, msg)
}

///|
pub fn ApiError::internal(msg : String) -> ApiError {
  ApiError::new(internal, msg)
}

///|
pub fn ApiError::unavailable(msg : String) -> ApiError {
  ApiError::new(unavailable, msg)
}

///|
pub fn ApiError::data_loss(msg : String) -> ApiError {
  ApiError::new(data_loss, msg)
}

///|
pub fn ApiError::unauthenticated(msg : String) -> ApiError {
  ApiError::new(unauthenticated, msg)
}

///|
let codes : Map[Int, Int] = Map([])

///|
fn init {
  codes[ok] = 200
  codes[cancelled] = 499
  codes[unknown] = 500
  codes[invalid_argument] = 400
  codes[failed_precondition] = 400
  codes[out_of_range] = 400
  codes[deadline_exceeded] = 504
  codes[not_found] = 404
  codes[already_exists] = 409
  codes[permission_denied] = 403
  codes[unauthenticated] = 401
  codes[resource_exhausted] = 429
  codes[aborted] = 409
  codes[unimplemented] = 501
  codes[internal] = 500
  codes[unavailable] = 503
  codes[data_loss] = 500
}

///|
pub fn ApiError::to_http_status(code : Int) -> Int {
  match codes.get(code) {
    Some(status) => status
    None => 500
  }
}

///|
pub fn register(code : Int, http_status : Int) -> Unit {
  codes[code] = http_status
}

///|
/// Types that can be converted to an `ApiError` for use with `reply_error`.
/// `reply_error` accepts any `T : ToApiError`, so you can pass `PonyError`,
/// `ApiError`, or your own error types directly.
pub(open) trait ToApiError {
  fn to_api_error(Self) -> ApiError
}

///|
pub impl ToApiError for ApiError with fn to_api_error(self : ApiError) -> ApiError {
  self
}

///|
pub extend ApiError with ToApiError::{to_api_error}

///|
/// Convert a `PonyError` to an `ApiError`.
/// Kept for backward compatibility — delegates to the `ToApiError` trait.
pub fn to_api_error(e : PonyError) -> ApiError {
  ToApiError::to_api_error(e)
}
