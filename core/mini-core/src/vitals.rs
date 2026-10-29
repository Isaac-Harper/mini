use cef::*;
use serde::Deserialize;

use crate::{MiniTabId, login::javascript_string_literal, state::callbacks};

const VITALS_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-vitals-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console);
var state={lcp:-1,cls:0,inp:-1,ttfb:-1,load:-1},last='',scheduled=false,sessionValue=0,sessionEntries=[],interactions={};
function activation(){var entry=performance.getEntriesByType('navigation')[0];return entry&&entry.activationStart||0;}
function report(){scheduled=false;var text=JSON.stringify(state);if(text===last)return;last=text;signal(token+':vitals:'+frameId+':'+text);}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(report,250);}
function observe(type,options,handler){try{var observer=new PerformanceObserver(function(list){list.getEntries().forEach(handler);schedule();});var settings={type:type,buffered:true};for(var name in options)settings[name]=options[name];observer.observe(settings);}catch(error){}}
observe('navigation',{},function(entry){state.ttfb=Math.max(0,entry.responseStart-(entry.activationStart||0));if(entry.loadEventEnd>0)state.load=Math.max(0,entry.loadEventEnd-(entry.activationStart||0));});
observe('largest-contentful-paint',{},function(entry){state.lcp=Math.max(0,entry.startTime-activation());});
observe('layout-shift',{},function(entry){if(entry.hadRecentInput)return;var first=sessionEntries[0],previous=sessionEntries[sessionEntries.length-1];
if(previous&&entry.startTime-previous.startTime<1000&&entry.startTime-first.startTime<5000){sessionValue+=entry.value;sessionEntries.push(entry);}else{sessionValue=entry.value;sessionEntries=[entry];}
if(sessionValue>state.cls)state.cls=sessionValue;});
observe('event',{durationThreshold:16},function(entry){if(!entry.interactionId)return;if(entry.duration<=(interactions[entry.interactionId]||0))return;interactions[entry.interactionId]=entry.duration;
var durations=Object.keys(interactions).map(function(id){return interactions[id];}).sort(function(a,b){return b-a;});state.inp=durations[Math.min(durations.length-1,Math.floor(durations.length/50))];});
})();"#;

#[derive(Deserialize, Debug, PartialEq)]
pub struct Vitals {
    pub lcp: f64,
    pub cls: f64,
    pub inp: f64,
    pub ttfb: f64,
    pub load: f64,
}

pub fn script(frame: &Frame, token: &str) -> String {
    VITALS_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

pub fn parse(payload: &str) -> Option<Vitals> {
    let vitals = serde_json::from_str::<Vitals>(payload).ok()?;
    let values = [vitals.lcp, vitals.cls, vitals.inp, vitals.ttfb, vitals.load];
    values.iter().all(|value| value.is_finite() && *value >= -1.0 && *value < 3_600_000.0).then_some(vitals)
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":vitals:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| frame.is_main() == 1);
    if let (true, Some(vitals)) = (is_main_frame, parse(payload)) {
        unsafe { (callbacks().page_vitals_changed)(tab, vitals.lcp, vitals.inp, vitals.cls, vitals.ttfb, vitals.load) };
    }
    true
}

#[cfg(test)]
mod tests {
    use super::{Vitals, parse};

    #[test]
    fn parses_the_reported_numbers() {
        assert_eq!(
            parse(r#"{"lcp":1234.5,"cls":0.12,"inp":-1,"ttfb":88,"load":-1}"#),
            Some(Vitals { lcp: 1234.5, cls: 0.12, inp: -1.0, ttfb: 88.0, load: -1.0 })
        );
    }

    #[test]
    fn rejects_anything_but_four_sane_numbers() {
        assert_eq!(parse(r#"{"lcp":"x","cls":0,"inp":0,"ttfb":0,"load":0}"#), None);
        assert_eq!(parse(r#"{"lcp":1,"cls":0,"inp":0,"ttfb":0}"#), None);
        assert_eq!(parse(r#"{"lcp":-5,"cls":0,"inp":0,"ttfb":0,"load":0}"#), None);
        assert_eq!(parse(r#"{"lcp":1e12,"cls":0,"inp":0,"ttfb":0,"load":0}"#), None);
        assert_eq!(parse("not json"), None);
    }
}
