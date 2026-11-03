use cef::*;

use crate::{
    MiniTabId,
    client::main_frame_url,
    state::{c_string, callbacks},
};

const BROWSER_SCHEMES: [&str; 16] = [
    "about",
    "blob",
    "chrome",
    "chrome-error",
    "chrome-extension",
    "chrome-untrusted",
    "data",
    "devtools",
    "file",
    "filesystem",
    "http",
    "https",
    "javascript",
    "view-source",
    "ws",
    "wss",
];

pub fn is_external(url: &str) -> bool {
    url::Url::parse(url).is_ok_and(|parsed| !BROWSER_SCHEMES.contains(&parsed.scheme()))
}

pub fn report(tab: MiniTabId, browser: &Browser, url: &str) {
    let origin = requesting_origin(&main_frame_url(browser));
    let url = c_string(url);
    let origin = c_string(&origin);
    unsafe { (callbacks().external_url_requested)(tab, url.as_ptr(), origin.as_ptr()) };
}

fn requesting_origin(main_frame_url: &str) -> String {
    match url::Url::parse(main_frame_url) {
        Ok(parsed) if parsed.origin().is_tuple() => parsed.origin().ascii_serialization(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schemes_chromium_does_not_handle_are_external() {
        assert!(is_external("zoommtg://zoom.us/join?confno=1&pwd=secret"));
        assert!(is_external("MAILTO:team@example.com"));
        assert!(is_external("msteams:/l/meetup-join/x"));
        assert!(is_external("vscode://file/Users/me/project"));
    }

    #[test]
    fn browser_schemes_and_unparsable_urls_stay_in_chromium() {
        for url in [
            "https://example.com",
            "http://localhost:3000",
            "about:blank",
            "data:text/html,hi",
            "javascript:void(0)",
            "file:///etc/hosts",
            "chrome://version",
            "blob:https://example.com/id",
            "view-source:https://example.com",
            "devtools://devtools/bundled/inspector.html",
            "not a url",
            "",
        ] {
            assert!(!is_external(url), "{url}");
        }
    }

    #[test]
    fn origin_is_the_main_frame_scheme_host_and_port() {
        assert_eq!(
            requesting_origin("https://zoom.us/j/123?pwd=secret#x"),
            "https://zoom.us"
        );
        assert_eq!(
            requesting_origin("http://localhost:3000/meeting"),
            "http://localhost:3000"
        );
        assert_eq!(
            requesting_origin("HTTPS://Example.COM:443/"),
            "https://example.com"
        );
    }

    #[test]
    fn pages_without_a_tuple_origin_have_none() {
        assert_eq!(requesting_origin(""), "");
        assert_eq!(requesting_origin("about:blank"), "");
        assert_eq!(requesting_origin("data:text/html,hi"), "");
    }
}
