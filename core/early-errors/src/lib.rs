pub const KEY: &str = "mini-early-errors";

const SCRIPT: &str = r#"(function(){
var key=Symbol.for('__KEY__');
if(Object.prototype.hasOwnProperty.call(window,key))return;
var count=0,first=null;
function onError(event){if(!(event instanceof ErrorEvent))return;count++;if(first===null)first=event;}
function onRejection(event){count++;if(first===null)first=event;}
window.addEventListener('error',onError);
window.addEventListener('unhandledrejection',onRejection);
Object.defineProperty(window,key,{value:function(){window.removeEventListener('error',onError);window.removeEventListener('unhandledrejection',onRejection);var taken={count:count,event:first};count=0;first=null;return taken;}});
})();"#;

pub fn script() -> String {
    SCRIPT.replace("__KEY__", KEY)
}

#[cfg(test)]
mod tests {
    use super::{KEY, script};

    #[test]
    fn script_defines_the_shared_key_once() {
        let script = script();
        assert!(script.contains(&format!("Symbol.for('{KEY}')")));
        assert!(!script.contains("__KEY__"));
    }
}
