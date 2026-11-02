pub const KEY: &str = "mini-microphone";

const SCRIPT: &str = r#"(function(){
var key=Symbol.for('__KEY__');
if(Object.prototype.hasOwnProperty.call(window,key)||!window.WeakRef)return;
var references=[],known=new WeakSet(),disabledByMini=new WeakSet(),muted=false,installed=false;
function nativeLooking(name,implementation){
var wrapped={[name]:function(){return implementation.apply(this,arguments);}}[name];
Object.defineProperty(wrapped,'toString',{value:function(){return 'function '+name+'() { [native code] }';},enumerable:false,configurable:true,writable:true});
return wrapped;}
function define(target,name,implementation){Object.defineProperty(target,name,{value:nativeLooking(name,implementation),enumerable:false,configurable:true,writable:true});}
function apply(track){if(muted){if(track.enabled){track.enabled=false;disabledByMini.add(track);}}else if(disabledByMini.has(track)){disabledByMini.delete(track);track.enabled=true;}}
function keep(track,original){if(!track||track.kind!=='audio'||known.has(track))return;known.add(track);if(original&&disabledByMini.has(original)&&!track.enabled)disabledByMini.add(track);references.push(new WeakRef(track));apply(track);}
function live(){references=references.filter(function(reference){var track=reference.deref();return track&&track.readyState!=='ended';});return references.map(function(reference){return reference.deref();});}
function install(){if(installed||!window.MediaDevices||!window.MediaStreamTrack)return;installed=true;
var getUserMedia=MediaDevices.prototype.getUserMedia;
if(typeof getUserMedia==='function')define(MediaDevices.prototype,'getUserMedia',function(){return getUserMedia.apply(this,arguments).then(function(stream){stream.getAudioTracks().forEach(function(track){keep(track);});return stream;});});
var cloneTrack=MediaStreamTrack.prototype.clone;
define(MediaStreamTrack.prototype,'clone',function(){var copy=cloneTrack.apply(this,arguments);if(known.has(this))keep(copy,this);return copy;});
if(window.MediaStream){var cloneStream=MediaStream.prototype.clone;
define(MediaStream.prototype,'clone',function(){var copy=cloneStream.apply(this,arguments),originals=this.getAudioTracks();if(originals.some(function(track){return known.has(track);}))copy.getAudioTracks().forEach(function(track,index){keep(track,originals[index]);});return copy;});}}
Object.defineProperty(window,key,{value:function(value){install();muted=!!value;live().forEach(apply);}});
install();
if(!installed&&window.navigator&&!Object.prototype.hasOwnProperty.call(navigator,'mediaDevices'))Object.defineProperty(navigator,'mediaDevices',{configurable:true,enumerable:false,get:function(){delete navigator.mediaDevices;install();return navigator.mediaDevices;}});
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
        assert!(script.contains("hasOwnProperty.call(window,key)"));
        assert!(!script.contains("__KEY__"));
    }

    #[test]
    fn wraps_get_user_media_and_clones_but_not_display_media() {
        let script = script();
        assert!(script.contains("'getUserMedia'"));
        assert!(script.contains("MediaStreamTrack.prototype,'clone'"));
        assert!(script.contains("MediaStream.prototype,'clone'"));
        assert!(!script.contains("getDisplayMedia"));
    }
}
