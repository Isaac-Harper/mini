use cef::*;

use crate::{
    MiniTabId,
    login::{javascript_string_literal, run},
    state::{c_string, callbacks},
};

const TIMESHEET_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-harvest-'+__TOKEN__);
if(window[key])return;
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),last='',pending=0;
function text(value){return typeof value==='string'?value.slice(0,500):'';}
function entry(item){return {id:Number(item.id)||0,project:text(item.project_name),client:text(item.client_name),task:text(item.task_name),notes:text(item.notes),hours:Number(item.hours)||0,timerStartedAt:typeof item.timer_started_at==='string'?item.timer_started_at:null,updatedAt:text(item.updated_at)};}
function report(state){var body=JSON.stringify(state);if(body===last)return;last=body;signal(token+':harvest:'+frameId+':{"fetchedAt":'+Date.now()+','+body.slice(1));}
function refresh(){var now=new Date();
fetch('/time/day/'+now.getFullYear()+'/'+(now.getMonth()+1)+'/'+now.getDate(),{headers:{Accept:'application/json'},credentials:'same-origin',cache:'no-store',redirect:'manual'}).then(function(response){
if(response.type==='opaqueredirect'||response.status===401||response.status===403){report({signedIn:false,entries:[]});return null;}
if(!response.ok||(response.headers.get('content-type')||'').indexOf('json')<0)return null;
return response.json();}).then(function(day){if(day&&Array.isArray(day.day_entries))report({signedIn:true,entries:day.day_entries.map(entry)});}).catch(function(){});}
function schedule(){clearTimeout(pending);pending=setTimeout(refresh,400);}
Object.defineProperty(window,key,{value:refresh});
window.addEventListener('harvest:timer-changed',schedule);
window.addEventListener('harvest:day-entry-saved',schedule);
document.addEventListener('visibilitychange',schedule);
function observe(){new MutationObserver(schedule).observe(document.documentElement,{subtree:true,attributes:true,attributeFilter:['data-running-timer']});refresh();}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',observe);else observe();
setInterval(refresh,60000);
})();"#;

const TIMER_SCRIPT: &str = r#"(function(){
var meta=document.querySelector('meta[name="csrf-token"]'),refresh=window[Symbol.for('mini-harvest-'+__TOKEN__)];
fetch('/timers/'+__ENTRY__+'/'+__ACTION__,{method:'POST',credentials:'same-origin',headers:{Accept:'application/json','X-Requested-With':'XMLHttpRequest','X-CSRF-Token':meta?meta.content:''}}).catch(function(){}).then(function(){
if(document.hidden)location.reload();else if(typeof refresh==='function')refresh();});
})();"#;

pub fn is_harvest_url(url: &str) -> bool {
    let Ok(url) = url::Url::parse(url) else {
        return false;
    };
    if url.scheme() != "https" && url.scheme() != "http" {
        return false;
    }
    url.host_str()
        .is_some_and(|host| host == "harvestapp.com" || host.ends_with(".harvestapp.com"))
}

pub fn main_frame_script(frame: &Frame, token: &str) -> Option<String> {
    if !is_harvest_url(&CefString::from(&frame.url()).to_string()) {
        return None;
    }
    Some(timesheet_script(
        token,
        &CefString::from(&frame.identifier()).to_string(),
    ))
}

fn timesheet_script(token: &str, frame_id: &str) -> String {
    TIMESHEET_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace("__FRAME__", &javascript_string_literal(frame_id))
}

fn timer_script(token: &str, entry: u64, start: bool) -> String {
    TIMER_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace("__ENTRY__", &entry.to_string())
        .replace(
            "__ACTION__",
            &javascript_string_literal(if start { "start" } else { "stop" }),
        )
}

pub fn set_timer(browser: &Browser, token: &str, entry: u64, start: bool) {
    assert_ne!(entry, 0, "Harvest entry id 0 is not an entry");
    let frame = browser.main_frame().expect("browser has no main frame");
    if !is_harvest_url(&CefString::from(&frame.url()).to_string()) {
        return;
    }
    run(&frame, &timer_script(token, entry, start));
}

fn is_report(payload: &str) -> bool {
    serde_json::from_str::<serde_json::Value>(payload).is_ok_and(|value| {
        value
            .get("signedIn")
            .is_some_and(serde_json::Value::is_boolean)
            && value
                .get("entries")
                .is_some_and(serde_json::Value::is_array)
            && value
                .get("fetchedAt")
                .is_some_and(serde_json::Value::is_number)
    })
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":harvest:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_harvest_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| {
            frame.is_main() == 1 && is_harvest_url(&CefString::from(&frame.url()).to_string())
        });
    if is_harvest_main_frame && is_report(payload) {
        let report = c_string(payload);
        unsafe { (callbacks().harvest_reported)(tab, report.as_ptr()) };
    }
    true
}

#[cfg(test)]
mod tests {
    use super::{is_harvest_url, is_report, timer_script};

    #[test]
    fn matches_harvest_account_hosts_only() {
        assert!(is_harvest_url("https://example.harvestapp.com/time"));
        assert!(is_harvest_url("https://harvestapp.com/time"));
        assert!(is_harvest_url("http://demo.harvestapp.com:8080/time"));
        assert!(!is_harvest_url("https://id.getharvest.com/sessions/new"));
        assert!(!is_harvest_url("https://harvestapp.com.example.com/time"));
        assert!(!is_harvest_url("https://notharvestapp.com/time"));
        assert!(!is_harvest_url("javascript:alert(1)"));
        assert!(!is_harvest_url("not a url"));
    }

    #[test]
    fn accepts_only_complete_reports() {
        assert!(is_report(
            r#"{"fetchedAt":1,"signedIn":true,"entries":[{"id":1}]}"#
        ));
        assert!(is_report(
            r#"{"fetchedAt":1,"signedIn":false,"entries":[]}"#
        ));
        assert!(!is_report(r#"{"signedIn":true,"entries":[]}"#));
        assert!(!is_report(
            r#"{"fetchedAt":1,"signedIn":"yes","entries":[]}"#
        ));
        assert!(!is_report("not json"));
    }

    #[test]
    fn timer_script_posts_to_the_entry_action() {
        let stop = timer_script("token", 42, false);
        assert!(stop.contains("'/timers/'+42+'/'+\"stop\""));
        assert!(stop.contains("Symbol.for('mini-harvest-'+\"token\")"));
        assert!(timer_script("token", 7, true).contains("'/timers/'+7+'/'+\"start\""));
    }
}
