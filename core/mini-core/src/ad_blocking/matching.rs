use adblock::{Engine, request::Request};
use cef::ResourceType;

pub fn request_type(resource_type: ResourceType) -> &'static str {
    match resource_type {
        ResourceType::MAIN_FRAME | ResourceType::NAVIGATION_PRELOAD_MAIN_FRAME => "document",
        ResourceType::SUB_FRAME | ResourceType::NAVIGATION_PRELOAD_SUB_FRAME => "sub_frame",
        ResourceType::STYLESHEET => "stylesheet",
        ResourceType::SCRIPT
        | ResourceType::WORKER
        | ResourceType::SHARED_WORKER
        | ResourceType::SERVICE_WORKER => "script",
        ResourceType::IMAGE | ResourceType::FAVICON => "image",
        ResourceType::FONT_RESOURCE => "font",
        ResourceType::OBJECT | ResourceType::PLUGIN_RESOURCE => "object",
        ResourceType::MEDIA => "media",
        ResourceType::XHR => "xhr",
        ResourceType::PING => "ping",
        ResourceType::CSP_REPORT => "csp_report",
        _ => "other",
    }
}

pub fn host_of(url: &str) -> Option<String> {
    url::Url::parse(url)
        .ok()?
        .host_str()
        .map(|host| host.trim_end_matches('.').to_ascii_lowercase())
}

pub fn should_block(engine: &Engine, url: &str, source_url: &str, request_type: &str) -> bool {
    let Ok(request) = Request::new(url, source_url, request_type, "get") else {
        return false;
    };
    engine.check_network_request(&request).should_block()
}

fn css_string_literal(text: &str) -> String {
    serde_json::to_string(text).expect("a string always serializes to JSON")
}

pub fn cosmetic_script(engine: &Engine, frame_url: &str) -> Option<String> {
    let resources = engine.url_cosmetic_resources(frame_url);
    let mut selectors: Vec<&str> = resources
        .hide_selectors
        .iter()
        .map(String::as_str)
        .collect();
    selectors.sort_unstable();
    let mut script = String::new();
    if !selectors.is_empty() {
        let style = format!("{}{{display:none !important}}", selectors.join(","));
        script.push_str(&format!(
            "(function(){{var css={};function inject(){{var style=document.createElement('style');style.textContent=css;(document.head||document.documentElement).appendChild(style);}}if(document.documentElement){{inject();}}else{{new MutationObserver(function(records,observer){{if(document.documentElement){{observer.disconnect();inject();}}}}).observe(document,{{childList:true}});}}}})();\n",
            css_string_literal(&style)
        ));
    }
    if !resources.injected_script.is_empty() {
        script.push_str(&resources.injected_script);
    }
    (!script.is_empty()).then_some(script)
}

#[cfg(test)]
mod tests {
    use super::*;
    use adblock::{FilterSet, lists::ParseOptions};

    fn engine(rules: &str) -> Engine {
        let mut filter_set = FilterSet::new(false);
        filter_set.add_filter_list(rules.to_owned(), ParseOptions::default());
        Engine::new_with_filter_set(filter_set)
    }

    #[test]
    fn maps_cef_resource_types_to_adblock_request_types() {
        assert_eq!(request_type(ResourceType::MAIN_FRAME), "document");
        assert_eq!(request_type(ResourceType::SUB_FRAME), "sub_frame");
        assert_eq!(request_type(ResourceType::SCRIPT), "script");
        assert_eq!(request_type(ResourceType::SERVICE_WORKER), "script");
        assert_eq!(request_type(ResourceType::FAVICON), "image");
        assert_eq!(request_type(ResourceType::FONT_RESOURCE), "font");
        assert_eq!(request_type(ResourceType::XHR), "xhr");
        assert_eq!(request_type(ResourceType::PING), "ping");
        assert_eq!(request_type(ResourceType::PREFETCH), "other");
    }

    #[test]
    fn blocks_tracker_from_inline_list() {
        let engine = engine("||tracker.example^\n");
        assert!(should_block(
            &engine,
            "https://tracker.example/pixel.gif",
            "https://news.example/",
            "image"
        ));
        assert!(!should_block(
            &engine,
            "https://cdn.example/app.js",
            "https://news.example/",
            "script"
        ));
    }

    #[test]
    fn third_party_rule_spares_first_party_requests() {
        let engine = engine("||tracker.example^$third-party\n");
        assert!(should_block(
            &engine,
            "https://tracker.example/t.js",
            "https://news.example/",
            "script"
        ));
        assert!(!should_block(
            &engine,
            "https://tracker.example/t.js",
            "https://www.tracker.example/",
            "script"
        ));
    }

    #[test]
    fn cosmetic_script_hides_hostname_selectors_and_injects_scriptlets() {
        let engine = engine("news.example##.advert\n");
        let script =
            cosmetic_script(&engine, "https://news.example/story").expect("selectors apply");
        assert!(script.contains(".advert{display:none !important}"));
        assert!(cosmetic_script(&engine, "https://other.example/").is_none());
    }

    #[test]
    fn host_of_lowercases_and_strips_trailing_dot() {
        assert_eq!(
            host_of("https://WWW.Example.com./path").as_deref(),
            Some("www.example.com")
        );
        assert_eq!(host_of("data:text/html,hi"), None);
    }
}
