use cef::*;

use crate::{MiniTabId, login::javascript_string_literal, state::callbacks};

const READ_SCRIPT: &str = r#"(function(){
var element=document.scrollingElement||document.documentElement;
var range=element.scrollHeight-window.innerHeight;
var fraction=range>0?Math.min(1,Math.max(0,window.scrollY/range)):0;
console.debug(__TOKEN__+':scroll-position:'+__FRAME__+':'+fraction);
})();"#;

const RESTORE_SCRIPT: &str = r#"(function(){
if(window.scrollY>0)return;
var element=document.scrollingElement||document.documentElement;
var range=element.scrollHeight-window.innerHeight;
if(range>0)window.scrollTo(window.scrollX,Math.round(range*__FRACTION__));
})();"#;

pub fn request(browser: &Browser, token: &str) {
    let frame = browser.main_frame().expect("browser has no main frame");
    let frame_id = CefString::from(&frame.identifier()).to_string();
    run(&frame, &read_script(token, &frame_id));
}

pub fn restore(browser: &Browser, fraction: f64) {
    assert!(
        (0.0..=1.0).contains(&fraction),
        "scroll fraction {fraction} is outside 0...1"
    );
    let frame = browser.main_frame().expect("browser has no main frame");
    run(&frame, &restore_script(fraction));
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":scroll-position:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| frame.is_main() == 1);
    if let (true, Some(fraction)) = (is_main_frame, parse(payload)) {
        unsafe { (callbacks().scroll_fraction_received)(tab, fraction) };
    }
    true
}

fn read_script(token: &str, frame_id: &str) -> String {
    READ_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace("__FRAME__", &javascript_string_literal(frame_id))
}

fn restore_script(fraction: f64) -> String {
    RESTORE_SCRIPT.replace("__FRACTION__", &fraction.to_string())
}

fn parse(payload: &str) -> Option<f64> {
    payload
        .parse::<f64>()
        .ok()
        .filter(|fraction| (0.0..=1.0).contains(fraction))
}

fn run(frame: &Frame, script: &str) {
    let frame_url = CefString::from(&frame.url()).to_string();
    frame.execute_java_script(
        Some(&CefString::from(script)),
        Some(&CefString::from(frame_url.as_str())),
        0,
    );
}

#[cfg(test)]
mod tests {
    use super::{parse, read_script, restore_script};

    #[test]
    fn only_fractions_between_zero_and_one_parse() {
        assert_eq!(parse("0.25"), Some(0.25));
        assert_eq!(parse("0"), Some(0.0));
        assert_eq!(parse("1"), Some(1.0));
        assert_eq!(parse("1.5"), None);
        assert_eq!(parse("-0.1"), None);
        assert_eq!(parse("NaN"), None);
        assert_eq!(parse(""), None);
    }

    #[test]
    fn the_scripts_carry_their_values_as_literals() {
        let read = read_script("abc", "7-'x");
        assert!(read.contains(r#"console.debug("abc"+':scroll-position:'+"7-'x"+':'+fraction)"#));
        assert!(restore_script(0.5).contains("Math.round(range*0.5)"));
        assert!(restore_script(1.0).contains("Math.round(range*1)"));
    }
}
