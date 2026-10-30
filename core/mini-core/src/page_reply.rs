use cef::*;

use crate::{
    MiniTabId,
    login::{self, javascript_string_literal},
    state::callbacks,
};

pub fn instantiate(template: &str, token: &str, request: u64) -> String {
    template
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace("__REQUEST__", &request.to_string())
}

pub fn run_in_every_frame(browser: &Browser, script: &str) {
    let mut identifiers = CefStringList::new();
    browser.frame_identifiers(Some(&mut identifiers));
    for identifier in identifiers {
        if let Some(frame) =
            browser.frame_by_identifier(Some(&CefString::from(identifier.as_str())))
        {
            login::run(&frame, script);
        }
    }
}

pub fn run_in_main_frame(browser: &Browser, script: &str) {
    login::run(
        &browser.main_frame().expect("browser has no main frame"),
        script,
    );
}

pub fn parse(rest: &str) -> Option<(u64, &str)> {
    let (request, payload) = rest.strip_prefix(":pagetext:")?.split_once(':')?;
    Some((request.parse().ok()?, payload))
}

pub fn handle_signal(tab: MiniTabId, rest: &str) -> bool {
    if !rest.starts_with(":pagetext:") {
        return false;
    }
    if let Some((request, payload)) = parse(rest) {
        unsafe { (callbacks().page_text_received)(tab, request, payload.as_ptr(), payload.len()) };
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_request_number_and_keeps_colons_and_newlines_in_the_payload() {
        assert_eq!(
            parse(":pagetext:12:# Title: a\nb"),
            Some((12, "# Title: a\nb"))
        );
        assert_eq!(parse(":pagetext:7:"), Some((7, "")));
    }

    #[test]
    fn rejects_malformed_replies() {
        assert_eq!(parse(":pagetext:x:body"), None);
        assert_eq!(parse(":pagetext:12"), None);
        assert_eq!(parse(":vitals:12:body"), None);
    }

    #[test]
    fn instantiates_token_and_request() {
        assert_eq!(
            instantiate("a(__TOKEN__,__REQUEST__)", "t0k", 9),
            "a(\"t0k\",9)"
        );
    }
}
