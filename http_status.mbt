///|
pub let status_continue = 100

///|
pub let status_switching_protocols = 101

///|
pub let status_processing = 102

///|
pub let status_early_hints = 103

///|
pub let status_ok = 200

///|
pub let status_created = 201

///|
pub let status_accepted = 202

///|
pub let status_non_authoritative_info = 203

///|
pub let status_no_content = 204

///|
pub let status_reset_content = 205

///|
pub let status_partial_content = 206

///|
pub let status_multi_status = 207

///|
pub let status_already_reported = 208

///|
pub let status_im_used = 226

///|
pub let status_multiple_choices = 300

///|
pub let status_moved_permanently = 301

///|
pub let status_found = 302

///|
pub let status_see_other = 303

///|
pub let status_not_modified = 304

///|
pub let status_use_proxy = 305

///|
pub let status_temporary_redirect = 307

///|
pub let status_permanent_redirect = 308

///|
pub let status_bad_request = 400

///|
pub let status_unauthorized = 401

///|
pub let status_payment_required = 402

///|
pub let status_forbidden = 403

///|
pub let status_not_found = 404

///|
pub let status_method_not_allowed = 405

///|
pub let status_not_acceptable = 406

///|
pub let status_proxy_auth_required = 407

///|
pub let status_request_timeout = 408

///|
pub let status_conflict = 409

///|
pub let status_gone = 410

///|
pub let status_length_required = 411

///|
pub let status_precondition_failed = 412

///|
pub let status_request_entity_too_large = 413

///|
pub let status_request_uri_too_long = 414

///|
pub let status_unsupported_media_type = 415

///|
pub let status_requested_range_not_satisfiable = 416

///|
pub let status_expectation_failed = 417

///|
pub let status_misdirected_request = 421

///|
pub let status_unprocessable_entity = 422

///|
pub let status_locked = 423

///|
pub let status_failed_dependency = 424

///|
pub let status_too_early = 425

///|
pub let status_upgrade_required = 426

///|
pub let status_precondition_required = 428

///|
pub let status_too_many_requests = 429

///|
pub let status_request_header_fields_too_large = 431

///|
pub let status_unavailable_for_legal_reasons = 451

///|
pub let status_internal_server_error = 500

///|
pub let status_not_implemented = 501

///|
pub let status_bad_gateway = 502

///|
pub let status_service_unavailable = 503

///|
pub let status_gateway_timeout = 504

///|
pub let status_http_version_not_supported = 505

///|
pub let status_variant_also_negotiates = 506

///|
pub let status_insufficient_storage = 507

///|
pub let status_loop_detected = 508

///|
pub let status_not_extended = 510

///|
pub let status_network_authentication_required = 511

///|
pub fn status_text(code : Int) -> String {
  match code {
    100 => "Continue"
    101 => "Switching Protocols"
    102 => "Processing"
    103 => "Early Hints"
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    203 => "Non-Authoritative Information"
    204 => "No Content"
    205 => "Reset Content"
    206 => "Partial Content"
    207 => "Multi-Status"
    208 => "Already Reported"
    226 => "IM Used"
    300 => "Multiple Choices"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    305 => "Use Proxy"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    402 => "Payment Required"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    406 => "Not Acceptable"
    407 => "Proxy Authentication Required"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Request Entity Too Large"
    414 => "Request URI Too Long"
    415 => "Unsupported Media Type"
    416 => "Requested Range Not Satisfiable"
    417 => "Expectation Failed"
    421 => "Misdirected Request"
    422 => "Unprocessable Entity"
    423 => "Locked"
    424 => "Failed Dependency"
    425 => "Too Early"
    426 => "Upgrade Required"
    428 => "Precondition Required"
    429 => "Too Many Requests"
    431 => "Request Header Fields Too Large"
    451 => "Unavailable For Legal Reasons"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    505 => "HTTP Version Not Supported"
    506 => "Variant Also Negotiates"
    507 => "Insufficient Storage"
    508 => "Loop Detected"
    510 => "Not Extended"
    511 => "Network Authentication Required"
    _ => ""
  }
}
