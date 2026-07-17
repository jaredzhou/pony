// multipart_wbtest.mbt — whitebox tests for multipart parsing
//
// Tested against:
//   RFC 7578 §4.2   Multipart body parts
//   RFC 7578 §4.3   Content-Disposition header
//   RFC 7578 §4.4   Content-Type boundary parameter
//   RFC 2046 §5.1   Multipart Media Type — boundary delimiter syntax
//   RFC 2183 §2     Content-Disposition field — filename parameter

// ============================================================================
// Spec: RFC 2046 §5.1 — boundary delimiter
// ============================================================================
// The boundary delimiter line consists of two hyphens followed by the
// boundary parameter value. The final delimiter has two additional hyphens.
//   --boundary         → part separator
//   --boundary--       → end marker

///|
/// Spec: [RFC 2046 §5.1] Quoted boundary values are properly unwrapped.
test "boundary_from unwraps quoted boundary" {
  let result = boundary_from("multipart/form-data; boundary=\"----foo\"")
  @debug.assert_eq(result, "----foo")
}

///|
/// Spec: [RFC 2046 §5.1] Unquoted boundary values are extracted as-is.
test "boundary_from handles unquoted boundary" {
  let result = boundary_from("multipart/form-data; boundary=----bar")
  @debug.assert_eq(result, "----bar")
}

// ============================================================================
// Spec: RFC 2046 §5.1 — byte-level primitives
// ============================================================================

///|
/// Spec: [RFC 2046 §5.1] A part boundary marker `--boundary` must be
/// locatable within the body bytes.
test "BytesView::find locates substring" {
  let data = b"abc---def---ghi"
  let pos = data[:].find(b"---")
  @debug.assert_eq(pos, Some(3))
}

///|
/// Spec: [RFC 2046 §5.1] A second boundary marker should be found after
/// skipping past the first one.
test "BytesView::find after start offset" {
  let data = b"abc---def---ghi"
  let pos = data[4:].find(b"---")
  match pos {
    Some(p) => @debug.assert_eq(p + 4, 9)
    None => @debug.assert_eq("not found", "")
  }
}

// ============================================================================
// Spec: RFC 2183 §2, RFC 7578 §4.3 — Content-Disposition parameters
// ============================================================================
// MIME parameters in Content-Disposition may be quoted or unquoted.
//   Content-Disposition: form-data; name="field1"
//   Content-Disposition: form-data; name="file1"; filename="test.txt"

///|
/// Spec: [RFC 2183 §2] Quoted parameter values are unescaped.
test "unquote_mime_value strips surrounding quotes" {
  let result = unquote_mime_value("\"value\"")
  @debug.assert_eq(result, "value")
}

///|
/// Spec: [RFC 2183 §2] Unquoted parameter values are left alone.
test "unquote_mime_value passes through unquoted text" {
  let result = unquote_mime_value("plain")
  @debug.assert_eq(result, "plain")
}

///|
/// Spec: [RFC 7578 §4.3] The `name` parameter identifies the form field.
test "split_content_disposition extracts name parameter" {
  let (name, filename) = split_content_disposition("form-data; name=\"field1\"")
  @debug.assert_eq(name, "field1")
  @debug.assert_eq(filename is None, true)
}

///|
/// Spec: [RFC 7578 §4.3] The `filename` parameter (when present) identifies
/// the original file name.
test "split_content_disposition extracts filename parameter" {
  let (name, filename) = split_content_disposition(
    "form-data; name=\"file1\"; filename=\"test.txt\"",
  )
  @debug.assert_eq(name, "file1")
  match filename {
    Some(f) => @debug.assert_eq(f, "test.txt")
    None => @debug.assert_eq("missing", "filename")
  }
}

// ============================================================================
// Spec: RFC 7578 §4.2 — MultipartForm structure
// ============================================================================
// A parsed multipart form contains regular form fields (Values) and
// file uploads (UploadedFile entries), keyed by their `name`.

///|
/// Spec: [RFC 7578 §4.2] An empty form has no values and no files.
test "MultipartForm new is empty" {
  let form = MultipartForm::new()
  @debug.assert_eq(form.field_value("any") is None, true)
  @debug.assert_eq(form.file_of("any") is None, true)
  @debug.assert_eq(form.files_of("any").length(), 0)
}

// ============================================================================
// Part struct whitebox tests
// ============================================================================

///|
/// Construct a Part with a given Content-Disposition header and verify
/// form_name extracts the name and optional filename.
test "Part form_name extracts name and filename" {
  let headers = PartHeaders::new()
  headers.set(
    "Content-Disposition", "form-data; name=\"file1\"; filename=\"test.txt\"",
  )
  headers.set("Content-Type", "text/plain")
  let reader = @io.MemoryReader() <| _ => {  }
  let part = Part::{
    source: reader,
    delimiter: b"--boundary",
    headers,
    buf: @buffer.Buffer::Buffer(),
    body_eof: false,
  }
  let (name, filename) = part.form_name()
  @debug.assert_eq(name, "file1")
  match filename {
    Some(f) => @debug.assert_eq(f, "test.txt")
    None => @debug.assert_eq("missing", "filename")
  }
}

///|
/// Verify Part::content_type returns the Content-Type header value.
test "Part content_type" {
  let headers = PartHeaders::new()
  headers.set("Content-Type", "image/png")
  let reader = @io.MemoryReader() <| _ => {  }
  let part = Part::{
    source: reader,
    delimiter: b"--boundary",
    headers,
    buf: @buffer.Buffer::Buffer(),
    body_eof: false,
  }
  @debug.assert_eq(part.content_type(), Some("image/png"))
}

///|
/// Verify Part::content_type returns None when no Content-Type header.
test "Part content_type none" {
  let headers = PartHeaders::new()
  let reader = @io.MemoryReader() <| _ => {  }
  let part = Part::{
    source: reader,
    delimiter: b"--boundary",
    headers,
    buf: @buffer.Buffer::Buffer(),
    body_eof: false,
  }
  @debug.assert_eq(part.content_type() is None, true)
}

///|
/// Verify Part::headers returns the part's MIME headers.
test "Part headers" {
  let headers = PartHeaders::new()
  headers.set("X-Custom", "value")
  let reader = @io.MemoryReader() <| _ => {  }
  let part = Part::{
    source: reader,
    delimiter: b"--boundary",
    headers,
    buf: @buffer.Buffer::Buffer(),
    body_eof: false,
  }
  @debug.assert_eq(part.headers().get("x-custom"), Some("value"))
}

// ============================================================================
// MultipartReader streaming whitebox tests
// ============================================================================

///|
/// Build a complete multipart body with the given boundary and one text part.
fn build_multipart_body(
  boundary : String,
  name : String,
  value : String,
) -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  buf.write_string_utf8("--\{boundary}\r\n")
  buf.write_string_utf8("Content-Disposition: form-data; name=\"\{name}\"\r\n")
  buf.write_string_utf8("\r\n")
  buf.write_string_utf8(value)
  buf.write_string_utf8("\r\n--\{boundary}--\r\n")
  buf.to_bytes()
}

///|
/// Streaming: parse a single text field part through MultipartReader.
async test "MultipartReader yields Part with text field" {
  let boundary = "----boundary"
  let body = build_multipart_body(boundary, "username", "alice")
  let reader = @io.MemoryReader() <| w => { w.write(body) }
  let mr = MultipartReader::new(reader, boundary)
  match mr.next_part() {
    Some(part) => {
      let (name, filename) = part.form_name()
      @debug.assert_eq(name, "username")
      @debug.assert_eq(filename is None, true)
      match part.read_chunk() {
        Some(chunk) => @debug.assert_eq(to_utf8_string(chunk[:]), "alice")
        None => @debug.assert_eq("no chunk", "expected chunk")
      }
      @debug.assert_eq(part.read_chunk() is None, true)
    }
    None => @debug.assert_eq("no part", "expected part")
  }
}

///|
/// Streaming: parse a file part with filename through MultipartReader.
async test "MultipartReader yields Part with file field" {
  let boundary = "----fileboundary"
  let buf = @buffer.Buffer::Buffer()
  buf.write_string_utf8("--\{boundary}\r\n")
  buf.write_string_utf8(
    "Content-Disposition: form-data; name=\"avatar\"; filename=\"photo.png\"\r\n",
  )
  buf.write_string_utf8("Content-Type: image/png\r\n")
  buf.write_string_utf8("\r\n")
  buf.write_bytes(b"\x00\x01\x02\x03")
  buf.write_string_utf8("\r\n--\{boundary}--\r\n")
  let body = buf.to_bytes()
  let reader = @io.MemoryReader() <| w => { w.write(body) }
  let mr = MultipartReader::new(reader, boundary)
  match mr.next_part() {
    Some(part) => {
      let (name, filename) = part.form_name()
      @debug.assert_eq(name, "avatar")
      match filename {
        Some(f) => @debug.assert_eq(f, "photo.png")
        None => @debug.assert_eq("missing", "filename")
      }
      @debug.assert_eq(part.content_type(), Some("image/png"))
      match part.read_chunk() {
        Some(chunk) => @debug.assert_eq(chunk, b"\x00\x01\x02\x03")
        None => @debug.assert_eq("no chunk", "expected chunk")
      }
      @debug.assert_eq(part.read_chunk() is None, true)
    }
    None => @debug.assert_eq("no part", "expected part")
  }
}

///|
/// Streaming: MultipartReader returns None after final boundary.
async test "MultipartReader returns None after final boundary" {
  let boundary = "----endboundary"
  let body = build_multipart_body(boundary, "f", "v")
  let reader = @io.MemoryReader() <| w => { w.write(body) }
  let mr = MultipartReader::new(reader, boundary)
  let part1 = mr.next_part()
  @debug.assert_eq(part1 is Some(_), true)
  let part1 = part1.unwrap()
  // Drain the part so store_remaining gets boundary tail
  part1.read_chunk() |> ignore
  part1.read_chunk() |> ignore
  mr.store_remaining(part1.take_remaining())
  let part2 = mr.next_part()
  @debug.assert_eq(part2 is None, true)
}

// ============================================================================
// readutil test (existing)
// ============================================================================

///|
async test "readutil test" {
  let reader = @io.MemoryReader() <| w => { w.write("\r\n") }
  @debug.assert_eq(reader.read_until("\r\n"), Some(""))
}
