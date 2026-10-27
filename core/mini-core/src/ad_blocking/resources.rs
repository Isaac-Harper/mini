use adblock::resources::{MimeType, PermissionMask, Resource, ResourceType};
use base64::{Engine as _, prelude::BASE64_STANDARD};
use serde::Deserialize;

pub const TRUSTED_PERMISSION: PermissionMask = PermissionMask::from_bits(1);

#[derive(Deserialize)]
struct ResourceBundle {
    scriptlets: Vec<Scriptlet>,
    redirects: Vec<Redirect>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Scriptlet {
    name: String,
    aliases: Vec<String>,
    body: String,
    dependencies: Vec<String>,
    #[serde(default)]
    execution_world: Option<String>,
    #[serde(default)]
    requires_trust: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Redirect {
    name: String,
    aliases: Vec<String>,
    content_type: String,
    body: String,
}

fn scriptlet_resource(scriptlet: Scriptlet) -> Resource {
    let mime = if scriptlet.name.ends_with(".fn") {
        MimeType::FnJavascript
    } else {
        MimeType::ApplicationJavascript
    };
    Resource {
        name: scriptlet.name,
        aliases: scriptlet.aliases,
        kind: ResourceType::Mime(mime),
        content: BASE64_STANDARD.encode(scriptlet.body),
        dependencies: scriptlet.dependencies,
        permission: if scriptlet.requires_trust {
            TRUSTED_PERMISSION
        } else {
            PermissionMask::default()
        },
    }
}

fn redirect_resource(redirect: Redirect) -> Resource {
    let mut content_type_parts = redirect.content_type.split(';');
    let mime = content_type_parts
        .next()
        .expect("split yields at least one part");
    let is_base64 = content_type_parts.any(|part| part == "base64");
    Resource {
        name: redirect.name,
        aliases: redirect.aliases,
        kind: ResourceType::Mime(MimeType::from(mime)),
        content: if is_base64 {
            redirect.body
        } else {
            BASE64_STANDARD.encode(redirect.body)
        },
        dependencies: Vec::new(),
        permission: PermissionMask::default(),
    }
}

pub fn parse_resource_bundle(json: &str) -> Result<Vec<Resource>, serde_json::Error> {
    let bundle: ResourceBundle = serde_json::from_str(json)?;
    let scriptlets = bundle
        .scriptlets
        .into_iter()
        .filter(|scriptlet| scriptlet.execution_world.as_deref() != Some("ISOLATED"))
        .map(scriptlet_resource);
    let redirects = bundle.redirects.into_iter().map(redirect_resource);
    Ok(scriptlets.chain(redirects).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use adblock::{Engine, FilterSet, lists::ParseOptions};

    const BUNDLE: &str = r#"{
        "scriptlets": [
            {"name": "set-constant.fn", "aliases": [], "body": "function setConstantFn(trusted, chain, value){window[chain]=value==='true';}", "dependencies": []},
            {"name": "set-constant.js", "aliases": ["set.js"], "body": "function setConstant(...args){setConstantFn(false,...args)}", "dependencies": ["set-constant.fn"]},
            {"name": "isolated.js", "aliases": [], "body": "function isolated(){}", "dependencies": [], "executionWorld": "ISOLATED"}
        ],
        "redirects": [
            {"name": "1x1.gif", "aliases": [], "contentType": "image/gif;base64", "body": "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"},
            {"name": "noop.js", "aliases": [], "contentType": "application/javascript", "body": "(function(){})()"}
        ]
    }"#;

    #[test]
    fn converts_bundle_and_drops_isolated_world_scriptlets() {
        let resources = parse_resource_bundle(BUNDLE).expect("bundle parses");
        let names: Vec<&str> = resources
            .iter()
            .map(|resource| resource.name.as_str())
            .collect();
        assert_eq!(
            names,
            ["set-constant.fn", "set-constant.js", "1x1.gif", "noop.js"]
        );
        assert_eq!(
            resources[0].kind,
            ResourceType::Mime(MimeType::FnJavascript)
        );
        assert_eq!(
            resources[2].content,
            "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        );
        assert_eq!(
            resources[3].content,
            BASE64_STANDARD.encode("(function(){})()")
        );
    }

    #[test]
    fn scriptlet_filter_injects_function_style_resource() {
        let mut filter_set = FilterSet::new(false);
        filter_set.add_filter_list(
            "news.example##+js(set, adsEnabled, false)\n".to_owned(),
            ParseOptions::default(),
        );
        let mut engine = Engine::new_with_filter_set(filter_set);
        engine.use_resources(parse_resource_bundle(BUNDLE).expect("bundle parses"));
        let script = engine
            .url_cosmetic_resources("https://news.example/")
            .injected_script;
        assert!(script.contains("function setConstantFn"), "{script}");
        assert!(script.contains("setConstant("), "{script}");
    }
}
