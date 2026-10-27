mod ad_blocking;
mod authentication;
mod client;
mod downloads;
mod favicon;
mod login;
mod permissions;
mod resource_requests;
mod state;

use cef::{library_loader::LibraryLoader, *};
use objc2_app_kit::NSView;
use std::{
    ffi::{CStr, c_char, c_int, c_void},
    sync::Mutex,
};

use client::{DevToolsClient, MiniClient, alloy_window_info};
use state::{Callbacks, TabState, callbacks, with_core, with_tab};

pub type MiniTabId = u64;

#[repr(C)]
pub struct MiniPopupTarget {
    pub tab: MiniTabId,
    pub parent_view: *mut c_void,
}

#[repr(C)]
pub struct MiniCallbacks {
    pub address_changed: Option<unsafe extern "C" fn(MiniTabId, *const c_char)>,
    pub title_changed: Option<unsafe extern "C" fn(MiniTabId, *const c_char)>,
    pub favicon_changed: Option<unsafe extern "C" fn(MiniTabId, *const u8, usize)>,
    pub loading_state_changed: Option<unsafe extern "C" fn(MiniTabId, bool, bool, bool)>,
    pub open_tab_requested: Option<unsafe extern "C" fn(MiniTabId, *const c_char, bool)>,
    pub popup_requested: Option<unsafe extern "C" fn(MiniTabId, *const c_char) -> MiniPopupTarget>,
    pub pre_key_event: Option<unsafe extern "C" fn(MiniTabId, *mut c_void) -> bool>,
    pub focus_requested: Option<unsafe extern "C" fn(MiniTabId) -> bool>,
    pub web_got_focus: Option<unsafe extern "C" fn(MiniTabId)>,
    pub download_finished: Option<unsafe extern "C" fn(*const c_char)>,
    pub permission_requested: Option<unsafe extern "C" fn(MiniTabId, u64, *const c_char, u32)>,
    pub permission_dismissed: Option<unsafe extern "C" fn(u64)>,
    pub auth_requested:
        Option<unsafe extern "C" fn(MiniTabId, u64, *const c_char, *const c_char, bool)>,
    pub login_field_focused: Option<unsafe extern "C" fn(MiniTabId, *const c_char, *const c_char)>,
    pub browser_closed: Option<unsafe extern "C" fn(MiniTabId)>,
    pub all_browsers_closed: Option<unsafe extern "C" fn()>,
}

static LIBRARY: Mutex<Option<LibraryLoader>> = Mutex::new(None);

fn borrowed_text<'text>(text: *const c_char, argument: &str) -> &'text str {
    assert!(!text.is_null(), "{argument} is null");
    unsafe { CStr::from_ptr(text) }
        .to_str()
        .unwrap_or_else(|_| panic!("{argument} is not UTF-8"))
}

pub(crate) fn view_bounds(parent_view: *mut c_void) -> Rect {
    let view = unsafe { parent_view.cast::<NSView>().as_ref() }.expect("parent view is null");
    let size = view.frame().size;
    Rect {
        x: 0,
        y: 0,
        width: size.width as c_int,
        height: size.height as c_int,
    }
}

fn created_browser(tab: MiniTabId) -> Option<Browser> {
    with_tab(tab, |state| state.browser.clone())
}

fn host(browser: &Browser) -> BrowserHost {
    browser.host().expect("browser has no host")
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_initialize(
    argc: c_int,
    argv: *mut *mut c_char,
    root_cache_path: *const c_char,
    filter_lists_path: *const c_char,
    callbacks: MiniCallbacks,
) -> bool {
    let root_cache_path = borrowed_text(root_cache_path, "root_cache_path").to_owned();
    let filter_lists_path = borrowed_text(filter_lists_path, "filter_lists_path").to_owned();
    state::install(Callbacks::from_table(&callbacks));
    login::initialize_token();

    let executable = std::env::current_exe().expect("cannot resolve the executable path");
    let loader = LibraryLoader::new(&executable, false);
    assert!(loader.load(), "cannot load the Chromium Embedded Framework");
    *LIBRARY.lock().expect("library lock poisoned") = Some(loader);

    let _ = api_hash(sys::CEF_API_VERSION_LAST, 0);

    let main_arguments = MainArgs { argc, argv };
    let exit_code = execute_process(Some(&main_arguments), None, std::ptr::null_mut());
    assert_eq!(
        exit_code, -1,
        "mini_initialize ran in a CEF subprocess (exit code {exit_code})"
    );

    let cache_path = std::path::Path::new(&root_cache_path).join("Default");
    let settings = Settings {
        root_cache_path: CefString::from(root_cache_path.as_str()),
        cache_path: CefString::from(cache_path.to_str().expect("cache path is not UTF-8")),
        persist_session_cookies: 1,
        no_sandbox: 0,
        log_severity: LogSeverity::WARNING,
        ..Default::default()
    };
    let initialized = initialize(
        Some(&main_arguments),
        Some(&settings),
        None,
        std::ptr::null_mut(),
    ) == 1;
    if initialized {
        ad_blocking::start(std::path::PathBuf::from(filter_lists_path));
    }
    initialized
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_run_message_loop() {
    run_message_loop();
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_quit_message_loop() {
    quit_message_loop();
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_shutdown() {
    shutdown();
    LIBRARY
        .lock()
        .expect("library lock poisoned")
        .take()
        .expect("CEF library was not loaded");
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_create(
    tab: MiniTabId,
    parent_view: *mut c_void,
    url: *const c_char,
) {
    assert_ne!(tab, 0, "tab id 0 is reserved");
    let url = borrowed_text(url, "url");
    with_core(|core| {
        assert!(
            !core.closing_all,
            "mini_browser_create called while closing all browsers"
        );
        let previous = core.tabs.insert(tab, TabState::default());
        assert!(
            previous.is_none(),
            "mini_browser_create called twice for tab {tab}"
        );
    });
    let window_info = alloy_window_info(parent_view);
    let mut client = MiniClient::new(tab);
    let started = browser_host_create_browser(
        Some(&window_info),
        Some(&mut client),
        Some(&CefString::from(url)),
        Some(&BrowserSettings::default()),
        None,
        None,
    );
    assert_eq!(started, 1, "browser creation failed for tab {tab}");
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_load_url(tab: MiniTabId, url: *const c_char) {
    let url = borrowed_text(url, "url");
    let browser = with_tab(tab, |state| {
        if state.browser.is_none() {
            state.pending_url = Some(url.to_owned());
        }
        state.browser.clone()
    });
    if let Some(browser) = browser {
        browser
            .main_frame()
            .expect("browser has no main frame")
            .load_url(Some(&CefString::from(url)));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_go_back(tab: MiniTabId) {
    if let Some(browser) = created_browser(tab) {
        browser.go_back();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_go_forward(tab: MiniTabId) {
    if let Some(browser) = created_browser(tab) {
        browser.go_forward();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_reload(tab: MiniTabId) {
    if let Some(browser) = created_browser(tab) {
        browser.reload();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_stop(tab: MiniTabId) {
    if let Some(browser) = created_browser(tab) {
        browser.stop_load();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_set_focus(tab: MiniTabId, focused: bool) {
    let browser = with_tab(tab, |state| {
        if state.browser.is_none() {
            state.pending_focus = Some(focused);
        }
        state.browser.clone()
    });
    if let Some(browser) = browser {
        host(&browser).set_focus(focused.into());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_set_hidden(tab: MiniTabId, hidden: bool) {
    let browser = with_tab(tab, |state| {
        if state.browser.is_none() {
            state.pending_hidden = Some(hidden);
        }
        state.browser.clone()
    });
    if let Some(browser) = browser {
        host(&browser).was_hidden(hidden.into());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_zoom(tab: MiniTabId, direction: c_int) {
    let Some(browser) = created_browser(tab) else {
        return;
    };
    let host = host(&browser);
    let level = match direction {
        -1 => host.zoom_level() - 0.5,
        0 => 0.0,
        1 => host.zoom_level() + 0.5,
        other => panic!("zoom direction must be -1, 0 or 1, got {other}"),
    };
    host.set_zoom_level(level);
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_find(
    tab: MiniTabId,
    text: *const c_char,
    forward: bool,
    find_next: bool,
) {
    let text = borrowed_text(text, "text");
    if let Some(browser) = created_browser(tab) {
        host(&browser).find(
            Some(&CefString::from(text)),
            forward.into(),
            0,
            find_next.into(),
        );
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_stop_finding(tab: MiniTabId) {
    if let Some(browser) = created_browser(tab) {
        host(&browser).stop_finding(1);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_show_dev_tools(tab: MiniTabId) {
    let Some(browser) = created_browser(tab) else {
        return;
    };
    let window_info = WindowInfo {
        runtime_style: RuntimeStyle::ALLOY,
        ..Default::default()
    };
    let mut client = DevToolsClient::new();
    host(&browser).show_dev_tools(
        Some(&window_info),
        Some(&mut client),
        Some(&BrowserSettings::default()),
        None,
    );
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_browser_close(tab: MiniTabId) {
    let browser = with_tab(tab, |state| {
        if state.browser.is_none() {
            state.pending_close = true;
        }
        state.browser.clone()
    });
    if let Some(browser) = browser {
        let host = host(&browser);
        host.close_dev_tools();
        host.close_browser(1);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_close_all_browsers() {
    let browsers: Vec<Browser> = with_core(|core| {
        core.closing_all = true;
        core.tabs
            .values_mut()
            .filter_map(|state| {
                if state.browser.is_none() {
                    state.pending_close = true;
                }
                state.browser.clone()
            })
            .collect()
    });
    let none_remain = with_core(|core| core.tabs.is_empty());
    if none_remain {
        with_core(|core| core.closing_all = false);
        unsafe { (callbacks().all_browsers_closed)() };
        return;
    }
    for browser in browsers {
        let host = host(&browser);
        host.close_dev_tools();
        host.close_browser(1);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_permission_respond(request: u64, granted: u32) {
    permissions::respond(request, granted);
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_auth_respond(
    request: u64,
    username: *const c_char,
    password: *const c_char,
) {
    if username.is_null() {
        authentication::respond(request, None);
        return;
    }
    let username = borrowed_text(username, "username");
    let password = if password.is_null() {
        ""
    } else {
        borrowed_text(password, "password")
    };
    authentication::respond(request, Some((username, password)));
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_adblock_set_enabled(enabled: bool) {
    ad_blocking::set_enabled(enabled);
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_adblock_set_host_exempt(host: *const c_char, exempt: bool) {
    ad_blocking::set_host_exempt(borrowed_text(host, "host"), exempt);
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_request_login_fill(tab: MiniTabId) {
    if let Some(browser) = created_browser(tab) {
        login::request_fill(&browser);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mini_fill_login(
    tab: MiniTabId,
    frame_id: *const c_char,
    expected_origin: *const c_char,
    username: *const c_char,
    password: *const c_char,
) {
    let frame_id = borrowed_text(frame_id, "frame_id");
    let expected_origin = borrowed_text(expected_origin, "expected_origin");
    let username = if username.is_null() {
        ""
    } else {
        borrowed_text(username, "username")
    };
    let password = borrowed_text(password, "password");
    if let Some(browser) = created_browser(tab) {
        login::fill(&browser, frame_id, expected_origin, username, password);
    }
}
