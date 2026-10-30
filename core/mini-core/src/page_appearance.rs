use cef::*;
use serde_json::{Value, json};

use crate::state::next_request_id;

pub const COLOR_SCHEME_SYSTEM: i32 = 0;
pub const COLOR_SCHEME_LIGHT: i32 = 1;
pub const COLOR_SCHEME_DARK: i32 = 2;

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
}
