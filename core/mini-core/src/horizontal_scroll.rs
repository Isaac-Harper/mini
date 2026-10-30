use cef::*;

use crate::{MiniTabId, login::javascript_string_literal, state::callbacks};

const HORIZONTAL_SCROLL_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-scroll-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),lastWheel=0,lastState=-1;
function scrollable(element){if(element===document.scrollingElement)return element.scrollWidth>element.clientWidth;
var overflow=getComputedStyle(element).overflowX;return (overflow==='auto'||overflow==='scroll'||overflow==='overlay')&&element.scrollWidth>element.clientWidth;}
function state(path){var left=false,right=false;
var elements=path.filter(function(node){return node instanceof Element;});
if(document.scrollingElement&&elements.indexOf(document.scrollingElement)<0)elements.push(document.scrollingElement);
elements.forEach(function(element){if(!scrollable(element))return;var maximum=element.scrollWidth-element.clientWidth;
if(Math.abs(element.scrollLeft)>0.5)left=true;if(Math.abs(element.scrollLeft)<maximum-0.5)right=true;});
return (left?1:0)|(right?2:0);}
window.addEventListener('wheel',function(event){var now=Date.now(),starts=now-lastWheel>300;lastWheel=now;
if(Math.abs(event.deltaX)<=Math.abs(event.deltaY)&&!starts)return;
var current=state(event.composedPath());if(!starts&&current===lastState)return;lastState=current;
signal(token+':scroll:'+frameId+':'+current);},{capture:true,passive:true});
})();"#;

pub fn script(frame: &Frame, token: &str) -> String {
    HORIZONTAL_SCROLL_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":scroll:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    if browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_none()
    {
        return true;
    }
    let Ok(edges) = payload.parse::<u8>() else {
        return true;
    };
    unsafe { (callbacks().horizontal_scroll_reported)(tab, edges & 1 != 0, edges & 2 != 0) };
    true
}
