pub const SUPPRESSION_SCRIPT: &str = r#"(function(){
var marker=Symbol.for('mini-webauthn-suppressed');
if(window[marker])return;
Object.defineProperty(window,marker,{value:true});
function nativeLooking(name,implementation){
var wrapped={[name]:function(){return implementation.apply(this,arguments);}}[name];
Object.defineProperty(wrapped,'toString',{value:function(){return 'function '+name+'() { [native code] }';},enumerable:false,configurable:true,writable:true});
return wrapped;}
function define(target,name,implementation){
if(!target)return;
Object.defineProperty(target,name,{value:nativeLooking(name,implementation),enumerable:false,configurable:true,writable:true});}
function notAllowed(){return Promise.reject(new DOMException('The operation either timed out or was not allowed.','NotAllowedError'));}
var container=window.CredentialsContainer&&CredentialsContainer.prototype;
if(container){
['get','create'].forEach(function(name){
var original=container[name];
if(typeof original!=='function')return;
define(container,name,function(options){
if(options&&typeof options==='object'&&'publicKey' in options)return notAllowed();
return original.apply(this,arguments);});});}
var credential=window.PublicKeyCredential;
if(credential){
define(credential,'isUserVerifyingPlatformAuthenticatorAvailable',function(){return Promise.resolve(false);});
define(credential,'isConditionalMediationAvailable',function(){return Promise.resolve(false);});
if(typeof credential.getClientCapabilities==='function')define(credential,'getClientCapabilities',function(){return Promise.resolve({});});}
})();"#;

#[cfg(test)]
mod tests {
    use super::SUPPRESSION_SCRIPT;

    #[test]
    fn covers_every_webauthn_entry_point() {
        for needle in [
            "'get','create'",
            "'publicKey' in options",
            "NotAllowedError",
            "isUserVerifyingPlatformAuthenticatorAvailable",
            "isConditionalMediationAvailable",
            "getClientCapabilities",
            "enumerable:false",
        ] {
            assert!(SUPPRESSION_SCRIPT.contains(needle), "missing {needle}");
        }
    }
}
