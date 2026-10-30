use cef::*;

use crate::{
    MiniTabId,
    login::{javascript_string_literal, token},
    state::with_core,
};

const REPLACEMENT_SCRIPT: &str = r#"(function(){
if(location.protocol!=='chrome-error:'&&document.body&&document.body.childElementCount>0)return;
var token=__TOKEN__,signal=console.debug.bind(console);
document.open();document.write(__HTML__);document.close();
if(history.length<2){var back=document.querySelector('[data-mini-action=back]');if(back)back.remove();var first=document.querySelector('button');if(first)first.className='primary';}
document.addEventListener('click',function(event){var target=event.target.closest&&event.target.closest('[data-mini-action]');
if(target)signal(token+':errorpage:'+target.getAttribute('data-mini-action'));},true);
})();"#;

pub fn replacement_script(token: &str, html: &str) -> String {
    REPLACEMENT_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace("__HTML__", &javascript_string_literal(html))
}

pub fn show(tab: MiniTabId, html: &str) {
    let browser = with_core(|core| {
        let state = core.tabs.get_mut(&tab)?;
        state.pending_error_page = Some(html.to_owned());
        state.browser.clone()
    });
    if let Some(frame) = browser.and_then(|browser| browser.main_frame()) {
        apply(&frame, html);
    }
}

pub fn main_frame_loaded(tab: MiniTabId, frame: &Frame) {
    let pending = with_core(|core| core.tabs.get_mut(&tab).and_then(|state| state.pending_error_page.take()));
    if let Some(html) = pending {
        apply(frame, &html);
    }
}

fn apply(frame: &Frame, html: &str) {
    let script = replacement_script(token(), html);
    frame.execute_java_script(Some(&CefString::from(script.as_str())), Some(&CefString::from("mini-error-page")), 0);
}

pub fn handle_signal(browser: &Browser, rest: &str) -> bool {
    let Some(action) = rest.strip_prefix(":errorpage:") else {
        return false;
    };
    match action {
        "retry" => browser.reload(),
        "back" => browser.go_back(),
        _ => {}
    }
    true
}

#[cfg(test)]
mod tests {
    use super::replacement_script;

    #[test]
    fn page_html_is_a_safe_literal() {
        let script = replacement_script("abc", "<p>\"x\"</p>\u{2028}");
        assert!(script.contains(r#""\u003cp>\"x\"\u003c/p>\u2028""#));
        assert!(script.contains(r#"var token="abc""#));
        assert!(!script.contains("__HTML__") && !script.contains("__TOKEN__"));
    }
}
