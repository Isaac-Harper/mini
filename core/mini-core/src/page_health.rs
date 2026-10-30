use cef::*;
use serde::Deserialize;
use std::{
    collections::HashMap,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use crate::{
    MiniTabId,
    login::javascript_string_literal,
    state::{c_string, callbacks, tab_is_live},
};

const MESSAGE_LIMIT: usize = 300;
const REPORT_LIMIT: u32 = 100_000;

const HEALTH_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-health-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console);
var count=0,first=null,scheduled=false;
function report(){scheduled=false;var text=JSON.stringify({count:count,message:first||''});count=0;first=null;signal(token+':health:'+frameId+':'+text);}
function describe(value){try{if(value instanceof Error)return value.name+': '+value.message;if(value&&typeof value==='object'&&'message' in value)return String(value.message);return String(value);}catch(error){return 'Error';}}
function message(event){if(event.type==='error')return event.error!==undefined&&event.error!==null?describe(event.error):event.message;var reason=event.reason;return reason instanceof Error?describe(reason):'Unhandled rejection: '+describe(reason);}
function record(event,amount){count+=amount;if(first===null)first=String(message(event)).split('\n')[0].slice(0,300);if(!scheduled){scheduled=true;setTimeout(report,250);}}
window.addEventListener('error',function(event){if(!(event instanceof ErrorEvent))return;record(event,1);});
window.addEventListener('unhandledrejection',function(event){record(event,1);});
var early=window[Symbol.for(__EARLY_KEY__)];
if(typeof early==='function'){var taken=early();if(taken.count>0)record(taken.event,taken.count);}
})();"#;

static TRACKED_PAGES: Mutex<Option<HashMap<MiniTabId, u64>>> = Mutex::new(None);
static NEXT_PAGE: AtomicU64 = AtomicU64::new(1);

fn with_tracked_pages<Output>(action: impl FnOnce(&mut HashMap<MiniTabId, u64>) -> Output) -> Output {
    let mut pages = TRACKED_PAGES.lock().expect("page health lock poisoned");
    action(pages.get_or_insert_with(HashMap::new))
}

pub fn main_frame_navigation_started(tab: MiniTabId, url: &str) {
    let url = c_string(url);
    let wanted = unsafe { (callbacks().page_health_wanted)(tab, url.as_ptr()) };
    with_tracked_pages(|pages| {
        if wanted {
            pages.insert(tab, NEXT_PAGE.fetch_add(1, Ordering::Relaxed));
        } else {
            pages.remove(&tab);
        }
    });
}

pub fn main_frame_script(tab: MiniTabId, frame: &Frame, token: &str) -> Option<String> {
    tracked_page(tab).is_some().then(|| script(frame, token))
}

pub fn forget(tab: MiniTabId) {
    with_tracked_pages(|pages| pages.remove(&tab));
}

pub fn tracked_page(tab: MiniTabId) -> Option<u64> {
    with_tracked_pages(|pages| pages.get(&tab).copied())
}

fn script(frame: &Frame, token: &str) -> String {
    HEALTH_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
        .replace("__EARLY_KEY__", &javascript_string_literal(early_errors::KEY))
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct ErrorReport {
    pub count: u32,
    pub message: String,
}

pub fn parse(payload: &str) -> Option<ErrorReport> {
    let mut report = serde_json::from_str::<ErrorReport>(payload).ok()?;
    if report.count == 0 || report.count > REPORT_LIMIT {
        return None;
    }
    let line = report.message.lines().next().unwrap_or_default();
    report.message = line.chars().take(MESSAGE_LIMIT).collect();
    Some(report)
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":health:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| frame.is_main() == 1);
    if let (true, true, Some(report)) = (is_main_frame, tracked_page(tab).is_some(), parse(payload)) {
        let message = c_string(&report.message);
        unsafe { (callbacks().page_errors_reported)(tab, report.count, message.as_ptr()) };
    }
    true
}

pub fn failure_status(request_failed: bool, http_status: i32, net_error: i32) -> Option<i32> {
    const ABORTED: i32 = -3;
    const BLOCKED_BY_CLIENT: i32 = -20;
    if request_failed {
        return (net_error < 0 && net_error != ABORTED && net_error != BLOCKED_BY_CLIENT).then_some(net_error);
    }
    (http_status >= 400).then_some(http_status)
}

pub fn report_from_io_thread(
    tab: MiniTabId,
    page: u64,
    request: &Request,
    response: Option<&Response>,
    status: UrlrequestStatus,
) {
    if matches!(request.resource_type(), ResourceType::MAIN_FRAME | ResourceType::FAVICON) {
        return;
    }
    let request_failed = status.get_raw() == UrlrequestStatus::FAILED.get_raw();
    let http_status = response.map_or(0, |response| response.status());
    let net_error = response.map_or(0, |response| *response.error().as_ref() as i32);
    let Some(failure) = failure_status(request_failed, http_status, net_error) else {
        return;
    };
    let url = CefString::from(&request.url()).to_string();
    let mut task = FailedRequestReport::new(tab, page, failure, url);
    assert_eq!(post_task(ThreadId::UI, Some(&mut task)), 1, "cannot post a failed request to the UI thread");
}

wrap_task! {
    struct FailedRequestReport {
        tab: MiniTabId,
        page: u64,
        status: i32,
        url: String,
    }

    impl Task {
        fn execute(&self) {
            if !tab_is_live(self.tab) || tracked_page(self.tab) != Some(self.page) {
                return;
            }
            let url = c_string(&self.url);
            unsafe { (callbacks().request_failed)(self.tab, self.status, url.as_ptr()) };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ErrorReport, failure_status, parse};

    #[test]
    fn parses_a_batch_and_keeps_one_short_line() {
        assert_eq!(
            parse(r#"{"count":2,"message":"TypeError: x is undefined"}"#),
            Some(ErrorReport { count: 2, message: "TypeError: x is undefined".into() })
        );
        let long = format!(r#"{{"count":1,"message":"{}\nsecond line"}}"#, "a".repeat(400));
        assert_eq!(parse(&long).map(|report| report.message), Some("a".repeat(300)));
    }

    #[test]
    fn rejects_empty_or_absurd_batches() {
        assert_eq!(parse(r#"{"count":0,"message":"x"}"#), None);
        assert_eq!(parse(r#"{"count":1000000,"message":"x"}"#), None);
        assert_eq!(parse(r#"{"count":-1,"message":"x"}"#), None);
        assert_eq!(parse(r#"{"count":1}"#), None);
        assert_eq!(parse("not json"), None);
    }

    #[test]
    fn reports_http_errors_and_network_failures_only() {
        assert_eq!(failure_status(false, 404, 0), Some(404));
        assert_eq!(failure_status(false, 500, 0), Some(500));
        assert_eq!(failure_status(false, 200, 0), None);
        assert_eq!(failure_status(false, 304, 0), None);
        assert_eq!(failure_status(true, 0, -102), Some(-102));
        assert_eq!(failure_status(true, 0, -3), None);
        assert_eq!(failure_status(true, 0, -20), None);
        assert_eq!(failure_status(true, 0, 0), None);
    }
}
