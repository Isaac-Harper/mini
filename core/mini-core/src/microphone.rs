use cef::*;

use crate::{MiniTabId, login::javascript_string_literal, state::with_core};

pub fn reset(tab: MiniTabId) {
    with_core(|core| {
        if let Some(state) = core.tabs.get_mut(&tab) {
            state.microphone_muted = false;
        }
    });
}

pub fn frame_loading(tab: MiniTabId, frame: &Frame, frame_url: &str) {
    let muted = with_core(|core| {
        core.tabs
            .get(&tab)
            .is_some_and(|state| state.microphone_muted)
    });
    if muted {
        run(frame, frame_url, true);
    }
}

pub fn set_muted(tab: MiniTabId, browser: &Browser, muted: bool) {
    with_core(|core| {
        if let Some(state) = core.tabs.get_mut(&tab) {
            state.microphone_muted = muted;
        }
    });
    let mut identifiers = CefStringList::new();
    browser.frame_identifiers(Some(&mut identifiers));
    for identifier in identifiers {
        if let Some(frame) =
            browser.frame_by_identifier(Some(&CefString::from(identifier.as_str())))
        {
            let url = CefString::from(&frame.url()).to_string();
            run(&frame, &url, muted);
        }
    }
}

fn run(frame: &Frame, frame_url: &str, muted: bool) {
    let script = mute_script(muted);
    frame.execute_java_script(
        Some(&CefString::from(script.as_str())),
        Some(&CefString::from(frame_url)),
        0,
    );
}

fn mute_script(muted: bool) -> String {
    format!(
        "(function(){{var mute=window[Symbol.for({})];if(typeof mute==='function')mute({})}})();",
        javascript_string_literal(microphone_mute::KEY),
        muted
    )
}

#[cfg(test)]
mod tests {
    use super::mute_script;

    #[test]
    fn mute_script_calls_the_frame_function() {
        assert_eq!(
            mute_script(true),
            "(function(){var mute=window[Symbol.for(\"mini-microphone\")];if(typeof mute==='function')mute(true)})();"
        );
    }
}
