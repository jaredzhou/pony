///|
/// Validate a route pattern before the router tree is modified.
fn validate_route_pattern(
  pattern : String,
  http_method : HttpMethod,
) -> Unit raise RouterError {
  guard pattern.has_prefix("/") else {
    raise RouterError::InvalidPattern(
      http_method=http_method.to_string(),
      path=pattern,
      reason="pattern must start with /",
    )
  }

  let mut remaining = pattern[:]
  while remaining != "" {
    match remaining {
      ['{', .. rest] => {
        guard rest.find("}") is Some(end_idx) else {
          raise RouterError::InvalidPattern(
            http_method=http_method.to_string(),
            path=pattern,
            reason="unclosed path parameter",
          )
        }
        remaining = rest[end_idx + 1:]
      }
      ['*', .. rest] => {
        guard rest == "" else {
          raise RouterError::InvalidPattern(
            http_method=http_method.to_string(),
            path=pattern,
            reason="* should be at the end of the pattern",
          )
        }
        remaining = rest
      }
      [_, .. rest] => remaining = rest
      [] => break
    }
  }
}
