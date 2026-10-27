mod lists;
mod matching;
mod resources;

use adblock::Engine;
use cef::ResourceType;
use std::{
    collections::HashSet,
    path::PathBuf,
    sync::{
        Arc, LazyLock, RwLock,
        atomic::{AtomicBool, Ordering},
    },
};

pub use matching::host_of;

static ENGINE: RwLock<Option<Arc<Engine>>> = RwLock::new(None);
static ENABLED: AtomicBool = AtomicBool::new(true);
static EXEMPT_HOSTS: LazyLock<RwLock<HashSet<String>>> =
    LazyLock::new(|| RwLock::new(HashSet::new()));

fn log_enabled() -> bool {
    static LOG: LazyLock<bool> = LazyLock::new(|| std::env::var_os("MINI_ADBLOCK_LOG").is_some());
    *LOG
}

fn install(engine: Engine) {
    *ENGINE.write().expect("ad block engine lock poisoned") = Some(Arc::new(engine));
}

fn current_engine() -> Option<Arc<Engine>> {
    ENGINE
        .read()
        .expect("ad block engine lock poisoned")
        .clone()
}

fn load_and_refresh(directory: PathBuf) {
    let mut loaded = false;
    match lists::load_serialized_engine(&directory) {
        Ok(engine) => {
            install(engine);
            loaded = true;
            if log_enabled() {
                eprintln!("[adblock] loaded serialized engine");
            }
        }
        Err(error) if lists::engine_path(&directory).exists() => {
            eprintln!("[adblock] {error}; rebuilding")
        }
        Err(_) => {}
    }
    let refresh = lists::needs_refresh(&directory);
    if refresh {
        if let Err(error) = lists::download_all(&directory) {
            eprintln!("[adblock] {error}");
        } else if log_enabled() {
            eprintln!("[adblock] downloaded filter lists");
        }
    }
    if loaded && !refresh {
        return;
    }
    if !lists::lists_present(&directory) {
        eprintln!(
            "[adblock] filter lists unavailable; ad blocking stays off until a download succeeds"
        );
        return;
    }
    let engine = match lists::build_engine(&directory) {
        Ok(engine) => engine,
        Err(error) => {
            eprintln!("[adblock] {error}");
            return;
        }
    };
    if let Err(error) = lists::save_serialized_engine(&engine, &directory) {
        eprintln!("[adblock] {error}");
    }
    install(engine);
    if log_enabled() {
        eprintln!("[adblock] built and serialized engine");
    }
}

pub fn start(directory: PathBuf) {
    std::thread::Builder::new()
        .name("mini-adblock".to_owned())
        .spawn(move || load_and_refresh(directory))
        .expect("cannot spawn the ad block loader thread");
}

pub fn set_enabled(enabled: bool) {
    ENABLED.store(enabled, Ordering::Relaxed);
}

pub fn set_host_exempt(host: &str, exempt: bool) {
    let host = host.to_ascii_lowercase();
    let mut hosts = EXEMPT_HOSTS.write().expect("exempt hosts lock poisoned");
    if exempt {
        hosts.insert(host);
    } else {
        hosts.remove(&host);
    }
}

fn applies_to(top_level_url: &str) -> bool {
    if !ENABLED.load(Ordering::Relaxed) {
        return false;
    }
    match host_of(top_level_url) {
        Some(host) => !EXEMPT_HOSTS
            .read()
            .expect("exempt hosts lock poisoned")
            .contains(&host),
        None => true,
    }
}

pub fn is_active() -> bool {
    ENABLED.load(Ordering::Relaxed)
        && ENGINE
            .read()
            .expect("ad block engine lock poisoned")
            .is_some()
}

pub fn should_cancel(url: &str, top_level_url: &str, resource_type: ResourceType) -> bool {
    if resource_type == ResourceType::MAIN_FRAME
        || resource_type == ResourceType::NAVIGATION_PRELOAD_MAIN_FRAME
    {
        return false;
    }
    if !applies_to(top_level_url) {
        return false;
    }
    let Some(engine) = current_engine() else {
        return false;
    };
    let blocked = matching::should_block(
        &engine,
        url,
        top_level_url,
        matching::request_type(resource_type),
    );
    if blocked && log_enabled() {
        eprintln!("[adblock] cancelled {url} on {top_level_url}");
    }
    blocked
}

pub fn cosmetic_script(frame_url: &str, top_level_url: &str) -> Option<String> {
    if !applies_to(top_level_url) {
        return None;
    }
    matching::cosmetic_script(&*current_engine()?, frame_url)
}

#[cfg(test)]
mod tests {
    use super::*;
    use adblock::{FilterSet, lists::ParseOptions};

    #[test]
    fn exempt_host_and_disable_bypass_blocking() {
        let mut filter_set = FilterSet::new(false);
        filter_set.add_filter_list(
            "||ads.example^\nnews.example##.advert\n".to_owned(),
            ParseOptions::default(),
        );
        install(Engine::new_with_filter_set(filter_set));
        let ad = "https://ads.example/banner.js";
        assert!(should_cancel(
            ad,
            "https://news.example/",
            ResourceType::SCRIPT
        ));
        assert!(!should_cancel(
            ad,
            "https://news.example/",
            ResourceType::MAIN_FRAME
        ));
        assert!(cosmetic_script("https://news.example/", "https://news.example/").is_some());

        set_host_exempt("News.Example", true);
        assert!(!should_cancel(
            ad,
            "https://news.example/",
            ResourceType::SCRIPT
        ));
        assert!(cosmetic_script("https://news.example/", "https://news.example/").is_none());
        assert!(should_cancel(
            ad,
            "https://www.news.example/",
            ResourceType::SCRIPT
        ));
        set_host_exempt("news.example", false);

        set_enabled(false);
        assert!(!should_cancel(
            ad,
            "https://news.example/",
            ResourceType::SCRIPT
        ));
        set_enabled(true);
        assert!(should_cancel(
            ad,
            "https://news.example/",
            ResourceType::SCRIPT
        ));
    }
}
