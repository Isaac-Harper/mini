use base64::{Engine as _, prelude::BASE64_STANDARD};
use cef::*;
use serde_json::{Value, json};

use crate::{
    MiniTabId,
    state::{callbacks, next_request_id, with_tab},
};

pub const COLOR_SCHEME_SYSTEM: i32 = 0;
pub const COLOR_SCHEME_LIGHT: i32 = 1;
pub const COLOR_SCHEME_DARK: i32 = 2;

wrap_dev_tools_message_observer! {
    struct SnapshotObserver {
        tab: MiniTabId,
        request: u64,
        message_id: i32,
    }

    impl DevToolsMessageObserver {
        fn on_dev_tools_method_result(
            &self,
            _browser: Option<&mut Browser>,
            message_id: ::std::os::raw::c_int,
            success: ::std::os::raw::c_int,
            result: Option<&[u8]>,
        ) {
            if message_id != self.message_id {
                return;
            }
            let image = if success == 1 { result.and_then(snapshot_image) } else { None }.unwrap_or_default();
            unsafe { (callbacks().page_snapshot_received)(self.tab, self.request, image.as_ptr(), image.len()) };
        }
    }
}

fn snapshot_image(result: &[u8]) -> Option<Vec<u8>> {
    let value: Value = serde_json::from_slice(result).ok()?;
    BASE64_STANDARD.decode(value.get("data")?.as_str()?).ok()
}

fn next_message_id() -> i32 {
    i32::try_from(next_request_id() % i32::MAX as u64).expect("message id fits i32")
}

fn send(browser: &Browser, message_id: i32, method: &str, params: Value) {
    let message = json!({ "id": message_id, "method": method, "params": params }).to_string();
    let sent = browser
        .host()
        .expect("browser has no host")
        .send_dev_tools_message(Some(message.as_bytes()));
    assert_eq!(sent, 1, "{method} was not sent");
}

pub fn media_features(color_scheme: i32, reduced_motion: bool) -> Value {
    let scheme = match color_scheme {
        COLOR_SCHEME_SYSTEM => "",
        COLOR_SCHEME_LIGHT => "light",
        COLOR_SCHEME_DARK => "dark",
        other => panic!("unknown color scheme {other}"),
    };
    json!({
        "features": [
            { "name": "prefers-color-scheme", "value": scheme },
            { "name": "prefers-reduced-motion", "value": if reduced_motion { "reduce" } else { "" } },
        ]
    })
}

pub fn set_emulated_media(browser: &Browser, color_scheme: i32, reduced_motion: bool) {
    send(
        browser,
        next_message_id(),
        "Emulation.setEmulatedMedia",
        media_features(color_scheme, reduced_motion),
    );
}

pub fn capture_snapshot(tab: MiniTabId, browser: &Browser, request: u64) {
    let message_id = next_message_id();
    let mut observer = SnapshotObserver::new(tab, request, message_id);
    let registration = browser
        .host()
        .expect("browser has no host")
        .add_dev_tools_message_observer(Some(&mut observer))
        .expect("CEF refused the devtools observer");
    with_tab(tab, |state| state.snapshot_observer = Some(registration));
    send(
        browser,
        message_id,
        "Page.captureScreenshot",
        json!({ "format": "jpeg", "quality": 90, "optimizeForSpeed": true }),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_clears_both_features() {
        let features = media_features(COLOR_SCHEME_SYSTEM, false);
        assert_eq!(features["features"][0]["value"], "");
        assert_eq!(features["features"][1]["value"], "");
    }

    #[test]
    fn forces_scheme_and_motion() {
        let features = media_features(COLOR_SCHEME_DARK, true);
        assert_eq!(features["features"][0]["name"], "prefers-color-scheme");
        assert_eq!(features["features"][0]["value"], "dark");
        assert_eq!(features["features"][1]["name"], "prefers-reduced-motion");
        assert_eq!(features["features"][1]["value"], "reduce");
        assert_eq!(media_features(COLOR_SCHEME_LIGHT, false)["features"][0]["value"], "light");
    }

    #[test]
    fn decodes_the_screenshot_result() {
        assert_eq!(snapshot_image(br#"{"data":"AQID"}"#), Some(vec![1, 2, 3]));
        assert_eq!(snapshot_image(br#"{"other":1}"#), None);
        assert_eq!(snapshot_image(b"not json"), None);
    }
}
