use cef::*;
use std::{io::Read, sync::OnceLock};
use zeroize::Zeroize;

use crate::{
    MiniTabId,
    state::{c_string, callbacks, with_core},
};

static TOKEN: OnceLock<String> = OnceLock::new();

const DETECTION_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-login-'+__TOKEN__);
if(window[key])return;
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),state={username:null,password:null};
function hinted(e){var a=(e.autocomplete||'').toLowerCase();return a.indexOf('username')>=0||a.indexOf('email')>=0||e.type==='email';}
function scope(e){return e.form||e.ownerDocument;}
function usernameFor(password){var inputs=Array.prototype.slice.call(scope(password).querySelectorAll('input'));var match=inputs.filter(function(i){return i!==password&&hinted(i);})[0];if(match)return match;var candidate=null;for(var i=0;i<inputs.length;i++){if(inputs[i]===password)break;if(inputs[i].type==='text'||inputs[i].type==='email'||inputs[i].type==='tel')candidate=inputs[i];}return candidate;}
function remember(password){state.password=password;state.username=usernameFor(password);}
function emit(){signal(token+':login:'+frameId);}
var setValue=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
function put(e,v){setValue.call(e,v);e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}
var hasForm=false,checkScheduled=false;
function visiblePassword(){var inputs=document.querySelectorAll('input[type=password]');for(var i=0;i<inputs.length;i++){if(inputs[i].getClientRects().length>0)return true;}return false;}
function check(){checkScheduled=false;var present=visiblePassword();if(present===hasForm)return;hasForm=present;signal(token+':form:'+frameId+':'+(present?'1':'0'));}
function scheduleCheck(){if(checkScheduled)return;checkScheduled=true;setTimeout(check,700);}
new MutationObserver(scheduleCheck).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['type','style','class','hidden']});
document.addEventListener('DOMContentLoaded',scheduleCheck);
window.addEventListener('load',scheduleCheck);
scheduleCheck();
Object.defineProperty(window,key,{value:{
request:function(){var inputs=document.querySelectorAll('input[type=password]');for(var i=0;i<inputs.length;i++){var input=inputs[i];if(input.getClientRects().length===0)continue;remember(input);input.focus();emit();return;}},
fill:function(username,password){if(state.username&&username)put(state.username,username);if(state.password)put(state.password,password);}
}});
})();"#;

const REQUEST_SCRIPT: &str =
    "(function(){var api=window[Symbol.for('mini-login-'+__TOKEN__)];if(api)api.request();})();";

const FILL_SCRIPT: &str = "(function(){var api=window[Symbol.for('mini-login-'+__TOKEN__)];if(api)api.fill(__USERNAME__,__PASSWORD__);})();";

pub fn initialize_token() {
    let mut bytes = [0u8; 16];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut source| source.read_exact(&mut bytes))
        .expect("cannot read /dev/urandom for the login signal token");
    let token: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    TOKEN.set(token).expect("login token initialized twice");
}

pub fn token() -> &'static str {
    TOKEN
        .get()
        .expect("login token used before mini_initialize")
}

pub fn javascript_string_literal(text: &str) -> String {
    serde_json::to_string(text)
        .expect("a string always serializes to JSON")
        .replace('\u{2028}', "\\u2028")
        .replace('\u{2029}', "\\u2029")
        .replace('<', "\\u003c")
}

pub fn origin_of(url: &str) -> Option<String> {
    let parsed = url::Url::parse(url).ok()?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        return None;
    }
    Some(parsed.origin().ascii_serialization())
}

pub fn parse_signal<'message>(token: &str, message: &'message str) -> Option<&'message str> {
    let frame_id = message.strip_prefix(token)?.strip_prefix(":login:")?;
    (!frame_id.is_empty()).then_some(frame_id)
}

pub fn parse_form_signal<'message>(token: &str, message: &'message str) -> Option<(&'message str, bool)> {
    let rest = message.strip_prefix(token)?.strip_prefix(":form:")?;
    let (frame_id, presence) = rest.rsplit_once(':')?;
    if frame_id.is_empty() {
        return None;
    }
    match presence {
        "1" => Some((frame_id, true)),
        "0" => Some((frame_id, false)),
        _ => None,
    }
}

fn report_form_presence(tab: MiniTabId, change: impl FnOnce(&mut std::collections::HashSet<String>)) {
    let changed_to = with_core(|core| {
        let state = core.tabs.get_mut(&tab)?;
        let had_form = !state.login_form_frames.is_empty();
        change(&mut state.login_form_frames);
        let has_form = !state.login_form_frames.is_empty();
        (had_form != has_form).then_some(has_form)
    });
    if let Some(has_form) = changed_to {
        unsafe { (callbacks().login_form_presence_changed)(tab, has_form) };
    }
}

pub fn reset_form_presence(tab: MiniTabId) {
    report_form_presence(tab, |frames| frames.clear());
}

fn frame_identifier(frame: &Frame) -> String {
    CefString::from(&frame.identifier()).to_string()
}

fn frame_url(frame: &Frame) -> String {
    CefString::from(&frame.url()).to_string()
}

fn run(frame: &Frame, script: &str) {
    frame.execute_java_script(
        Some(&CefString::from(script)),
        Some(&CefString::from(frame_url(frame).as_str())),
        0,
    );
}

pub fn detection_script(frame: &Frame) -> String {
    DETECTION_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token()))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&frame_identifier(frame)),
        )
}

pub fn is_signal(message: &str) -> bool {
    message.starts_with(token())
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, message: &str) {
    if let Some(rest) = message.strip_prefix(token())
        && (crate::notifications::handle_signal(tab, browser, token(), rest)
            || crate::media::handle_signal(tab, rest)
            || crate::editable_focus::handle_signal(tab, browser, rest)
            || crate::theme_color::handle_signal(tab, browser, rest)
            || crate::error_page::handle_signal(browser, rest)
            || crate::vitals::handle_signal(tab, browser, rest)
            || crate::horizontal_scroll::handle_signal(tab, browser, rest))
    {
        return;
    }
    if let Some((frame_id, present)) = parse_form_signal(token(), message) {
        if browser.frame_by_identifier(Some(&CefString::from(frame_id))).is_none() {
            return;
        }
        let frame_id = frame_id.to_owned();
        report_form_presence(tab, |frames| {
            if present {
                frames.insert(frame_id);
            } else {
                frames.remove(&frame_id);
            }
        });
        return;
    }
    let Some(frame_id) = parse_signal(token(), message) else {
        return;
    };
    let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(frame_id))) else {
        return;
    };
    let Some(origin) = origin_of(&frame_url(&frame)) else {
        return;
    };
    let frame_id = c_string(frame_id);
    let origin = c_string(&origin);
    unsafe { (callbacks().login_field_focused)(tab, frame_id.as_ptr(), origin.as_ptr()) };
}

pub fn request_fill(browser: &Browser) {
    let script = REQUEST_SCRIPT.replace("__TOKEN__", &javascript_string_literal(token()));
    let mut identifiers = CefStringList::new();
    browser.frame_identifiers(Some(&mut identifiers));
    for identifier in identifiers {
        if let Some(frame) =
            browser.frame_by_identifier(Some(&CefString::from(identifier.as_str())))
        {
            run(&frame, &script);
        }
    }
}

pub fn fill(
    browser: &Browser,
    frame_id: &str,
    expected_origin: &str,
    username: &str,
    password: &str,
) {
    let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(frame_id))) else {
        return;
    };
    if origin_of(&frame_url(&frame)).as_deref() != Some(expected_origin) {
        return;
    }
    let mut username_literal = javascript_string_literal(username);
    let mut password_literal = javascript_string_literal(password);
    let mut script = FILL_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token()))
        .replace("__USERNAME__", &username_literal)
        .replace("__PASSWORD__", &password_literal);
    run(&frame, &script);
    username_literal.zeroize();
    password_literal.zeroize();
    script.zeroize();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn javascript_literal_escapes_quotes_backslashes_separators_and_script_tags() {
        let literal = javascript_string_literal("a\"b\\c\u{2028}d\u{2029}e</script>\n");
        assert_eq!(literal, "\"a\\\"b\\\\c\\u2028d\\u2029e\\u003c/script>\\n\"");
        assert!(!literal.contains('\u{2028}') && !literal.contains('<'));
    }

    #[test]
    fn parses_only_well_formed_signals_with_the_right_token() {
        let token = "0123456789abcdef0123456789abcdef";
        assert_eq!(
            parse_signal(token, &format!("{token}:login:7-12")),
            Some("7-12")
        );
        assert_eq!(
            parse_signal(token, "ffffffffffffffffffffffffffffffff:login:7-12"),
            None
        );
        assert_eq!(parse_signal(token, &format!("{token}:login:")), None);
        assert_eq!(parse_form_signal(token, &format!("{token}:form:7-12:1")), Some(("7-12", true)));
        assert_eq!(parse_form_signal(token, &format!("{token}:form:7-12:0")), Some(("7-12", false)));
        assert_eq!(parse_form_signal(token, &format!("{token}:form::1")), None);
        assert_eq!(parse_form_signal(token, &format!("{token}:form:7-12:2")), None);
        assert_eq!(parse_form_signal("ffffffffffffffffffffffffffffffff", &format!("{token}:form:7-12:1")), None);
        assert_eq!(parse_signal(token, &format!("{token}:logout:7")), None);
        assert_eq!(parse_signal(token, "hello"), None);
    }

    #[test]
    fn derives_origin_only_for_http_schemes() {
        assert_eq!(
            origin_of("https://Example.com/login?x=1").as_deref(),
            Some("https://example.com")
        );
        assert_eq!(
            origin_of("http://localhost:8080/a").as_deref(),
            Some("http://localhost:8080")
        );
        assert_eq!(
            origin_of("https://example.com:443/").as_deref(),
            Some("https://example.com")
        );
        assert_eq!(origin_of("file:///tmp/login.html"), None);
        assert_eq!(origin_of("data:text/html,hi"), None);
        assert_eq!(origin_of("about:blank"), None);
    }
}
