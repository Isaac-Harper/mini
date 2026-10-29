use std::collections::HashSet;

use cef::*;

use crate::{
    MiniTabId,
    login::javascript_string_literal,
    state::with_core,
};

const EDITABLE_FOCUS_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-editable-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),last='',scheduled=false,typed=false;
var textless={button:1,checkbox:1,radio:1,submit:1,reset:1,image:1,range:1,color:1,file:1,hidden:1};
function focused(){var element=document.activeElement;
while(element&&element.shadowRoot&&element.shadowRoot.activeElement)element=element.shadowRoot.activeElement;return element;}
function state(){if(document.designMode==='on')return 'e';
var element=focused();if(!element||element===document.body||element===document.documentElement)return 'n';
var tag=element.tagName;
if(tag==='IFRAME'||tag==='FRAME'||tag==='OBJECT'||tag==='EMBED')return 'f';
if(element.isContentEditable||tag==='TEXTAREA')return 'e';
if(tag==='INPUT')return textless[String(element.type).toLowerCase()]?'n':'e';
return 'n';}
function typing(event){if(typed)return;var element=event.composedPath?event.composedPath()[0]:event.target;
if(!element||!element.tagName)return;var tag=element.tagName;
if(!(element.isContentEditable||tag==='TEXTAREA'||(tag==='INPUT'&&!textless[String(element.type).toLowerCase()])))return;
typed=true;signal(token+':typed:'+frameId+':1');}
function submitted(){if(!typed)return;typed=false;signal(token+':typed:'+frameId+':0');}
function report(){scheduled=false;var current=state();if(current===last)return;last=current;
signal(token+':editable:'+frameId+':'+current);}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(report,0);}
document.addEventListener('focusin',report,true);
document.addEventListener('input',report,true);
document.addEventListener('input',typing,true);
document.addEventListener('submit',submitted,true);
['focusout','mousedown'].forEach(function(type){document.addEventListener(type,schedule,true);});
['focus','blur'].forEach(function(type){window.addEventListener(type,schedule,true);});
document.addEventListener('DOMContentLoaded',report);
report();
})();"#;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FrameFocus {
    Editable,
    NotEditable,
    ChildFrame,
}

#[derive(Default)]
pub struct EditableFocus {
    main_frame: Option<FrameFocus>,
    editable_frames: HashSet<String>,
    typed_frames: HashSet<String>,
}

impl EditableFocus {
    pub fn has_editable_focus(&self) -> bool {
        !self.editable_frames.is_empty() || self.main_frame != Some(FrameFocus::NotEditable)
    }

    pub fn has_unsaved_input(&self) -> bool {
        !self.typed_frames.is_empty()
    }

    fn record_typing(&mut self, frame_id: &str, typed: bool) {
        if typed {
            self.typed_frames.insert(frame_id.to_owned());
        } else {
            self.typed_frames.remove(frame_id);
        }
    }

    fn record(&mut self, frame_id: &str, is_main: bool, focus: FrameFocus) {
        if focus == FrameFocus::Editable {
            self.editable_frames.insert(frame_id.to_owned());
        } else {
            self.editable_frames.remove(frame_id);
        }
        if is_main {
            self.main_frame = Some(focus);
        }
    }
}

pub fn script(frame: &Frame, token: &str) -> String {
    EDITABLE_FOCUS_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

fn parse_focus(payload: &str) -> Option<FrameFocus> {
    match payload {
        "e" => Some(FrameFocus::Editable),
        "n" => Some(FrameFocus::NotEditable),
        "f" => Some(FrameFocus::ChildFrame),
        _ => None,
    }
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    if let Some(rest) = rest.strip_prefix(":typed:") {
        if let Some((frame_id, payload)) = rest.split_once(':') {
            with_core(|core| {
                if let Some(state) = core.tabs.get_mut(&tab) {
                    state.editable_focus.record_typing(frame_id, payload == "1");
                }
            });
        }
        return true;
    }
    let Some(rest) = rest.strip_prefix(":editable:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let Some(focus) = parse_focus(payload) else {
        return true;
    };
    let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(frame_id))) else {
        return true;
    };
    let is_main = frame.is_main() == 1;
    with_core(|core| {
        if let Some(state) = core.tabs.get_mut(&tab) {
            state.editable_focus.record(frame_id, is_main, focus);
        }
    });
    true
}

pub fn reset(tab: MiniTabId) {
    with_core(|core| {
        if let Some(state) = core.tabs.get_mut(&tab) {
            state.editable_focus = EditableFocus::default();
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_state_counts_as_editable() {
        assert!(EditableFocus::default().has_editable_focus());
    }

    #[test]
    fn plain_main_frame_is_not_editable() {
        let mut focus = EditableFocus::default();
        focus.record("main", true, FrameFocus::NotEditable);
        assert!(!focus.has_editable_focus());
    }

    #[test]
    fn editable_main_frame_is_editable() {
        let mut focus = EditableFocus::default();
        focus.record("main", true, FrameFocus::Editable);
        assert!(focus.has_editable_focus());
        focus.record("main", true, FrameFocus::NotEditable);
        assert!(!focus.has_editable_focus());
    }

    #[test]
    fn focus_inside_a_child_frame_stays_with_the_page() {
        let mut focus = EditableFocus::default();
        focus.record("main", true, FrameFocus::ChildFrame);
        assert!(focus.has_editable_focus());
    }

    #[test]
    fn editable_child_frame_wins_over_a_plain_main_frame() {
        let mut focus = EditableFocus::default();
        focus.record("main", true, FrameFocus::NotEditable);
        focus.record("child", false, FrameFocus::Editable);
        assert!(focus.has_editable_focus());
        focus.record("child", false, FrameFocus::NotEditable);
        assert!(!focus.has_editable_focus());
    }

    #[test]
    fn typing_in_any_frame_is_unsaved_until_submitted() {
        let mut focus = EditableFocus::default();
        assert!(!focus.has_unsaved_input());
        focus.record_typing("child", true);
        focus.record_typing("main", true);
        focus.record_typing("child", false);
        assert!(focus.has_unsaved_input());
        focus.record_typing("main", false);
        assert!(!focus.has_unsaved_input());
    }

    #[test]
    fn payloads_parse() {
        assert_eq!(parse_focus("e"), Some(FrameFocus::Editable));
        assert_eq!(parse_focus("n"), Some(FrameFocus::NotEditable));
        assert_eq!(parse_focus("f"), Some(FrameFocus::ChildFrame));
        assert_eq!(parse_focus("x"), None);
    }
}
