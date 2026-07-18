// multipart.mbt — multipart/form-data parsing
//
// Relevant specifications:
//   RFC 7578       Returning Values from Forms: multipart/form-data
//   RFC 2046 §5.1  Multipart Media Type — boundary delimiter syntax
//   RFC 2183 §2    Content-Disposition — filename parameter
//
// ============================================================================
// Quick Start
// ============================================================================
//
// The simplest way to handle a multipart file upload is through
// `Context::parse_multipart_form`.  Behind the scenes it:
//
//   1. Parses the raw body into memory  (sync)
//   2. Spills files that exceed `max_memory` to temp disk  (async)
//   3. Cleans up temp files when the request finishes  (async)
//
// ```moonbit nocheck
// fn upload_handler : Handler = async fn(ctx) {
//   // Step 1 — parse the multipart body (default 32 MiB memory threshold).
//   // Raises MultipartError if the body is malformed or missing a boundary.
//   ctx.parse_multipart_form(max_memory=64 * 1024 * 1024)!  // 64 MiB
//
//   // Step 2 — read regular form fields via ctx.try_form().
//   // After parsing, try_form() bridges to the multipart fields automatically.
//   let username = ctx.try_form("username").unwrap_or("anonymous")
//   let title    = ctx.try_form("title").unwrap_or("")
//
//   // Step 3 — access uploaded files.
//   match ctx.form_file("avatar") {
//     Some(file) => {
//       let header = file.header()          // FileHeader { filename, size, … }
//       let data   = file.bytes()           // Bytes — reads from disk if needed
//
//       // … save to storage, resize, etc. …
//       println("received \{header.filename} (\{header.size} bytes)")
//       println("content type: \{header.content_type.unwrap_or("unknown")}")
//     }
//     None => ctx.write_text(400, "avatar is required")
//   }
//
//   // Step 4 — access multiple files under the same field name.
//   for doc in ctx.form_files("attachments") {
//     println("attachment: \{doc.header().filename}")
//   }
//
//   // Step 5 — respond.  Temp files are cleaned up automatically
//   // by the framework after the handler returns.
//   ctx.response_ok({"user": username, "title": title})
// }
// ```
//
// ============================================================================
// How a multipart body looks on the wire
// ============================================================================
//
// Client sends a POST with `Content-Type: multipart/form-data; boundary=----Boundary`.
// The body is a sequence of parts separated by boundary delimiters:
//
//   ------Boundary\r\n                                    ← part separator
//   Content-Disposition: form-data; name="username"\r\n   ← part header
//   \r\n                                                   ← blank line
//   alice\r\n                                              ← part body
//   ------Boundary\r\n                                    ← next separator
//   Content-Disposition: form-data; name="avatar"; filename="cat.png"\r\n
//   Content-Type: image/png\r\n
//   \r\n
//   <binary PNG data>\r\n
//   ------Boundary--\r\n                                   ← final delimiter
//
// Each part is:
//   • A boundary line: `--` followed by the boundary value.
//   • MIME headers (Content-Disposition is required; Content-Type is optional).
//   • A blank line (empty `\r\n`).
//   • The body content.
//
// The final delimiter appends `--` after the boundary value.
//
// ============================================================================
// Architecture
// ============================================================================
//
// The module is split into three layers to keep the parsing synchronous
// and testable while still supporting async disk I/O for large files:
//
//   Layer                     Async?   Purpose
//   ────────────────────────  ───────  ──────────────────────────
//   parse_multipart(..)       sync     Pure in‑memory parsing.
//                                      All file content stays in RAM.
//                                      ✅ callable from test functions.
//
//   MultipartForm::           async    Walk every file; when its size
//     spill_large_files_to_disk         exceeds max_memory, write it
//                                      to a unique temp file under the
//                                      temp directory.
//
//   Context::                 async    Orchestrator: parse → spill →
//     parse_multipart_form              store on context → auto‑cleanup.
//
// Context::parse_multipart_form is the public entry point.  Every
// file is first buffered in memory by parse_multipart, then
// spill_large_files_to_disk moves oversized ones to disk in a second
// pass.  This two‑phase approach keeps the parser pure and testable
// while deferring I/O to the async runtime.

///|
/// Default memory threshold: 32 MiB.
/// Files larger than this are written to temporary disk files
/// (via `MultipartForm::spill_to_disk`).
pub let default_max_memory : Int64 = 32 * 1024 * 1024

///|
/// Errors that may occur during multipart parsing.
pub(all) suberror MultipartError {
  MissingBoundary
  MissingName
  MalformedBody(String)
  FileTooLarge(String, Int64)
  FileIOError(String)
} derive(Debug)

// ---------------------------------------------------------------------------
// IO traits
// ---------------------------------------------------------------------------

///|
/// Close the resource. Safe to call multiple times.
pub trait Closer {
  fn close(Self) -> Unit
}

///|
/// A writer that can be closed.
pub trait WriterCloser: @io.Writer + Closer {}

///|
/// A reader that can be closed.
pub trait ReaderCloser: @io.Reader + Closer {}

///|
/// Wraps an `@fs.File` as a `WriterCloser` for multipart uploads.
pub(all) struct FileWriter(@fs.File)

///|
impl @io.Writer for FileWriter with fn write_once(
  self : FileWriter,
  data : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int {
  let FileWriter(f) = self
  f.write_once(data, offset~, len~)
}

///|
impl Closer for FileWriter with fn close(self : FileWriter) -> Unit {
  let FileWriter(f) = self
  f.close()
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

///|
/// Case-insensitive MIME part headers.
///
/// Keys are normalised to lower-case on insertion and lookup.
pub(all) struct PartHeaders(Map[String, String])

///|
pub fn PartHeaders::new() -> PartHeaders {
  PartHeaders(Map([]))
}

///|
fn PartHeaders::set(self : PartHeaders, key : String, value : String) -> Unit {
  let PartHeaders(m) = self
  m[key.to_lower()] = value
}

///|
/// Return the value for `key` (case-insensitive), or `None`.
pub fn PartHeaders::get(self : PartHeaders, key : String) -> String? {
  let PartHeaders(m) = self
  m.get(key.to_lower())
}

///|
/// Return true if `key` is present.
pub fn PartHeaders::has(self : PartHeaders, key : String) -> Bool {
  let k = key.to_lower()
  let PartHeaders(m) = self
  m.contains(k)
}

///|
/// Return true if there are no entries.
pub fn PartHeaders::is_empty(self : PartHeaders) -> Bool {
  let PartHeaders(m) = self
  m.length() == 0
}

// ============================================================================
// Streaming Part
// ============================================================================

///|
/// A single part in a multipart stream.
///
/// Owns a lookback buffer for boundary scanning. When the body reaches
/// the next boundary delimiter, `read_chunk` returns `None` and the
/// remaining bytes after the boundary are recoverable via
/// `take_remaining()`.
pub(all) struct Part {
  source : &@io.Reader
  delimiter : Bytes // "--boundary"
  headers : PartHeaders
  mut buf : @buffer.Buffer // unprocessed data (initial + new chunks)
  mut body_eof : Bool // true when boundary delimiter found
}

///|
/// Return the part's MIME headers.
pub fn Part::headers(self : Part) -> PartHeaders {
  self.headers
}

///|
/// Return the `Content-Type` of the part, if present.
pub fn Part::content_type(self : Part) -> String? {
  self.headers.get("Content-Type")
}

///|
/// Extract `(name, filename?)` from the `Content-Disposition` header.
pub fn Part::form_name(self : Part) -> (String, String?) {
  let cd = self.headers.get("Content-Disposition").unwrap_or("")
  split_content_disposition(cd)
}

///|
/// Read the next body chunk (up to `max_len` bytes).
///
/// Returns `None` when the boundary delimiter has been reached or the
/// source is exhausted.
async fn Part::read_chunk(
  self : Part,
  max_len? : Int = stream_chunk_size,
) -> Bytes? {
  guard self.body_eof is false else { return None }

  // Scan for the boundary delimiter
  let data = self.buf.to_bytes()
  match data[:].find(self.delimiter[:]) {
    Some(pos) => {
      // Trim trailing CRLF before the boundary
      let body_end = if pos >= 2 &&
        data[pos - 2] == b'\r' &&
        data[pos - 1] == b'\n' {
        pos - 2
      } else if pos >= 1 && data[pos - 1] == b'\n' {
        pos - 1
      } else {
        pos
      }

      self.body_eof = true

      // Keep bytes after boundary for take_remaining()
      let after = pos + self.delimiter.length()
      let remaining = @buffer.Buffer::Buffer()
      if after < data.length() {
        remaining.write_bytes(data[after:].to_owned())
      }
      self.buf = remaining

      if body_end > 0 {
        Some(data[0:body_end].to_owned())
      } else {
        Some(b"")
      }
    }
    None => {
      // Boundary not found — keep lookbehind zone, emit the rest
      let keep = self.delimiter.length() + 2
      if data.length() > keep {
        let emit_end = data.length() - keep
        let chunk = data[0:emit_end].to_owned()
        let new_buf = @buffer.Buffer::Buffer()
        new_buf.write_bytes(data[emit_end:].to_owned())
        self.buf = new_buf
        Some(chunk)
      } else {
        // Not enough data — read more from source
        match self.source.read_some(max_len~) {
          Some(chunk) => {
            self.buf.write_bytes(chunk)
            // Recurse via re-calling with the updated buffer
            // We need to try again with the larger buffer
            Part::read_chunk_retry(self, max_len~)
          }
          None => {
            // Source exhausted — emit whatever remains
            let chunk = self.buf.to_bytes()
            self.body_eof = true
            self.buf = @buffer.Buffer::Buffer()
            if chunk.length() > 0 {
              Some(chunk)
            } else {
              None
            }
          }
        }
      }
    }
  }
}

///|
/// Internal helper: retry boundary scan after reading more data.
fn Part::read_chunk_retry(
  self : Part,
  max_len? : Int = stream_chunk_size,
) -> Bytes? {
  ignore(max_len)
  let data = self.buf.to_bytes()
  match data[:].find(self.delimiter[:]) {
    Some(pos) => {
      let body_end = if pos >= 2 &&
        data[pos - 2] == b'\r' &&
        data[pos - 1] == b'\n' {
        pos - 2
      } else if pos >= 1 && data[pos - 1] == b'\n' {
        pos - 1
      } else {
        pos
      }
      self.body_eof = true
      let after = pos + self.delimiter.length()
      let remaining = @buffer.Buffer::Buffer()
      if after < data.length() {
        remaining.write_bytes(data[after:].to_owned())
      }
      self.buf = remaining
      if body_end > 0 {
        Some(data[0:body_end].to_owned())
      } else {
        Some(b"")
      }
    }
    None => {
      let keep = self.delimiter.length() + 2
      if data.length() > keep {
        let emit_end = data.length() - keep
        let chunk = data[0:emit_end].to_owned()
        let new_buf = @buffer.Buffer::Buffer()
        new_buf.write_bytes(data[emit_end:].to_owned())
        self.buf = new_buf
        Some(chunk)
      } else {
        None
      }
    }
  }
}

///|
/// Return leftover bytes after the boundary delimiter.
///
/// Callers should pass these to `MultipartReader` after consuming
/// the part so the next boundary line and headers can be found.
fn Part::take_remaining(self : Part) -> Bytes {
  self.buf.to_bytes()
}

///|
/// Metadata for a single uploaded file, plus its content.
/// Fields mirror Go's `mime/multipart.FileHeader`.
pub(all) struct FileHeader {
  /// Original filename from the `Content-Disposition` header.
  filename : String
  /// Uncompressed size in bytes.
  size : Int64
  /// MIME type from the part header, e.g. `"image/png"`.
  content_type : String?
  /// Raw MIME part headers.
  header : PartHeaders
  /// Where the file content lives.
  mut backend : FileBackend
}

///|
/// Where the uploaded file content lives.
enum FileBackend {
  Memory(Bytes)
  Disk(String) // path to temporary file
  External // handled by a custom writer, no local copy
}

///|
/// Read the entire file content as `Bytes`.
///
/// * For files that fit in memory: returns immediately.
/// * For files spilled to disk: reads from the temp file.
/// * For External files: returns empty — file was streamed to a custom writer.
///
/// Must be called from an `async` context.
pub async fn FileHeader::bytes(self : FileHeader) -> Bytes {
  match self.backend {
    Memory(b) => b
    Disk(path) => @fs.read_file(path).binary()
    External => b""
  }
}

///|
/// Return the file path for on-disk files, or `None` for in-memory/External.
pub fn FileHeader::path(self : FileHeader) -> String? {
  match self.backend {
    Disk(path) => Some(path)
    _ => None
  }
}

///|
/// Open a reader for the file content.
///
/// * Memory: returns a reader backed by the in-memory bytes.
/// * Disk: reads the temp file and returns a memory-backed reader.
/// * External: returns an empty reader — file was streamed to a custom writer.
pub async fn FileHeader::open(self : FileHeader) -> @io.MemoryReader {
  let data = match self.backend {
    Memory(b) => b
    Disk(path) => @fs.read_file(path).binary()
    External => b""
  }
  @io.MemoryReader() <| w => { w.write(data) }
}

// ---------------------------------------------------------------------------
// Internal form container
// ---------------------------------------------------------------------------

///|
/// Accumulator for a parsed multipart form.
/// Holds both regular fields (via `Values`) and file uploads.
struct MultipartForm {
  values : Values
  files : Map[String, Array[FileHeader]]
}

///|
fn MultipartForm::new() -> MultipartForm {
  { values: Values::new(), files: Map([]) }
}

///|
fn MultipartForm::field_value(self : MultipartForm, key : String) -> String? {
  self.values.get(key)
}

///|
fn MultipartForm::file_of(self : MultipartForm, key : String) -> FileHeader? {
  match self.files.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

///|
fn MultipartForm::files_of(
  self : MultipartForm,
  key : String,
) -> Array[FileHeader] {
  self.files.get(key).unwrap_or([])
}

///|
/// Remove every temporary disk file held by this form.
/// Safe to call when no disk files exist (no-op).
/// Does NOT remove External files (belong to the caller).
async fn MultipartForm::cleanup(self : MultipartForm) -> Unit {
  for _, file_arr in self.files {
    for file in file_arr {
      match file.backend {
        Disk(path) => @fs.remove(path) catch { _ => () }
        Memory(_) | External => ()
      }
    }
  }
}

// ============================================================================
// Parsing helpers
// ============================================================================

// -- boundary extraction -----------------------------------------------

///|
/// Extract the boundary string from a `Content-Type` header value.
///
/// ## Examples
/// ```
/// "multipart/form-data; boundary=----WebKit"  →  "----WebKit"
/// "multipart/form-data; boundary=\"--abc\""   →  "--abc"
/// "multipart/form-data; charset=utf-8; boundary=foo" → "foo"
/// ```
///
/// ## How it works
///
/// 1. Do a case‑insensitive search for `"boundary="` in the header value
///    (using a lowercased copy).  RFC 2046 says the parameter name is
///    case‑insensitive.
///
/// 2. Extract the value portion **from the original string** so the
///    boundary itself retains its original case.  RFC 2046 §5.1.1 says
///    boundary values ARE case‑sensitive.
///
/// 3. Peel off optional surrounding double‑quotes and trailing `;`
///    / whitespace via a functional `for` loop with `continue`/`break`.
fn boundary_from(content_type : String) -> String raise {
  let lower = content_type.to_lower()
  let prefix = "boundary="

  // Find "boundary=" position (case‑insensitive, via lowercased copy)
  let bp_pos = lower.find(prefix)
  guard bp_pos is Some(pos) else { raise MultipartError::MissingBoundary }

  let rest = content_type[pos + prefix.length():]
  // Quoted: value between quotes is the pure boundary.
  // Unquoted: trim whitespace,  ';' if present.
  match rest {
    [] => raise MultipartError::MissingBoundary
    ['"', .. inner, '"'] => inner.to_owned()
    _ => rest.trim(chars="; ").to_owned()
  }
}

// -- byte-level primitives ---------------------------------------------

///|
/// Advance one line from `data`.
///
/// Returns `Some((line, rest))` where `line` is the content before the
/// Decode bytes as a UTF-8 string.
fn to_utf8_string(data : BytesView) -> String {
  @utf8.decode_lossy(data.to_owned())
}

// -- part header parsing -----------------------------------------------

///|
/// Parse MIME part headers from `data`.
///
/// Returns `(headers, rest)` where `rest` is the bytes immediately
/// after the blank line that terminates the headers (i.e. the body).
fn read_part_headers(data : BytesView) -> (PartHeaders, BytesView) raise {
  let headers = PartHeaders::new()

  for rest = data {
    match rest {
      [.. b"\r\n", .. rest] | [.. b"\n", .. rest] => return (headers, rest)
      _ => {
        let (line_end, skip) = match rest.find(b"\r\n") {
          Some(pos) => (pos, 2)
          None =>
            match rest.find(b"\n") {
              Some(pos) => (pos, 1)
              None =>
                raise MultipartError::MalformedBody("part header: no CRLF")
            }
        }

        let line_str = to_utf8_string(rest[:line_end])
        guard line_str.find(":") is Some(colon) else {
          raise MultipartError::MalformedBody("part header: \{line_str}")
        }

        let key = line_str[:colon].trim().to_owned()
        let value = line_str[colon + 1:].trim().to_owned()
        headers.set(key, value)
        continue rest[line_end + skip:]
      }
    }
  } nobreak {
    raise MultipartError::MalformedBody("no blank line found")
  }
}

///|
/// Split a `Content-Disposition` value into `(name, filename?)`.
///
/// ## Example
/// ```
/// "form-data; name=\"field1\"; filename=\"doc.txt\"" → ("field1", Some("doc.txt"))
/// ```
fn split_content_disposition(cd_value : String) -> (String, String?) {
  let mut name : String? = None
  let mut filename : String? = None
  for part in cd_value.split(";") {
    let trimmed = part.trim()
    guard !trimmed.has_prefix("name=") else {
      name = Some(unquote_mime_value(trimmed["name=".length():].to_owned()))
      continue
    }
    guard !trimmed.has_prefix("filename=") else {
      filename = Some(
        unquote_mime_value(trimmed["filename=".length():].to_owned()),
      )
    }
  }
  (name.unwrap_or(""), filename)
}

///|
/// Strip surrounding double quotes from a MIME parameter value.
///
/// ## Example
/// `"\"hello\""` → `"hello"`    `"plain"` → `"plain"`
fn unquote_mime_value(raw : String) -> String {
  let s = raw.trim()
  guard s.length() >= 2 && s[0] == '"' && s[s.length() - 1] == '"' else {
    return s.to_owned()
  }
  s[1:s.length() - 1].to_owned()
}
// -- random helpers ----------------------------------------------------

///|
/// Generate a random hex string of `n` digits.
fn random_hex(n : Int) -> String {
  let r = @random.Rand::new()
  let hex = "0123456789abcdef"
  let buf = @buffer.Buffer::Buffer()
  for _ in 0..<n {
    buf.write_byte(hex[r.int(limit=16)].to_byte())
  }
  buf.to_bytes().to_unchecked_string()
}

// ============================================================================
// Main entry point
// ============================================================================

// ============================================================================
// Streaming multipart reader
// ============================================================================

///|
/// Chunk size for streaming reads (8 KiB).
let stream_chunk_size : Int = 8192

///|
/// Streaming multipart reader — yields `Part` values one at a time.
///
/// The caller passes leftover bytes from each Part back via
/// `store_remaining` so the reader can find the next boundary line
/// and part headers.
priv struct MultipartReader {
  source : &@io.Reader
  delimiter : Bytes // "--boundary"
  final_delimiter : Bytes // "--boundary--"
  mut initial_buf : @buffer.Buffer // carry-over bytes from previous part
  mut preamble_skipped : Bool
  mut done : Bool
}

///|
fn MultipartReader::new(
  source : &@io.Reader,
  boundary : String,
) -> MultipartReader {
  let delim = b"--" + @utf8.encode(boundary)
  {
    source,
    delimiter: delim,
    final_delimiter: b"--" + @utf8.encode(boundary) + b"--",
    initial_buf: @buffer.Buffer::Buffer(),
    preamble_skipped: false,
    done: false,
  }
}

///|
/// Produce the next `Part` from the stream.
///
/// The first call skips any preamble bytes and reads the initial
/// boundary line.  Subsequent calls consume the carry‑over bytes
/// stashed via `store_remaining`.
///
/// Returns `None` when the final delimiter is consumed.
async fn MultipartReader::next_part(self : MultipartReader) -> Part? {
  guard self.done is false else { return None }

  // Build a scan buffer from any carry-over bytes.
  let mut scan_buf = @buffer.Buffer::Buffer()
  if self.initial_buf.length() > 0 {
    scan_buf.write_bytes(self.initial_buf.to_bytes())
    self.initial_buf = @buffer.Buffer::Buffer()
  }

  // -- Preamble skip (first call only) --------------------------------
  if self.preamble_skipped is false {
    // Read until we find the first boundary delimiter, skip preamble.
    while true {
      let data = scan_buf.to_bytes()
      match data[:].find(self.delimiter[:]) {
        Some(pos) => {
          // We have "--boundary" at pos. Strip preamble bytes.
          let new_buf = @buffer.Buffer::Buffer()
          new_buf.write_bytes(data[pos:].to_owned())
          scan_buf = new_buf
          break
        }
        None => {
          // Shrink to lookbehind window so buffer does not grow unbounded.
          let data = scan_buf.to_bytes()
          let keep = self.delimiter.length()
          if data.length() > keep {
            let new_buf = @buffer.Buffer::Buffer()
            new_buf.write_bytes(data[data.length() - keep:].to_owned())
            scan_buf = new_buf
          }
          match self.source.read_some(max_len=stream_chunk_size) {
            Some(chunk) => scan_buf.write_bytes(chunk)
            None => return None
          }
        }
      }
    }
    // Now scan_buf starts with 🠞 --boundary[suffix]\r\n...
    // Skip the boundary line itself.
    self.preamble_skipped = true
    scan_buf = match self.skip_boundary_line(scan_buf) {
      Some(buf) => buf
      None => return None
    }
  } else {
    // -- Subsequent calls: carry-over already has \r\nHeaders...  ----------
    let data = scan_buf.to_bytes()
    // Check for final delimiter tail.
    if data[:].has_prefix(b"--\r\n") || data[:].has_prefix(b"--\n") {
      self.done = true
      return None
    }
    // Skip the CRLF left over from the previous boundary line.
    if data[:].has_prefix(b"\r\n") {
      let new_buf = @buffer.Buffer::Buffer()
      if data.length() > 2 {
        new_buf.write_bytes(data[2:].to_owned())
      }
      scan_buf = new_buf
    } else if data[:].has_prefix(b"\n") {
      let new_buf = @buffer.Buffer::Buffer()
      if data.length() > 1 {
        new_buf.write_bytes(data[1:].to_owned())
      }
      scan_buf = new_buf
    } else {
      raise MultipartError::MalformedBody("expected line ending after boundary")
    }
  }

  // -- Read part headers ------------------------------------------------
  let mut part_headers = PartHeaders::new()
  let part_body_buf = @buffer.Buffer::Buffer()
  while true {
    let data = scan_buf.to_bytes()
    // Check for blank line (end of headers).
    let has_blank = data[:].find(b"\r\n\r\n") is Some(_) ||
      data[:].find(b"\n\n") is Some(_)
    if has_blank {
      let (headers, rest) = read_part_headers(data[:])
      part_headers = headers
      if rest.length() > 0 {
        part_body_buf.write_bytes(rest.to_owned())
      }
      break
    }
    match self.source.read_some(max_len=stream_chunk_size) {
      Some(chunk) => scan_buf.write_bytes(chunk)
      None => raise MultipartError::MalformedBody("incomplete headers")
    }
  }
  Some(Part::{
    source: self.source,
    delimiter: self.delimiter[:].to_owned(),
    headers: part_headers,
    buf: part_body_buf,
    body_eof: false,
  })
}

///|
/// Read all parts into a `MultipartForm`.
///
/// Iterates through every part, streams file bodies into `BodyWriter`
/// (spilling large files to disk), and collects form fields.
///
/// When a `writers` map is provided and a file part's field name matches
/// a key, the part body is streamed directly to that writer instead of
/// being buffered in memory or a temp file. The resulting `FileHeader`
/// will have an `External` backend.
async fn MultipartReader::read_form(
  self : MultipartReader,
  max_memory : Int64,
  temp_dir : String,
  writers? : Map[String, FileWriter] = Map([]),
) -> MultipartForm {
  let form = MultipartForm::new()
  while true {
    match self.next_part() {
      Some(part) => {
        let (name, filename) = part.form_name()
        guard name.length() > 0 else { continue }
        match filename {
          Some(fname) if fname.length() > 0 => {
            let (file_header, _backend) = match writers.get(name) {
              Some(writer) => {
                // Stream directly to the custom writer — no buffering.
                let mut total : Int64 = 0
                while true {
                  match part.read_chunk() {
                    Some(chunk) => {
                      total = total + chunk.length().to_int64()
                      @io.Writer::write(writer, chunk)
                    }
                    None => break
                  }
                }
                Closer::close(writer)
                let fh = FileHeader::{
                  filename: fname,
                  size: total,
                  content_type: part.content_type(),
                  header: part.headers(),
                  backend: External,
                }
                (fh, External)
              }
              None => {
                // Default: buffer/spill via BodyWriter.
                let bodyWriter = BodyWriter::new(max_memory, temp_dir)
                while true {
                  match part.read_chunk() {
                    Some(chunk) => @io.Writer::write(bodyWriter, chunk)
                    None => break
                  }
                }
                Closer::close(bodyWriter)
                let backend = if bodyWriter.disk_path.length() > 0 {
                  Disk(bodyWriter.disk_path)
                } else {
                  Memory(bodyWriter.buf.to_bytes())
                }
                let fh = FileHeader::{
                  filename: fname,
                  size: bodyWriter.total,
                  content_type: part.content_type(),
                  header: part.headers(),
                  backend,
                }
                (fh, backend)
              }
            }
            form.files.get_or_init(name, () => []).push(file_header)
            self.store_remaining(part.take_remaining())
          }
          _ => {
            let field_text = match part.read_chunk() {
              Some(chunk) => to_utf8_string(chunk[:])
              None => ""
            }
            form.values.0.get_or_init(name, () => []).push(field_text)
            self.store_remaining(part.take_remaining())
          }
        }
      }
      None => break
    }
  }
  form
}

///|
/// Stash leftover bytes from a Part so the next `next_part` call
/// can find the boundary line and headers.
fn MultipartReader::store_remaining(
  self : MultipartReader,
  remaining : Bytes,
) -> Unit {
  if remaining.length() > 0 {
    self.initial_buf.write_bytes(remaining)
  }
}

///|
/// Strip the boundary line from `scan_buf` and return the remaining
/// bytes (the part headers / body).  Returns `None` when the final
/// delimiter is encountered.
async fn MultipartReader::skip_boundary_line(
  self : MultipartReader,
  scan_buf : @buffer.Buffer,
) -> @buffer.Buffer? {
  let delim_len = self.delimiter.length()
  while true {
    let data = scan_buf.to_bytes()
    // Need enough bytes to identify the full boundary line.
    // Minimum: "--boundary\r\n"  or  "--boundary--\r\n"
    let need_len = self.final_delimiter.length() + 2
    if data.length() >= need_len {
      let after_delim = data[delim_len:]
      if after_delim.has_prefix(b"--\r\n") || after_delim.has_prefix(b"--\n") {
        self.done = true
        return None
      }
      if after_delim.has_prefix(b"\r\n") {
        let new_buf = @buffer.Buffer::Buffer()
        let after = delim_len + 2
        if after < data.length() {
          new_buf.write_bytes(data[after:].to_owned())
        }
        return Some(new_buf)
      } else if after_delim.has_prefix(b"\n") {
        let new_buf = @buffer.Buffer::Buffer()
        let after = delim_len + 1
        if after < data.length() {
          new_buf.write_bytes(data[after:].to_owned())
        }
        return Some(new_buf)
      } else {
        raise MultipartError::MalformedBody("unexpected boundary suffix")
      }
    }
    // Not enough data — read more.
    match self.source.read_some(max_len=stream_chunk_size) {
      Some(chunk) => scan_buf.write_bytes(chunk)
      None => raise MultipartError::MalformedBody("incomplete boundary line")
    }
  }
  raise MultipartError::MalformedBody("incomplete boundary line")
}

///|
/// Match body data to memory or disk.  Spills when total exceeds
/// `max_memory`.  Stream chunks via `write()`, then call `close()`.
/// Implements `WriterCloser` so it can be used both as default writer
/// and as a custom writer target.
priv struct BodyWriter {
  mut buf : @buffer.Buffer
  mut total : Int64
  mut disk_path : String
  mut disk_file : @fs.File?
  max_memory : Int64
  temp_dir : String
}

///|
fn BodyWriter::new(max_memory : Int64, temp_dir : String) -> BodyWriter {
  {
    buf: @buffer.Buffer::Buffer(),
    total: 0,
    disk_path: "",
    disk_file: None,
    max_memory,
    temp_dir,
  }
}

///|
/// Implement `@io.Writer` via `write_once`. The default `write(&Data)`
/// converts to bytes inside the @io package and calls back to us here.
impl @io.Writer for BodyWriter with fn write_once(
  self : BodyWriter,
  data : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int {
  let chunk = data[offset:offset + len].to_owned()
  let inc = chunk.length().to_int64()
  self.total = self.total + inc

  if self.disk_path.length() > 0 || self.total > self.max_memory {
    if self.disk_path.length() == 0 {
      let path = "\{self.temp_dir}/pony-multipart-\{random_hex(8)}"
      self.disk_file = Some(
        @fs.create(path) catch {
          _ => {
            self.buf.write_bytes(chunk)
            return len
          }
        },
      )
      self.disk_file.unwrap().write(self.buf.to_bytes()[:]) |> ignore
      self.buf = @buffer.Buffer::Buffer()
      self.disk_path = path
    }
    match self.disk_file {
      Some(f) => f.write(chunk[:]) |> ignore
      _ => ()
    }
  } else {
    self.buf.write_bytes(chunk)
  }
  len
}

///|
/// Close the underlying file handle, if any.
impl Closer for BodyWriter with fn close(self : BodyWriter) -> Unit {
  match self.disk_file {
    Some(f) => f.close()
    _ => ()
  }
}
