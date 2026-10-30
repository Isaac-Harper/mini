use cef::*;

use crate::login::javascript_string_literal;

const PRELOAD_SCRIPT: &str = r#"(function(){
var key=Symbol.for('mini-preload-'+__TOKEN__);
var previous=window[key];
if(previous)previous.remove();
Object.defineProperty(window,key,{value:null,writable:true,configurable:true});
var url=__URL__;
if(!url||!HTMLScriptElement.supports||!HTMLScriptElement.supports('speculationrules'))return;
var script=document.createElement('script');
script.type='speculationrules';
script.textContent=JSON.stringify({prefetch:[{source:'list',urls:[url]}]});
(document.head||document.documentElement).appendChild(script);
window[key]=script;
})();"#;

pub fn script(token: &str, url: &str) -> String {
    PRELOAD_SCRIPT
        .replace("__TOKEN__", &javascript_string_literal(token))
        .replace("__URL__", &javascript_string_literal(url))
}

pub fn set(browser: &Browser, token: &str, url: &str) {
    let frame = browser.main_frame().expect("browser has no main frame");
    let frame_url = CefString::from(&frame.url()).to_string();
    frame.execute_java_script(
        Some(&CefString::from(script(token, url).as_str())),
        Some(&CefString::from(frame_url.as_str())),
        0,
    );
}

#[cfg(test)]
mod tests {
    use super::script;

    #[test]
    fn the_url_is_a_string_literal() {
        let built = script("abc", "https://a.test/x?q='</script>");
        assert!(built.contains(r#"var url="https://a.test/x?q='\u003c/script>";"#));
        assert!(built.contains(r#"Symbol.for('mini-preload-'+"abc")"#));
    }

    #[test]
    fn an_empty_url_only_removes_the_previous_rule() {
        assert!(script("abc", "").contains(r#"var url="";"#));
    }
}
