use cef::*;
use serde::Deserialize;
use std::{collections::HashMap, ffi::c_char};

use crate::{
    MiniTabId,
    login::javascript_string_literal,
    state::{c_string, callbacks},
};

const LINK_PREVIEW_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-preview-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),last='';
var names=['og:title','twitter:title','og:description','twitter:description','description','og:image','og:image:url','og:image:secure_url','twitter:image','twitter:image:src','og:image:width','og:image:height'];
function report(){var tags={},metas=document.head?document.head.querySelectorAll('meta[property],meta[name]'):[];
for(var index=0;index<metas.length;index++){var meta=metas[index],name=(meta.getAttribute('property')||meta.getAttribute('name')||'').trim().toLowerCase();
if(names.indexOf(name)<0||tags[name]!==undefined)continue;var content=(meta.getAttribute('content')||'').trim();if(content)tags[name]=content.slice(0,2000);}
var titleElement=document.querySelector('title');
var text=JSON.stringify({tags:tags,title:titleElement?(titleElement.textContent||'').trim().slice(0,2000):'',base:document.baseURI});
if(text===last)return;last=text;signal(token+':preview:'+frameId+':'+text);}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',report);else report();
window.addEventListener('load',report);
})();"#;

#[repr(C)]
pub struct MiniLinkPreview {
    pub base_url: *const c_char,
    pub title_tag: *const c_char,
    pub og_title: *const c_char,
    pub twitter_title: *const c_char,
    pub og_description: *const c_char,
    pub twitter_description: *const c_char,
    pub description: *const c_char,
    pub og_image: *const c_char,
    pub twitter_image: *const c_char,
    pub image_width: u32,
    pub image_height: u32,
}

#[derive(Deserialize, Debug, PartialEq)]
struct Report {
    tags: HashMap<String, String>,
    title: String,
    base: String,
}

#[derive(Debug, PartialEq, Default)]
pub struct PreviewTags {
    pub base_url: String,
    pub title_tag: String,
    pub og_title: String,
    pub twitter_title: String,
    pub og_description: String,
    pub twitter_description: String,
    pub description: String,
    pub og_image: String,
    pub twitter_image: String,
    pub image_width: u32,
    pub image_height: u32,
}

pub fn script(frame: &Frame, token: &str) -> String {
    LINK_PREVIEW_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

fn first_of(tags: &HashMap<String, String>, names: &[&str]) -> String {
    names.iter().find_map(|name| tags.get(*name)).cloned().unwrap_or_default()
}

fn dimension(tags: &HashMap<String, String>, name: &str) -> u32 {
    tags.get(name).and_then(|value| value.parse::<u32>().ok()).filter(|value| *value <= 100_000).unwrap_or(0)
}

pub fn parse(payload: &str) -> Option<PreviewTags> {
    let report = serde_json::from_str::<Report>(payload).ok()?;
    let base = url::Url::parse(&report.base).ok()?;
    if base.scheme() != "http" && base.scheme() != "https" {
        return None;
    }
    let tags = &report.tags;
    Some(PreviewTags {
        base_url: base.to_string(),
        title_tag: report.title,
        og_title: first_of(tags, &["og:title"]),
        twitter_title: first_of(tags, &["twitter:title"]),
        og_description: first_of(tags, &["og:description"]),
        twitter_description: first_of(tags, &["twitter:description"]),
        description: first_of(tags, &["description"]),
        og_image: first_of(tags, &["og:image", "og:image:url", "og:image:secure_url"]),
        twitter_image: first_of(tags, &["twitter:image", "twitter:image:src"]),
        image_width: dimension(tags, "og:image:width"),
        image_height: dimension(tags, "og:image:height"),
    })
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":preview:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| frame.is_main() == 1);
    let (true, Some(tags)) = (is_main_frame, parse(payload)) else {
        return true;
    };
    let strings = [
        &tags.base_url,
        &tags.title_tag,
        &tags.og_title,
        &tags.twitter_title,
        &tags.og_description,
        &tags.twitter_description,
        &tags.description,
        &tags.og_image,
        &tags.twitter_image,
    ]
    .map(|value| c_string(value));
    let preview = MiniLinkPreview {
        base_url: strings[0].as_ptr(),
        title_tag: strings[1].as_ptr(),
        og_title: strings[2].as_ptr(),
        twitter_title: strings[3].as_ptr(),
        og_description: strings[4].as_ptr(),
        twitter_description: strings[5].as_ptr(),
        description: strings[6].as_ptr(),
        og_image: strings[7].as_ptr(),
        twitter_image: strings[8].as_ptr(),
        image_width: tags.image_width,
        image_height: tags.image_height,
    };
    unsafe { (callbacks().link_preview_reported)(tab, &preview) };
    true
}

#[cfg(test)]
mod tests {
    use super::{PreviewTags, parse};

    #[test]
    fn takes_the_first_image_alias_and_declared_size() {
        let tags = parse(
            r#"{"tags":{"og:title":"Launch","og:image:secure_url":"https://cdn.example.com/b.png","og:image:url":"/a.png","twitter:image:src":"t.png","og:image:width":"1200","og:image:height":"630"},"title":"Launch | Example","base":"https://example.com/post/"}"#,
        )
        .expect("a valid report");
        assert_eq!(
            tags,
            PreviewTags {
                base_url: "https://example.com/post/".to_owned(),
                title_tag: "Launch | Example".to_owned(),
                og_title: "Launch".to_owned(),
                og_image: "/a.png".to_owned(),
                twitter_image: "t.png".to_owned(),
                image_width: 1200,
                image_height: 630,
                ..PreviewTags::default()
            }
        );
    }

    #[test]
    fn rejects_non_web_documents_and_bad_sizes() {
        assert_eq!(parse(r#"{"tags":{},"title":"","base":"file:///tmp/a.html"}"#), None);
        assert_eq!(parse(r#"{"tags":{},"title":""}"#), None);
        assert_eq!(parse("not json"), None);
        let tags = parse(r#"{"tags":{"og:image:width":"wide","og:image:height":"9999999"},"title":"","base":"http://localhost:3000/"}"#)
            .expect("a valid report");
        assert_eq!((tags.image_width, tags.image_height), (0, 0));
    }
}
