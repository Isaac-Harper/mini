use cef::*;

use crate::{login::token, page_reply};

const TEXT_STYLE_SCRIPT: &str = r#"(function(){
var token=__TOKEN__,request=__REQUEST__,signal=console.debug.bind(console);
var selection=window.getSelection();
if(!selection||selection.rangeCount===0||selection.isCollapsed)return;
var node=selection.getRangeAt(0).startContainer;
var element=node.nodeType===1?node:node.parentElement;
if(!element)return;
var style=getComputedStyle(element);
signal(token+':pagetext:'+request+':'+JSON.stringify({fontFamily:style.fontFamily,fontSize:style.fontSize,lineHeight:style.lineHeight,fontWeight:style.fontWeight,letterSpacing:style.letterSpacing,color:style.color,textTransform:style.textTransform}));
})();"#;

pub fn script(token: &str, request: u64) -> String {
    page_reply::instantiate(TEXT_STYLE_SCRIPT, token, request)
}

pub fn request(browser: &Browser, request: u64) {
    page_reply::run_in_every_frame(browser, &script(token(), request));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn script_reads_the_selection_start_element_and_replies_on_the_page_text_channel() {
        let script = script("abc", 5);
        assert!(script.contains("var token=\"abc\",request=5,"));
        assert!(script.contains("getRangeAt(0).startContainer"));
        assert!(script.contains("':pagetext:'"));
        assert!(!script.contains("__"));
    }
}
