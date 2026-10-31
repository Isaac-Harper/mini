use cef::*;
use serde::Deserialize;

use crate::{
    MiniTabId,
    login::javascript_string_literal,
    page_health::tracks_builds,
    state::{c_string, callbacks},
};

pub const REBUILDING: i32 = 0;
pub const READY: i32 = 1;
pub const ERROR_SHOWN: i32 = 2;
pub const ERROR_CLEARED: i32 = 3;

const DETAIL_LIMIT: usize = 300;
const DURATION_LIMIT: f64 = 3_600_000.0;

const BUILD_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-build-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console);
var reported='',scheduled=false,watched=new WeakSet();
var observer=new MutationObserver(schedule);
function firstLine(text){var lines=String(text||'').split('\n');for(var index=0;index<lines.length;index++){var line=lines[index].trim();if(line)return line.slice(0,300);}return '';}
function viteError(){var overlay=document.querySelector('vite-error-overlay');if(!overlay)return null;var body=overlay.shadowRoot&&overlay.shadowRoot.querySelector('.message-body');return firstLine(body?body.textContent:'');}
function nextError(){var portals=document.querySelectorAll('nextjs-portal');for(var index=0;index<portals.length;index++){var root=portals[index].shadowRoot;if(!root)continue;if(!watched.has(root)){watched.add(root);observer.observe(root,{childList:true,subtree:true,characterData:true});}var label=root.querySelector('#nextjs__container_errors_label,#nextjs__container_build_error_label');if(!label)continue;var title=label.textContent.trim();if(title!=='Build Error'&&title!=='Failed to compile')continue;var body=root.querySelector('#nextjs__container_errors_desc,[data-nextjs-terminal]');return firstLine(body?body.textContent:'');}return null;}
function check(){scheduled=false;var detail=viteError();if(detail===null)detail=nextError();var state=detail===null?'':'error:'+detail;if(state===reported)return;reported=state;signal(token+':build:'+frameId+':'+JSON.stringify({error:detail!==null,detail:detail||''}));}
function schedule(){if(!scheduled){scheduled=true;setTimeout(check,150);}}
observer.observe(document,{childList:true,subtree:true});
schedule();
})();"#;

#[derive(Debug, PartialEq)]
pub enum ConsoleSignal {
    Rebuilding,
    Ready(Option<f64>),
}

pub fn parse_console_line(message: &str) -> Option<ConsoleSignal> {
    if message.starts_with("[Fast Refresh] rebuilding") || message.starts_with("[vite] page reload")
    {
        return Some(ConsoleSignal::Rebuilding);
    }
    if let Some(rest) = message.strip_prefix("[Fast Refresh] done") {
        return Some(ConsoleSignal::Ready(fast_refresh_duration(rest)));
    }
    if message.starts_with("[vite] hot updated:") || message.starts_with("[vite] css hot updated:")
    {
        return Some(ConsoleSignal::Ready(None));
    }
    None
}

fn fast_refresh_duration(rest: &str) -> Option<f64> {
    let (number, _) = rest.strip_prefix(" in ")?.split_once("ms")?;
    let duration = number.trim().parse::<f64>().ok()?;
    (duration.is_finite() && (0.0..DURATION_LIMIT).contains(&duration)).then_some(duration)
}

pub fn handle_console_message(tab: MiniTabId, message: &str) {
    let Some(signal) = parse_console_line(message) else {
        return;
    };
    if !tracks_builds(tab) {
        return;
    }
    let (event, duration) = match signal {
        ConsoleSignal::Rebuilding => (REBUILDING, -1.0),
        ConsoleSignal::Ready(duration) => (READY, duration.unwrap_or(-1.0)),
    };
    report(tab, event, duration, "");
}

pub fn main_frame_script(tab: MiniTabId, frame: &Frame, token: &str) -> Option<String> {
    tracks_builds(tab).then(|| script(frame, token))
}

fn script(frame: &Frame, token: &str) -> String {
    BUILD_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct OverlayReport {
    pub error: bool,
    pub detail: String,
}

pub fn parse_overlay(payload: &str) -> Option<OverlayReport> {
    let mut report = serde_json::from_str::<OverlayReport>(payload).ok()?;
    let line = report.detail.lines().next().unwrap_or_default().trim();
    report.detail = if report.error {
        line.chars().take(DETAIL_LIMIT).collect()
    } else {
        String::new()
    };
    Some(report)
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":build:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| frame.is_main() == 1);
    if let (true, true, Some(overlay)) = (is_main_frame, tracks_builds(tab), parse_overlay(payload))
    {
        let event = if overlay.error {
            ERROR_SHOWN
        } else {
            ERROR_CLEARED
        };
        report(tab, event, -1.0, &overlay.detail);
    }
    true
}

fn report(tab: MiniTabId, event: i32, duration: f64, detail: &str) {
    let detail = c_string(detail);
    unsafe { (callbacks().dev_build_reported)(tab, event, duration, detail.as_ptr()) };
}

#[cfg(test)]
mod tests {
    use super::{ConsoleSignal, OverlayReport, parse_console_line, parse_overlay};

    #[test]
    fn parses_next_fast_refresh_lines() {
        assert_eq!(
            parse_console_line("[Fast Refresh] rebuilding"),
            Some(ConsoleSignal::Rebuilding)
        );
        assert_eq!(
            parse_console_line("[Fast Refresh] done in 230ms"),
            Some(ConsoleSignal::Ready(Some(230.0)))
        );
        assert_eq!(
            parse_console_line("[Fast Refresh] done in 12.5ms"),
            Some(ConsoleSignal::Ready(Some(12.5)))
        );
        assert_eq!(
            parse_console_line("[Fast Refresh] done in NaNms"),
            Some(ConsoleSignal::Ready(None))
        );
        assert_eq!(
            parse_console_line("[Fast Refresh] done in -4ms"),
            Some(ConsoleSignal::Ready(None))
        );
        assert_eq!(
            parse_console_line("[Fast Refresh] done"),
            Some(ConsoleSignal::Ready(None))
        );
        assert_eq!(
            parse_console_line("[Fast Refresh] performing full reload"),
            None
        );
    }

    #[test]
    fn parses_vite_lines() {
        assert_eq!(
            parse_console_line("[vite] hot updated: /src/App.tsx"),
            Some(ConsoleSignal::Ready(None))
        );
        assert_eq!(
            parse_console_line("[vite] css hot updated: /src/index.css"),
            Some(ConsoleSignal::Ready(None))
        );
        assert_eq!(
            parse_console_line("[vite] page reload src/main.ts"),
            Some(ConsoleSignal::Rebuilding)
        );
        assert_eq!(parse_console_line("[vite] connected."), None);
        assert_eq!(parse_console_line("[vite] connecting..."), None);
    }

    #[test]
    fn ignores_other_console_lines() {
        assert_eq!(parse_console_line(""), None);
        assert_eq!(parse_console_line("rebuilding [Fast Refresh]"), None);
        assert_eq!(parse_console_line("hello [vite] hot updated: x"), None);
    }

    #[test]
    fn parses_overlay_reports_and_keeps_one_short_line() {
        assert_eq!(
            parse_overlay(r#"{"error":true,"detail":"Module not found: ./x"}"#),
            Some(OverlayReport {
                error: true,
                detail: "Module not found: ./x".into()
            })
        );
        let long = format!(r#"{{"error":true,"detail":"{}\nsecond"}}"#, "a".repeat(400));
        assert_eq!(
            parse_overlay(&long).map(|report| report.detail),
            Some("a".repeat(300))
        );
        assert_eq!(
            parse_overlay(r#"{"error":false,"detail":"stale"}"#),
            Some(OverlayReport {
                error: false,
                detail: String::new()
            })
        );
        assert_eq!(parse_overlay(r#"{"error":true}"#), None);
        assert_eq!(parse_overlay("not json"), None);
    }
}
