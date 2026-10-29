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
function artwork(metadata){var best='',area=-1;
if(metadata&&metadata.artwork)Array.prototype.forEach.call(metadata.artwork,function(item){if(!item||!item.src)return;var size=0;String(item.sizes||'').split(/\s+/).forEach(function(entry){var match=/^(\d+)x(\d+)$/i.exec(entry);if(match)size=Math.max(size,match[1]*match[2]);});if(size>=area){area=size;best=item.src;}});
if(!best){var video=media().filter(function(element){return element.tagName==='VIDEO'&&audible(element)&&element.poster;})[0];if(video)best=video.poster;}
try{return best?new URL(best,document.baseURI).href:'';}catch(error){return '';}}
function report(){scheduled=false;
var playing=media().some(audible);
var metadata=navigator.mediaSession&&navigator.mediaSession.metadata;
var title=metadata?[metadata.title,metadata.artist].filter(Boolean).join(' · '):'';
var state=JSON.stringify({playing:playing,title:title,artwork:playing?artwork(metadata):''});
if(state===last)return;last=state;signal(token+':media:'+frameId+':'+state);}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(report,250);}
['play','playing','pause','ended','volumechange','emptied','loadedmetadata'].forEach(function(type){document.addEventListener(type,schedule,true);});
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

const ARTWORK_MAXIMUM_SIZE: u32 = 128;

#[derive(Deserialize)]
struct MediaState {
    playing: bool,
    title: String,
    #[serde(default)]
    artwork: String,
}

#[derive(Clone, Default, PartialEq)]
pub struct PlayingFrame {
    title: String,
    artwork: String,
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
    update(tab, false, |frames| {
        if state.playing {
            let artwork = if is_artwork_url(&state.artwork) {
                state.artwork
            } else {
                String::new()
            };
            frames.insert(
                frame_id.to_owned(),
                PlayingFrame {
                    title: state.title,
                    artwork,
                },
            );
        } else {
            frames.remove(frame_id);
        }
    });
    true
}

fn is_artwork_url(url: &str) -> bool {
    ["https:", "http:", "data:image/"]
        .iter()
        .any(|scheme| url.starts_with(scheme))
}

fn update(
    tab: MiniTabId,
    is_new_document: bool,
    change: impl FnOnce(&mut std::collections::BTreeMap<String, PlayingFrame>),
) {
    let (report, artwork) = with_core(|core| {
        let Some(state) = core.tabs.get_mut(&tab) else {
            return (None, None);
        };
        let was_playing = !state.playing_frames.is_empty();
        change(&mut state.playing_frames);
        let playing = !state.playing_frames.is_empty();
        let title = kept_while_idle(
            playing,
            is_new_document,
            &state.media_title,
            media_title(&state.playing_frames),
        );
        let report = (playing != was_playing || title != state.media_title)
            .then(|| (playing, title.clone()));
        state.media_title = title;
        let artwork = kept_while_idle(
            playing,
            is_new_document,
            &state.artwork_url,
            artwork_url(&state.playing_frames),
        );
        let artwork_change = if artwork != state.artwork_url {
            state.artwork_url = artwork.clone();
            state.artwork_generation += 1;
            Some((artwork, state.artwork_generation, state.browser.clone()))
        } else {
            None
        };
        (report, artwork_change)
    });
    if let Some((playing, title)) = report {
        let title = c_string(&title);
        unsafe { (callbacks().audio_state_changed)(tab, playing, title.as_ptr()) };
    }
    if let Some((url, generation, browser)) = artwork {
        match browser {
            Some(browser) if !url.is_empty() => {
                let mut callback = ArtworkDownload::new(tab, generation);
                browser.host().expect("browser has no host").download_image(
                    Some(&CefString::from(url.as_str())),
                    0,
                    ARTWORK_MAXIMUM_SIZE,
                    0,
                    Some(&mut callback),
                );
            }
            _ => report_artwork(tab, &[]),
        }
    }
}

fn kept_while_idle(playing: bool, is_new_document: bool, kept: &str, current: String) -> String {
    if playing || is_new_document {
        current
    } else {
        kept.to_owned()
    }
}

fn media_title(frames: &std::collections::BTreeMap<String, PlayingFrame>) -> String {
    frames
        .values()
        .map(|frame| &frame.title)
        .find(|title| !title.is_empty())
        .cloned()
        .unwrap_or_default()
}

fn artwork_url(frames: &std::collections::BTreeMap<String, PlayingFrame>) -> String {
    frames
        .values()
        .map(|frame| &frame.artwork)
        .find(|artwork| !artwork.is_empty())
        .cloned()
        .unwrap_or_default()
}

fn report_artwork(tab: MiniTabId, png: &[u8]) {
    let pointer = if png.is_empty() {
        std::ptr::null()
    } else {
        png.as_ptr()
    };
    unsafe { (callbacks().media_artwork_changed)(tab, pointer, png.len()) };
}

wrap_download_image_callback! {
    struct ArtworkDownload {
        tab: MiniTabId,
        generation: u64,
    }

    impl DownloadImageCallback {
        fn on_download_image_finished(
            &self,
            _image_url: Option<&CefString>,
            _http_status_code: ::std::os::raw::c_int,
            image: Option<&mut Image>,
        ) {
            let is_current = with_core(|core| {
                core.tabs
                    .get(&self.tab)
                    .is_some_and(|state| state.artwork_generation == self.generation)
            });
            if !is_current {
                return;
            }
            let png = image
                .filter(|image| image.is_empty() == 0)
                .map(|image| crate::favicon::png_bytes(image, 2.0))
                .unwrap_or_default();
            report_artwork(self.tab, &png);
        }
    }
}

pub fn reset(tab: MiniTabId) {
    update(tab, true, |frames| frames.clear());
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
        if let Some(frame) =
            browser.frame_by_identifier(Some(&CefString::from(identifier.as_str())))
        {
            let url = CefString::from(&frame.url()).to_string();
            frame.execute_java_script(
                Some(&CefString::from(script.as_str())),
                Some(&CefString::from(url.as_str())),
                0,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(title: &str, artwork: &str) -> PlayingFrame {
        PlayingFrame {
            title: title.to_owned(),
            artwork: artwork.to_owned(),
        }
    }

    #[test]
    fn artwork_urls_are_web_or_inline_images_only() {
        assert!(is_artwork_url("https://example.com/cover.jpg"));
        assert!(is_artwork_url("http://127.0.0.1/cover.png"));
        assert!(is_artwork_url("data:image/png;base64,AAAA"));
        assert!(!is_artwork_url("data:text/html,hi"));
        assert!(!is_artwork_url("javascript:alert(1)"));
        assert!(!is_artwork_url("file:///etc/passwd"));
        assert!(!is_artwork_url(""));
    }

    #[test]
    fn artwork_comes_from_the_first_frame_that_has_one() {
        let mut frames = std::collections::BTreeMap::new();
        assert_eq!(artwork_url(&frames), "");
        frames.insert("a".to_owned(), frame("Song", ""));
        frames.insert("b".to_owned(), frame("", "https://example.com/b.jpg"));
        assert_eq!(artwork_url(&frames), "https://example.com/b.jpg");
        assert_eq!(media_title(&frames), "Song");
    }

    #[test]
    fn title_and_artwork_are_kept_while_paused_and_cleared_by_a_new_document() {
        assert_eq!(kept_while_idle(false, false, "Song", String::new()), "Song");
        assert_eq!(kept_while_idle(false, true, "Song", String::new()), "");
        assert_eq!(kept_while_idle(true, false, "Song", String::new()), "");
        assert_eq!(
            kept_while_idle(true, false, "Song", "Next".to_owned()),
            "Next"
        );
    }
}
