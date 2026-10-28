use cef::*;

use crate::{
    MiniTabId,
    login::javascript_string_literal,
    state::callbacks,
};

const THEME_COLOR_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-theme-'+__TOKEN__);
if(window[key])return;
Object.defineProperty(window,key,{value:true});
var token=__TOKEN__,frameId=__FRAME__,signal=console.debug.bind(console),last=null,ready=document.readyState!=='loading',scheduled=false,context=null,queries={};
function normalize(value){if(!context)context=document.createElement('canvas').getContext('2d');
context.fillStyle='#010203';context.fillStyle=value;var first=context.fillStyle;
context.fillStyle='#040506';context.fillStyle=value;return first===context.fillStyle?first:'';}
function query(media){if(!queries[media]){queries[media]=matchMedia(media);queries[media].addEventListener('change',schedule);}return queries[media];}
function current(){var metas=document.querySelectorAll('meta[name="theme-color" i]');
for(var index=0;index<metas.length;index++){var media=metas[index].getAttribute('media');
if(media&&!query(media).matches)continue;var color=normalize((metas[index].getAttribute('content')||'').trim());if(color)return color;}return '';}
function report(){scheduled=false;var color=current();if(!ready&&!color)return;if(color===last)return;last=color;
signal(token+':theme:'+frameId+':'+JSON.stringify(color));}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(report,100);}
new MutationObserver(schedule).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['content','media','name']});
document.addEventListener('DOMContentLoaded',function(){ready=true;report();});
query('(prefers-color-scheme: dark)');
if(ready)report();
})();"#;

pub fn script(frame: &Frame, token: &str) -> String {
    THEME_COLOR_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace(
            "__FRAME__",
            &javascript_string_literal(&CefString::from(&frame.identifier()).to_string()),
        )
}

pub fn handle_signal(tab: MiniTabId, browser: &Browser, rest: &str) -> bool {
    let Some(rest) = rest.strip_prefix(":theme:") else {
        return false;
    };
    let Some((frame_id, payload)) = rest.split_once(':') else {
        return true;
    };
    let is_main_frame = browser
        .frame_by_identifier(Some(&CefString::from(frame_id)))
        .is_some_and(|frame| frame.is_main() == 1);
    let Ok(color) = serde_json::from_str::<String>(payload) else {
        return true;
    };
    if is_main_frame {
        unsafe { (callbacks().theme_color_changed)(tab, packed_color(&color)) };
    }
    true
}

fn packed_color(color: &str) -> u32 {
    let Some((red, green, blue, alpha)) = parse_color(color) else {
        return 0;
    };
    (u32::from(red) << 24) | (u32::from(green) << 16) | (u32::from(blue) << 8) | u32::from(alpha)
}

fn parse_color(color: &str) -> Option<(u8, u8, u8, u8)> {
    if let Some(hex) = color.strip_prefix('#') {
        if hex.len() != 6 {
            return None;
        }
        let value = u32::from_str_radix(hex, 16).ok()?;
        return Some(((value >> 16) as u8, (value >> 8) as u8, value as u8, 255));
    }
    let inner = color.strip_prefix("rgba(")?.strip_suffix(')')?;
    let parts: Vec<&str> = inner.split(',').map(str::trim).collect();
    let [red, green, blue, alpha] = parts.as_slice() else {
        return None;
    };
    let alpha: f64 = alpha.parse().ok()?;
    Some((
        red.parse().ok()?,
        green.parse().ok()?,
        blue.parse().ok()?,
        (alpha.clamp(0.0, 1.0) * 255.0).round() as u8,
    ))
}

#[cfg(test)]
mod tests {
    use super::packed_color;

    #[test]
    fn packs_canvas_normalized_colors() {
        assert_eq!(packed_color("#1a2b3c"), 0x1a2b3cff);
        assert_eq!(packed_color("rgba(10, 20, 30, 0.5)"), 0x0a141e80);
        assert_eq!(packed_color("rgba(0, 0, 0, 0)"), 0);
    }

    #[test]
    fn rejects_anything_else() {
        assert_eq!(packed_color(""), 0);
        assert_eq!(packed_color("#abc"), 0);
        assert_eq!(packed_color("red"), 0);
        assert_eq!(packed_color("rgba(1, 2, 3)"), 0);
        assert_eq!(packed_color("rgba(300, 2, 3, 1)"), 0);
    }
}
