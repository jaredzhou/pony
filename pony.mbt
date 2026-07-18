///|
pub suberror RouterError {
  InvalidPattern(http_method~ : String, path~ : String, reason~ : String)
} derive(Debug, ToJson)

///|
pub impl Show for RouterError with fn to_string(self) {
  match self {
    InvalidPattern(http_method~, path~, reason~) =>
      "InvalidRoute(\{http_method} \{path}): \{reason}"
  }
}

///|
/// Unified error type for context accessor methods.
/// Raised by `param`, `query`, `form`, `header`, `form_file`,
/// `get_ext`, and `wildcard` when the requested value is missing,
/// or (`InvalidValue`) when it cannot be parsed into the requested type.
/// Also used for generic request-level errors in handlers.
pub(all) suberror PonyError {
  MissingParam(String)
  MissingQuery(String)
  MissingForm(String)
  MissingHeader(String)
  MissingExt(String)
  ExtDecodeError(String, String)
  MissingFormFile(String)
  InvalidValue(String, String)
  InvalidArgument(String)
  NotFound(String)
  PermissionDenied(String)
} derive(Debug, ToJson)

///|
pub impl ToApiError for PonyError with fn to_api_error(self : PonyError) -> ApiError {
  match self {
    PonyError::MissingParam(name) =>
      ApiError::new(invalid_argument, "missing param: \{name}")
    PonyError::MissingQuery(key) =>
      ApiError::new(invalid_argument, "missing query: \{key}")
    PonyError::MissingForm(key) =>
      ApiError::new(invalid_argument, "missing form field: \{key}")
    PonyError::MissingHeader(key) =>
      ApiError::new(unauthenticated, "missing header: \{key}")
    PonyError::MissingExt(key) =>
      ApiError::new(internal, "missing extension: \{key}")
    PonyError::ExtDecodeError(key, msg) =>
      ApiError::new(internal, "extension decode error: \{key} - \{msg}")
    PonyError::MissingFormFile(key) =>
      ApiError::new(invalid_argument, "missing form file: \{key}")
    PonyError::InvalidValue(key, value) =>
      ApiError::new(invalid_argument, "invalid value for \{key}: \{value}")
    PonyError::InvalidArgument(msg) => ApiError::new(invalid_argument, msg)
    PonyError::NotFound(msg) => ApiError::new(not_found, msg)
    PonyError::PermissionDenied(msg) => ApiError::new(permission_denied, msg)
  }
}

///|
pub(all) enum HttpMethod {
  Get
  Head
  Post
  Put
  Delete
  Connect
  Options
  Trace
  Patch
  Any // 匹配任意方法
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub impl Show for HttpMethod with fn output(self, logger) {
  let name = match self {
    HttpMethod::Get => "Get"
    HttpMethod::Head => "Head"
    HttpMethod::Post => "Post"
    HttpMethod::Put => "Put"
    HttpMethod::Delete => "Delete"
    HttpMethod::Connect => "Connect"
    HttpMethod::Options => "Options"
    HttpMethod::Trace => "Trace"
    HttpMethod::Patch => "Patch"
    HttpMethod::Any => "Any"
  }
  logger.write_string(name)
}

///|
pub fn HttpMethod::from_std(meth : @http.RequestMethod) -> HttpMethod {
  match meth {
    @http.Get => HttpMethod::Get
    @http.Head => HttpMethod::Head
    @http.Post => HttpMethod::Post
    @http.Put => HttpMethod::Put
    @http.Delete => HttpMethod::Delete
    @http.Connect => HttpMethod::Connect
    @http.Options => HttpMethod::Options
    @http.Trace => HttpMethod::Trace
    @http.Patch => HttpMethod::Patch
  }
}

///|
struct ParamKV(String, String)

///|
pub(all) struct Values(Map[String, Array[String]])

///|
pub fn Values::new() -> Values {
  Values(Map([]))
}

///|
pub fn Values::get(self : Values, key : String) -> String? {
  let Values(m) = self
  match m.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

///|
pub fn Values::get_all(self : Values, key : String) -> Array[String] {
  let Values(m) = self
  m.get(key).unwrap_or([])
}

///|
/// Case-insensitive HTTP headers with lowercased keys.
pub(all) struct HttpHeaders(Map[String, String])

///|
pub fn HttpHeaders::new() -> HttpHeaders {
  HttpHeaders(Map([]))
}

///|
pub fn HttpHeaders::from_map(m : Map[String, String]) -> HttpHeaders {
  HttpHeaders(m)
}

///|
/// Return the value for `key` (case-insensitive lookup), or `None`.
pub fn HttpHeaders::get(self : HttpHeaders, key : String) -> String? {
  let HttpHeaders(m) = self
  m.get(key.to_lower())
}

///|
/// Set the value for `key`, lowercasing the key first.
pub fn HttpHeaders::set(
  self : HttpHeaders,
  key : String,
  value : String,
) -> Unit {
  let HttpHeaders(m) = self
  m[key.to_lower()] = value
}

///|
/// Return the underlying `Map[String, String]`.
pub fn HttpHeaders::to_map(self : HttpHeaders) -> Map[String, String] {
  let HttpHeaders(m) = self
  m
}

///|
/// Merge entries from `other` into `self`, lowercasing keys.
pub fn HttpHeaders::merge_in_place(
  self : HttpHeaders,
  other : Map[String, String],
) -> Unit {
  let HttpHeaders(m) = self
  for k, v in other {
    m[k.to_lower()] = v
  }
}

///|
pub(all) struct Context {
  http_method : HttpMethod
  url_str : String
  url : @url.URL
  mut route_path : String
  req_headers : HttpHeaders
  resp_headers : HttpHeaders
  queries : Values
  mut form_values : Values?
  mut multipart_form : MultipartForm?
  exts : ExtStore
  mut path_params : Array[ParamKV]
  req_body : &@io.Reader
  resp_writer : @http.ServerConnection
}

///|
pub(all) struct ExtStore(Array[(String, @any.Any)])

///|
pub fn ExtStore::new() -> ExtStore {
  ExtStore([])
}

///|
fn ExtStore::find(self : ExtStore, key : String) -> Int? {
  let ExtStore(arr) = self
  for i = 0; i < arr.length(); i = i + 1 {
    let (existing, _) = arr[i]
    if existing == key {
      return Some(i)
    }
  }
  None
}

///|
fn[T] decode_from_any(key : String, v : @any.Any) -> T raise ExtError {
  v.to() catch {
    @any.TypeMismatch(expect~, actual~) =>
      raise ExtError::DecodeError(
        key~,
        msg="expected '\{expect.name()}' but found '\{actual.name()}'",
      )
  }
}

///|
pub fn[K, V] ExtStore::set(self : ExtStore, _marker : K, v : V) -> Unit {
  let ExtStore(arr) = self
  let val = @any.Any::of(v)
  let key = @any.Any::of(_marker).type_name()
  match self.find(key) {
    Some(i) => arr[i] = (key, val)
    None => arr.push((key, val))
  }
}

///|
pub fn[K, V] ExtStore::try_get(self : ExtStore, _marker : K) -> V? {
  let key = @any.Any::of(_marker).type_name()
  match self.find(key) {
    None => None
    Some(i) => {
      let ExtStore(arr) = self
      let (_, v) = arr[i]
      try decode_from_any(key, v) catch {
        _ => None
      } noraise {
        value => Some(value)
      }
    }
  }
}

///|
pub fn[K, V] ExtStore::get(self : ExtStore, _marker : K) -> V raise ExtError {
  let key = @any.Any::of(_marker).type_name()
  match self.find(key) {
    None => raise ExtError::Missing
    Some(i) => {
      let ExtStore(arr) = self
      let (_, v) = arr[i]
      decode_from_any(key, v)
    }
  }
}

///|
pub fn[K] ExtStore::remove(self : ExtStore, _marker : K) -> Unit {
  let key = @any.Any::of(_marker).type_name()
  match self.find(key) {
    None => ()
    Some(i) => {
      let ExtStore(arr) = self
      arr.remove(i) |> ignore
    }
  }
}

///|
pub fn[K, V] Context::set_ext(self : Context, _marker : K, v : V) -> Unit {
  self.exts.set(_marker, v)
}

///|
pub fn[K, V] Context::try_get_ext(self : Context, _marker : K) -> V? {
  self.exts.try_get(_marker)
}

///|
pub fn[K, V] Context::get_ext(self : Context, _marker : K) -> V raise PonyError {
  self.exts.get(_marker) catch {
    ExtError::Missing =>
      raise PonyError::MissingExt(@any.Any::of(_marker).type_name())
    ExtError::DecodeError(key~, msg~) =>
      raise PonyError::ExtDecodeError(key, msg)
  }
}

///|
pub fn[K] Context::remove_ext(self : Context, _marker : K) -> Unit {
  self.exts.remove(_marker)
}

///|
pub fn Context::try_param(self : Context, name : String) -> String? {
  for p in self.path_params {
    let ParamKV(k, v) = p
    if k == name {
      return Some(v)
    }
  }
  None
}

///|
pub fn[T : FromStr] Context::param(
  self : Context,
  name : String,
) -> T raise PonyError {
  match self.try_param(name) {
    Some(v) =>
      T::from_str(v) catch {
        _ => raise PonyError::InvalidValue(name, v)
      }
    None => raise PonyError::MissingParam(name)
  }
}

///|
pub fn Context::try_wildcard(self : Context) -> String? {
  self.try_param("*")
}

///|
pub fn Context::wildcard(self : Context) -> String raise PonyError {
  self.param("*")
}

///|
pub fn Context::try_query(self : Context, key : String) -> String? {
  self.queries.get(key)
}

///|
pub fn[T : FromStr] Context::query(
  self : Context,
  key : String,
) -> T raise PonyError {
  match self.try_query(key) {
    Some(v) =>
      T::from_str(v) catch {
        _ => raise PonyError::InvalidValue(key, v)
      }
    None => raise PonyError::MissingQuery(key)
  }
}

///|
pub async fn Context::try_form(self : Context, key : String) -> String? {
  // If multipart form was parsed, read regular fields from it.
  if self.multipart_form is Some(mf) {
    return mf.field_value(key)
  }
  // Fallback: application/x-www-form-urlencoded lazy parse.
  if self.form_values is None {
    let body_text = self.req_body.read_all().text()
    self.form_values = Some(parse_query(body_text))
  }
  self.form_values.unwrap().get(key)
}

///|
pub async fn[T : FromStr] Context::form(
  self : Context,
  key : String,
) -> T raise PonyError {
  match (self.try_form(key) catch { _ => None }) {
    Some(v) =>
      T::from_str(v) catch {
        _ => raise PonyError::InvalidValue(key, v)
      }
    None => raise PonyError::MissingForm(key)
  }
}

///|
pub async fn Context::parse_multipart_form(
  self : Context,
  max_memory? : Int64 = default_max_memory,
  writers? : Map[String, FileWriter] = Map([]),
) -> Unit {
  let content_type = self.try_header("content-type").unwrap_or("")
  let boundary = boundary_from(content_type)
  let mr = MultipartReader::new(self.req_body, boundary)
  let temp_dir = @fs.tmpdir(prefix="pony_")
  let form = mr.read_form(max_memory, temp_dir, writers~)
  self.multipart_form = Some(form)
}

///|
pub fn Context::try_form_file(self : Context, key : String) -> FileHeader? {
  match self.multipart_form {
    Some(mf) => mf.file_of(key)
    None => None
  }
}

///|
pub fn Context::form_file(
  self : Context,
  key : String,
) -> FileHeader raise PonyError {
  match self.multipart_form {
    Some(mf) =>
      match mf.file_of(key) {
        Some(fh) => fh
        None => raise PonyError::MissingFormFile(key)
      }
    None => raise PonyError::MissingFormFile(key)
  }
}

///|
pub fn Context::form_files(self : Context, key : String) -> Array[FileHeader] {
  match self.multipart_form {
    Some(mf) => mf.files_of(key)
    None => []
  }
}

///|
pub async fn Context::cleanup(self : Context) -> Unit {
  match self.multipart_form {
    Some(mf) => mf.cleanup()
    None => ()
  }
  self.multipart_form = None
}

///|
pub async fn[T : FromJson] Context::json(self : Context) -> T {
  @json.from_json(self.req_body.read_all().json())
}

///

///|
pub fn Context::try_header(self : Context, key : String) -> String? {
  self.req_headers.get(key)
}

///|
pub fn[T : FromStr] Context::header(
  self : Context,
  key : String,
) -> T raise PonyError {
  match self.try_header(key) {
    Some(v) =>
      T::from_str(v) catch {
        _ => raise PonyError::InvalidValue(key, v)
      }
    None => raise PonyError::MissingHeader(key)
  }
}

///|
pub fn Context::set_header(
  self : Context,
  key : String,
  value : String,
) -> Unit {
  self.resp_headers.set(key, value)
}

///|
async fn[T : ToJson] Context::reply(
  self : Context,
  result : Result[T, ApiError],
) -> Unit {
  let (http_status, body) = match result {
    Ok(v) => {
      let v = v.to_json().stringify()
      (200, v)
    }
    Err(s) => {
      let http_status = ApiError::to_http_status(s.code)
      let v = s.to_json().stringify()
      (http_status, v)
    }
  }
  let http_status_msg = status_text(http_status)
  self.resp_headers.merge_in_place({ "Content-Type": "application/json" })
  self.resp_writer
  ..send_response(
    http_status,
    http_status_msg,
    extra_headers=self.resp_headers.to_map(),
  )
  ..write(body)
  .end_response()
}

///|
pub async fn[T : ToJson] Context::reply_ok(self : Context, value : T) -> Unit {
  self.reply(Ok(value))
}

///|
pub async fn[T : ToApiError] Context::reply_error(
  self : Context,
  e : T,
) -> Unit {
  self.reply((Err(e.to_api_error()) : Result[Unit, ApiError]))
}

///|
pub async fn Context::write_text(
  self : Context,
  http_status : Int,
  msg? : String,
  text : String,
) -> Unit {
  let msg = match msg {
    Some(m) => m
    None => status_text(http_status)
  }
  self.resp_headers.merge_in_place({ "Content-Type": "text/plain" })
  self.resp_writer.send_response(
    http_status,
    msg,
    extra_headers=self.resp_headers.to_map(),
  )
  self.resp_writer.write(text)
  self.resp_writer.end_response()
}

///|
pub async fn[T : ToJson] Context::write_json(
  self : Context,
  http_status : Int,
  msg? : String,
  v : T,
) -> Unit {
  let body = v.to_json().stringify()
  let msg = match msg {
    Some(m) => m
    None => status_text(http_status)
  }
  self.resp_headers.merge_in_place({ "Content-Type": "application/json" })
  self.resp_writer
  ..send_response(http_status, msg, extra_headers=self.resp_headers.to_map())
  ..write(body)
  .end_response()
}

///|
pub fn Context::set_content_type(self : Context, ct : String) -> Unit {
  self.resp_headers.merge_in_place({ "Content-Type": ct })
}

///|
pub async fn Context::write_bytes(
  self : Context,
  http_status : Int,
  msg? : String,
  body : Bytes,
) -> Unit {
  let msg = match msg {
    Some(m) => m
    None => status_text(http_status)
  }
  self.resp_writer.send_response(
    http_status,
    msg,
    extra_headers=self.resp_headers.to_map(),
  )
  self.resp_writer.write(body)
  self.resp_writer.end_response()
}

///|
pub async fn Context::no_content(self : Context) -> Unit {
  let msg = status_text(204)
  self.resp_writer.send_response(
    204,
    msg,
    extra_headers=self.resp_headers.to_map(),
  )
  self.resp_writer.end_response()
}

///|
pub async fn Context::redirect(
  self : Context,
  url : String,
  http_status? : Int = 302,
  msg? : String,
) -> Unit {
  self.resp_headers.merge_in_place({ "Location": url })
  let msg = match msg {
    Some(m) => m
    None => status_text(http_status)
  }
  self.resp_writer.send_response(
    http_status,
    msg,
    extra_headers=self.resp_headers.to_map(),
  )
  self.resp_writer.end_response()
}

///|
pub impl Show for Context with fn to_string(self : Context) -> String {
  let sb = StringBuilder::new()
  sb
  ..write_string("Context(")
  ..write_string(self.http_method.to_string())
  ..write_string(" ")
  ..write_string(self.url_str)
  .write_string(")")
  for p in self.path_params {
    let ParamKV(k, v) = p
    sb..write_string(" ")..write_string(k)..write_string("=").write_string(v)
  }
  sb.to_string()
}

///|
pub impl Show for Context with fn output(self : Context, out : &Logger) -> Unit {
  out.write_string("Context(")
  out.write_string(self.http_method.to_string())
  out.write_string(" ")
  out.write_string(self.url_str)
  out.write_string(")")
}

///|

///|
pub(all) struct Handler(async (Context) -> Unit) derive(Debug)

///|
pub enum RouteResult {
  Found(Endpoint, Array[String])
  MethodNotAllowed
  NotFound
}

///|
pub struct Router {
  tree : Node
  middlewares : Array[Middleware]
  mut not_found_handler : Handler?
  mut method_not_allowed_handler : Handler?
} derive(Debug)

// Default handlers

///|
fn default_not_found() -> Handler {
  ctx => ctx.write_text(404, "Not Found")
}

///|
fn default_method_not_allowed() -> Handler {
  ctx => ctx.write_text(405, "Method Not Allowed")
}

///|
pub impl Show for Router with fn to_string(self : Router) -> String {
  self.tree.to_string()
}

///|
pub fn Router::Router() -> Router {
  {
    tree: Node::{
      node_type: Static("".to_string()),
      children_static: [],
      children_param: [],
      child_wildcard: None,
      endpoints: Map([]),
    },
    middlewares: [],
    not_found_handler: None,
    method_not_allowed_handler: None,
  }
}

///|
pub fn Router::use_mw(self : Router, mw : Middleware) -> Unit {
  self.middlewares.push(mw)
}

///|
pub fn Router::set_not_found(self : Router, handler : Handler) -> Unit {
  self.not_found_handler = Some(handler)
}

///|
pub fn Router::set_method_not_allowed(self : Router, handler : Handler) -> Unit {
  self.method_not_allowed_handler = Some(handler)
}

///|
/// Add a new route to the router
/// # Parameters
/// - `meth`: HTTP method
/// - `pattern`: URL pattern, must start with `/`
/// - `mws`: Optional array of middlewares, applied in order before the handler
///    only applies to this route
/// - `name`: Optional name for the route
/// - `handler`: Handler function
/// # Raises
/// - `RouterError::InvalidPattern`: If the pattern does not start with `/`
/// or is otherwise invalid
pub fn Router::add(
  self : Router,
  meth : HttpMethod,
  pattern : String,
  name? : String = "",
  mws? : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  guard pattern.has_prefix("/") else {
    raise RouterError::InvalidPattern(
      http_method=meth.to_string(),
      path=pattern,
      reason="pattern must start with /",
    )
  }
  self.tree.insert(meth, pattern, name~, chain(mws, handler))
}

///|
pub fn Router::any(
  self : Router,
  pattern : String,
  name? : String = "",
  mws? : Array[Middleware] = [],
  handler : Handler,
) -> Unit raise RouterError {
  self.add(HttpMethod::Any, pattern, name~, mws~, handler)
}

///|
/// Mount a sub-router under the given prefix using a `prefix/*`
/// wildcard route, like chi does. The sub-router stays alive — routes
/// added to it after `mount` are automatically picked up.
pub fn Router::mount(
  self : Router,
  prefix : String,
  sub : Router,
) -> Unit raise RouterError {
  let handler : Handler = ctx => {
    ctx.route_path = ctx.route_path[prefix.length():].to_owned()
    sub.handler(ctx)
  }
  self.add(HttpMethod::Any, prefix + "/*", handler)
}

///|
pub struct Server {
  router : Router
  addr : String
  read_timeout : Int?
  write_timeout : Int?
  mut request_id : Int
}

///|
pub fn Server::Server(addr : String, router : Router) -> Server {
  { router, addr, read_timeout: None, write_timeout: None, request_id: 0 }
}

///|
pub fn Server::with_timeout(self : Server, read? : Int, write? : Int) -> Server {
  { ..self, read_timeout: read, write_timeout: write }
}

///|
pub async fn Server::start(self : Server) -> Unit {
  let server = @http.Server::Server(@socket.Addr::parse(self.addr))
  server.run_forever((req, req_body, resp_writer) => {
    let ctx = self.router.build_ctx(req, req_body, resp_writer)
    self.request_id += 1
    ctx.set_ext(RequestId::{  }, self.request_id.to_string())
    self.router.handler(ctx)
  })
}

///|
pub async fn start(addr : String, router : Router) -> Unit {
  Server::Server(addr, router).start()
}

///|
fn parse_query(q : String) -> Values {
  let m : Map[String, Array[String]] = Map([])
  for pair in q.split("&") {
    if pair == "" {
      continue
    }
    let (k, v) = if pair.find("=") is Some(idx) {
      let k = @url.query_unescape(pair[:idx].to_owned()) catch {
        _ => pair[:idx].to_owned()
      }
      let v = @url.query_unescape(pair[idx + 1:].to_owned()) catch {
        _ => pair[idx + 1:].to_owned()
      }
      (k, v)
    } else {
      let k = @url.query_unescape(pair.to_owned()) catch {
        _ => pair.to_owned()
      }
      (k, "")
    }
    m.get_or_init(k, () => []).push(v)
  }
  Values(m)
}

///|
pub fn Router::build_ctx(
  _self : Router,
  req : @http.Request,
  req_body : &@io.Reader,
  resp_writer : @http.ServerConnection,
) -> Context {
  let url = @url.parse_request_uri(req.path) catch {
    _ => @url.URL::{ ..@url.empty_url, path: Some(req.path), query: None }
  }
  Context::{
    http_method: HttpMethod::from_std(req.meth),
    url_str: req.path,
    url,
    req_headers: HttpHeaders::from_map(req.headers),
    resp_headers: HttpHeaders::new(),
    queries: match url.query {
      Some(q) => parse_query(q)
      None => Values::new()
    },
    form_values: None,
    multipart_form: None,
    exts: ExtStore::new(),
    path_params: [],
    req_body,
    resp_writer,
    route_path: url.path.unwrap_or(""),
  }
}

///|
pub async fn Router::handler(self : Router, ctx : Context) -> Unit {
  let result = self.route(ctx.http_method, ctx.route_path)
  match result {
    RouteResult::Found(ep, param_values) => {
      ctx.path_params = ep.to_paramKV_array(param_values)
      chain(self.middlewares, ep.handler)(ctx)
    }
    RouteResult::MethodNotAllowed => {
      let h = self.method_not_allowed_handler.unwrap_or(
        default_method_not_allowed(),
      )
      h(ctx)
    }
    RouteResult::NotFound => {
      let h = self.not_found_handler.unwrap_or(default_not_found())
      h(ctx)
    }
  }
  ctx.cleanup()
}

///|
pub async fn Router::handle(
  self : Router,
  req : @http.Request,
  req_body : &@io.Reader,
  resp_writer : @http.ServerConnection,
) -> Unit {
  let ctx = self.build_ctx(req, req_body, resp_writer)
  self.handler(ctx)
}

///|
fn Router::route(
  self : Router,
  meth : HttpMethod,
  path : String,
) -> RouteResult {
  self.tree.route(meth, path)
}
