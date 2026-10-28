use cef::*;
use serde::Deserialize;

use crate::{
    MiniTabId,
    login::javascript_string_literal,
    state::{c_string, callbacks, with_core},
};

const MEDIA_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-media-'+__TOKEN__);
if(window[key])return;
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),last='',pausedByMini=[],scheduled=false;
function media(){return Array.prototype.slice.call(document.querySelectorAll('video,audio'));}
function audible(element){return !element.paused&&!element.ended&&!element.muted&&element.volume>0&&element.readyState>2;}
function report(){scheduled=false;
var playing=media().some(audible);
var metadata=navigator.mediaSession&&navigator.mediaSession.metadata;
var title=metadata?[metadata.title,metadata.artist].filter(Boolean).join(' · '):'';
var state=JSON.stringify({playing:playing,title:title});
if(state===last)return;last=state;signal(token+':media:'+frameId+':'+state);}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(report,250);}
['play','playing','pause','ended','volumechange','emptied'].forEach(function(type){document.addEventListener(type,schedule,true);});
Object.defineProperty(window,key,{value:{
pause:function(){pausedByMini=media().filter(audible);pausedByMini.forEach(function(element){element.pause();});},
resume:function(){var targets=pausedByMini.length?pausedByMini:media().filter(function(element){return element.paused&&element.currentTime>0;}).slice(-1);pausedByMini=[];targets.forEach(function(element){element.play().catch(function(){});});}
}});
})();"#;

pub fn script(frame: &Frame, token: &str) -> String {
    MEDIA_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

#[derive(Deserialize)]
struct MediaState {
    playing: bool,
    title: String,
}

pub fn handle_signal(tab: MiniTabId, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":media:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let Ok(state) = serde_json::from_str::<MediaState>(payload) else {
        return true;
    };
    update(tab, |frames| {
        if state.playing {
            frames.insert(frame_id.to_owned(), state.title);
        } else {
            frames.remove(frame_id);
        }
    });
    true
}

fn update(tab: MiniTabId, change: impl FnOnce(&mut std::collections::BTreeMap<String, String>)) {
    let report = with_core(|core| {
        let state = core.tabs.get_mut(&tab)?;
        let before = summary(&state.playing_frames);
        change(&mut state.playing_frames);
        let after = summary(&state.playing_frames);
        (before != after).then_some(after)
    });
    if let Some((playing, title)) = report {
        let title = c_string(&title);
        unsafe { (callbacks().audio_state_changed)(tab, playing, title.as_ptr()) };
    }
}

fn summary(frames: &std::collections::BTreeMap<String, String>) -> (bool, String) {
    let title = frames.values().find(|title| !title.is_empty()).cloned().unwrap_or_default();
    (!frames.is_empty(), title)
}

pub fn reset(tab: MiniTabId) {
    update(tab, |frames| frames.clear());
}

pub fn control(browser: &Browser, token: &str, play: bool) {
    let script = format!(
        "(function(){{var api=window[Symbol.for('mini-media-'+{})];if(api)api.{}();}})();",
        javascript_string_literal(token),
        if play { "resume" } else { "pause" }
    );
    let mut identifiers = CefStringList::new();
    browser.frame_identifiers(Some(&mut identifiers));
    for identifier in identifiers {
        if let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(identifier.as_str()))) {
            let url = CefString::from(&frame.url()).to_string();
            frame.execute_java_script(Some(&CefString::from(script.as_str())), Some(&CefString::from(url.as_str())), 0);
        }
    }
}
