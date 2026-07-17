// header.mbt
// A Header represents the key-value pairs in an HTTP header.
// Keys are stored in canonical form (similar to net/http CanonicalHeaderKey).

///|
pub struct Header(Map[String, Array[String]])

///|
pub fn new() -> Header {
  Header(Map([]))
}

// CanonicalHeaderKey: roughly mimics Go's textproto.CanonicalMIMEHeaderKey.
// Rules:
// - Split by '-'.
// - For each token: first letter uppercase, rest lowercase.
// - Keep other characters as-is.

///|
pub fn canonicalHeaderKey(key : String) -> String {
  if key == "" {
    return ""
  }

  // Lowercase first, then Title-Case by '-' tokens.
  let lower = key.to_lower()
  let parts = lower.split("-")
  let out_parts : Array[String] = []
  for p in parts {
    if p == "" {
      out_parts.push("")
    } else {
      // upper first char, keep rest
      guard p is [first, .. rest]
      out_parts.push(first.to_string().to_upper() + rest.to_owned())
    }
  }
  out_parts.join("-")
}

// Add adds the key, value pair to the header.
// It appends to any existing values associated with key.
// The key is case insensitive; it is canonicalized.

///|
pub fn Header::add(h : Header, key : String, value : String) -> Unit {
  let k = canonicalHeaderKey(key)
  let Header(m) = h
  m.get_or_init(k, () => []).push(value)
}

// Set sets the header entries associated with key to the single element value.
// It replaces any existing values associated with key.
// The key is case insensitive; it is canonicalized.

///|
pub fn Header::set(h : Header, key : String, value : String) -> Unit {
  let k = canonicalHeaderKey(key)
  let Header(m) = h
  let arr = m.get_or_init(k, () => [])
  arr.drain(0, arr.length()).push(value)
}

// Get gets the first value associated with the given key.
// If there are no values, returns "".
// The key is case insensitive; it is canonicalized.

///|
pub fn Header::get(h : Header, key : String) -> String? {
  let k = canonicalHeaderKey(key)
  let Header(m) = h
  match m.get(k) {
    Some(vv) if vv.length() > 0 => Some(vv[0])
    _ => None
  }
}

// Values returns all values associated with the given key.
// If none, returns empty array.
// The key is case insensitive; it is canonicalized.
// NOTE: returns a copy for safety.

///|
pub fn Header::values(h : Header, key : String) -> Array[String] {
  let k = canonicalHeaderKey(key)
  let Header(m) = h
  match m.get(k) {
    Some(vv) => vv.copy()
    None => []
  }
}

// has reports whether h has the provided key defined.

///|
pub fn Header::has(h : Header, key : String) -> Bool {
  let k = canonicalHeaderKey(key)
  h.get(k) is Some(_)
}

// del deletes the values associated with key.
// The key is case insensitive; it is canonicalized.

///|
pub fn Header::del(h : Header, key : String) -> Unit {
  let k = canonicalHeaderKey(key)
  let Header(m) = h
  m.remove(k)
}

// Clone returns a deep copy of h.
// In Go, Header.Clone preserves nil vs empty slices; MoonBit version does not.

///|
pub fn Header::copy(h : Header) -> Header {
  let h2 = Map([], capacity=h.0.length())
  for k, vv in h.0 {
    h2.set(k, vv.copy())
  }
  h2
}
