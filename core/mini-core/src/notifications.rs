use cef::*;
use serde::Deserialize;
use std::{cell::RefCell, collections::HashMap};

use crate::{
    MiniTabId,
    login::{javascript_string_literal, origin_of},
    permissions,
    state::{c_string, callbacks},
};

pub const DEFAULT: i32 = 0;
pub const GRANTED: i32 = 1;
pub const DENIED: i32 = 2;

thread_local! {
    static PERMISSIONS: RefCell<HashMap<String, i32>> = RefCell::new(HashMap::new());
}

const SHIM_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-notify-'+__TOKEN__);
if(window[key])return;
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),permission=__PERMISSION__;
var nextId=1,open={},pendingRequest=null,waiters=[],identifier=Symbol('mini-notification-id');
function send(kind,payload){signal(token+':notify-'+kind+':'+frameId+':'+JSON.stringify(payload));}
function nativeLooking(name,implementation){
var wrapped={[name]:function(){return implementation.apply(this,arguments);}}[name];
Object.defineProperty(wrapped,'toString',{value:function(){return 'function '+name+'() { [native code] }';},enumerable:false,configurable:true,writable:true});
return wrapped;}
function define(target,name,implementation){
Object.defineProperty(target,name,{value:nativeLooking(name,implementation),enumerable:false,configurable:true,writable:true});}
function fire(notification,type){
var event=new Event(type);
var handler=notification['on'+type];
if(typeof handler==='function'){try{handler.call(notification,event);}catch(error){setTimeout(function(){throw error;});}}
notification.dispatchEvent(event);}
class Notification extends EventTarget{
constructor(title,options){
super();
if(arguments.length===0)throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
options=options||{};
this.title=String(title);
this.body=options.body===undefined?'':String(options.body);
this.tag=options.tag===undefined?'':String(options.tag);
this.icon=options.icon===undefined?'':String(options.icon);
this.silent=!!options.silent;
this.data=options.data===undefined?null:options.data;
this.onclick=null;this.onclose=null;this.onshow=null;this.onerror=null;
var id=nextId++,self=this;
Object.defineProperty(this,identifier,{value:id});
if(permission!=='granted'){setTimeout(function(){fire(self,'error');},0);return;}
if(this.tag){Object.keys(open).forEach(function(other){if(open[other].tag===self.tag)delete open[other];});}
open[id]=this;
send('show',{id:id,title:this.title,body:this.body,tag:this.tag,silent:this.silent});
setTimeout(function(){fire(self,'show');},0);}
close(){var id=this[identifier];if(!open[id])return;delete open[id];send('close',{id:id});fire(this,'close');}
static get permission(){return permission;}
static get maxActions(){return 0;}
static requestPermission(callback){
var promise=new Promise(function(resolve){
if(permission!=='default'){resolve(permission);return;}
var active=navigator.userActivation&&navigator.userActivation.isActive;
if(pendingRequest===null&&!active){resolve('default');return;}
waiters.push(resolve);
if(pendingRequest===null){pendingRequest=nextId++;send('permission',{id:pendingRequest});}});
if(typeof callback==='function')promise.then(callback);
return promise;}}
Object.defineProperty(Notification,'toString',{value:function(){return 'function Notification() { [native code] }';},enumerable:false,configurable:true,writable:true});
define(Notification.prototype,'close',Notification.prototype.close);
Object.defineProperty(window,'Notification',{value:Notification,enumerable:false,configurable:true,writable:true});
if(window.ServiceWorkerRegistration){
var registration=ServiceWorkerRegistration.prototype;
define(registration,'showNotification',function(title,options){
if(permission!=='granted')return Promise.reject(new TypeError('No notification permission has been granted for this origin.'));
new Notification(title,options);return Promise.resolve();});
define(registration,'getNotifications',function(filter){
var tag=filter&&filter.tag;
return Promise.resolve(Object.keys(open).map(function(id){return open[id];}).filter(function(notification){return !tag||notification.tag===tag;}));});}
Object.defineProperty(window,key,{value:{
permissionResult:function(state){permission=state;pendingRequest=null;var pending=waiters;waiters=[];pending.forEach(function(resolve){resolve(state);});},
clicked:function(id){var notification=open[id];if(!notification)return;window.focus();fire(notification,'click');}
}});
})();"#;

pub fn set_permission(origin: &str, state: i32) {
    PERMISSIONS.with_borrow_mut(|permissions| {
        if state == DEFAULT {
            permissions.remove(origin);
        } else {
            permissions.insert(origin.to_owned(), state);
        }
    });
}

fn permission(origin: &str) -> i32 {
    PERMISSIONS.with_borrow(|permissions| permissions.get(origin).copied().unwrap_or(DEFAULT))
}

fn permission_name(state: i32) -> &'static str {
    match state {
        GRANTED => "granted",
        DENIED => "denied",
        _ => "default",
    }
}

fn frame_url(frame: &Frame) -> String {
    CefString::from(&frame.url()).to_string()
}

fn run(frame: &Frame, script: &str) {
    frame.execute_java_script(
        Some(&CefString::from(script)),
        Some(&CefString::from(frame_url(frame).as_str())),
        0,
    );
}

pub fn shim_script(frame: &Frame, token: &str) -> String {
    let state = origin_of(&frame_url(frame)).map_or(DEFAULT, |origin| permission(&origin));
    SHIM_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
        .replace(
            "__PERMISSION__",
            &javascript_string_literal(permission_name(state)),
        )
}

fn api_call(token: &str, call: &str) -> String {
    format!(
        "(function(){{var api=window[Symbol.for('mini-notify-'+{})];if(api)api.{call};}})();",
        javascript_string_literal(token)
    )
}

pub fn deliver_permission_result(browser: &Browser, frame_id: &str, token: &str, state: i32) {
    if let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(frame_id))) {
        let call = format!(
            "permissionResult({})",
            javascript_string_literal(permission_name(state))
        );
        run(&frame, &api_call(token, &call));
    }
}

pub fn deliver_click(browser: &Browser, frame_id: &str, token: &str, notification: u32) {
    if let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(frame_id))) {
        run(
            &frame,
            &api_call(token, &format!("clicked({notification})")),
        );
    }
}

#[derive(Deserialize)]
struct ShowPayload {
    id: u32,
    title: String,
    body: String,
    tag: String,
    silent: bool,
}

#[derive(Deserialize)]
struct IdentifierPayload {
    id: u32,
}

pub fn parse_signal(rest: &str) -> Option<(&str, &str, &str)> {
    let rest = rest.strip_prefix(":notify-")?;
    let (kind, rest) = rest.split_once(':')?;
    let (frame_id, payload) = rest.split_once(':')?;
    (!frame_id.is_empty()).then_some((kind, frame_id, payload))
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, token: &str, rest: &str) -> bool {
    let Some((kind, frame_id, payload)) = parse_signal(rest) else {
        return false;
    };
    let Some(frame) = browser.frame_by_identifier(Some(&CefString::from(frame_id))) else {
        return true;
    };
    let Some(origin) = origin_of(&frame_url(&frame)) else {
        return true;
    };
    match kind {
        "show" => {
            let Ok(show) = serde_json::from_str::<ShowPayload>(payload) else {
                return true;
            };
            if permission(&origin) != GRANTED {
                return true;
            }
            let frame_id = c_string(frame_id);
            let origin = c_string(&origin);
            let title = c_string(&show.title);
            let body = c_string(&show.body);
            let tag = c_string(&show.tag);
            unsafe {
                (callbacks().notification_show)(
                    tab,
                    frame_id.as_ptr(),
                    show.id,
                    origin.as_ptr(),
                    title.as_ptr(),
                    body.as_ptr(),
                    tag.as_ptr(),
                    show.silent,
                )
            };
        }
        "close" => {
            let Ok(close) = serde_json::from_str::<IdentifierPayload>(payload) else {
                return true;
            };
            let frame_id = c_string(frame_id);
            unsafe { (callbacks().notification_close)(tab, frame_id.as_ptr(), close.id) };
        }
        "permission" => {
            if serde_json::from_str::<IdentifierPayload>(payload).is_err() {
                return true;
            }
            let state = permission(&origin);
            if state != DEFAULT {
                deliver_permission_result(browser, frame_id, token, state);
            } else {
                permissions::request_notifications(
                    tab,
                    &origin,
                    browser.clone(),
                    frame_id.to_owned(),
                );
            }
        }
        _ => {}
    }
    true
}

#[cfg(test)]
mod tests {
    use super::parse_signal;

    #[test]
    fn splits_kind_frame_and_payload() {
        assert_eq!(
            parse_signal(r#":notify-show:7-12:{"id":1,"title":"a:b"}"#),
            Some(("show", "7-12", r#"{"id":1,"title":"a:b"}"#))
        );
        assert_eq!(parse_signal(":notify-close::{}"), None);
        assert_eq!(parse_signal(":login:7-12"), None);
    }
}
