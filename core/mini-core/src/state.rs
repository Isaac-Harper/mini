use cef::{Browser, DownloadItemCallback};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    ffi::{CString, c_char, c_void},
    sync::atomic::{AtomicU64, Ordering},
};

use crate::{MiniCallbacks, MiniPopupTarget, MiniTabId};

#[derive(Clone, Copy)]
pub struct Callbacks {
    pub address_changed: unsafe extern "C" fn(MiniTabId, *const c_char),
    pub title_changed: unsafe extern "C" fn(MiniTabId, *const c_char),
    pub favicon_changed: unsafe extern "C" fn(MiniTabId, *const u8, usize),
    pub loading_state_changed: unsafe extern "C" fn(MiniTabId, bool, bool, bool),
    pub open_tab_requested: unsafe extern "C" fn(MiniTabId, *const c_char, bool),
    pub popup_requested: unsafe extern "C" fn(MiniTabId, *const c_char) -> MiniPopupTarget,
    pub pre_key_event: unsafe extern "C" fn(MiniTabId, *mut c_void) -> bool,
    pub focus_requested: unsafe extern "C" fn(MiniTabId) -> bool,
    pub web_got_focus: unsafe extern "C" fn(MiniTabId),
    pub download_updated: unsafe extern "C" fn(u32, *const c_char, *const c_char, i64, i64, bool, bool),
    pub permission_requested: unsafe extern "C" fn(MiniTabId, u64, *const c_char, u32),
    pub permission_dismissed: unsafe extern "C" fn(u64),
    pub auth_requested: unsafe extern "C" fn(MiniTabId, u64, *const c_char, *const c_char, bool),
    pub login_field_focused: unsafe extern "C" fn(MiniTabId, *const c_char, *const c_char),
    pub render_process_terminated: unsafe extern "C" fn(MiniTabId, i32),
    pub login_form_presence_changed: unsafe extern "C" fn(MiniTabId, bool),
    pub browser_closed: unsafe extern "C" fn(MiniTabId),
    pub all_browsers_closed: unsafe extern "C" fn(),
}

impl Callbacks {
    pub fn from_table(table: &MiniCallbacks) -> Self {
        Self {
            address_changed: table
                .address_changed
                .expect("MiniCallbacks.address_changed is null"),
            title_changed: table
                .title_changed
                .expect("MiniCallbacks.title_changed is null"),
            favicon_changed: table
                .favicon_changed
                .expect("MiniCallbacks.favicon_changed is null"),
            loading_state_changed: table
                .loading_state_changed
                .expect("MiniCallbacks.loading_state_changed is null"),
            open_tab_requested: table
                .open_tab_requested
                .expect("MiniCallbacks.open_tab_requested is null"),
            popup_requested: table
                .popup_requested
                .expect("MiniCallbacks.popup_requested is null"),
            pre_key_event: table
                .pre_key_event
                .expect("MiniCallbacks.pre_key_event is null"),
            focus_requested: table
                .focus_requested
                .expect("MiniCallbacks.focus_requested is null"),
            web_got_focus: table
                .web_got_focus
                .expect("MiniCallbacks.web_got_focus is null"),
            download_updated: table
                .download_updated
                .expect("MiniCallbacks.download_updated is null"),
            permission_requested: table
                .permission_requested
                .expect("MiniCallbacks.permission_requested is null"),
            permission_dismissed: table
                .permission_dismissed
                .expect("MiniCallbacks.permission_dismissed is null"),
            auth_requested: table
                .auth_requested
                .expect("MiniCallbacks.auth_requested is null"),
            login_field_focused: table
                .login_field_focused
                .expect("MiniCallbacks.login_field_focused is null"),
            render_process_terminated: table
                .render_process_terminated
                .expect("MiniCallbacks.render_process_terminated is null"),
            login_form_presence_changed: table
                .login_form_presence_changed
                .expect("MiniCallbacks.login_form_presence_changed is null"),
            browser_closed: table
                .browser_closed
                .expect("MiniCallbacks.browser_closed is null"),
            all_browsers_closed: table
                .all_browsers_closed
                .expect("MiniCallbacks.all_browsers_closed is null"),
        }
    }
}

#[derive(Default)]
pub struct TabState {
    pub browser: Option<Browser>,
    pub pending_url: Option<String>,
    pub pending_focus: Option<bool>,
    pub pending_hidden: Option<bool>,
    pub pending_close: bool,
    pub favicon_generation: u64,
    pub login_form_frames: HashSet<String>,
}

pub struct CoreState {
    pub callbacks: Callbacks,
    pub tabs: HashMap<MiniTabId, TabState>,
    pub pending_popups: HashMap<i32, MiniTabId>,
    pub download_callbacks: HashMap<u32, DownloadItemCallback>,
    pub closing_all: bool,
}

static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

thread_local! {
    static CORE: RefCell<Option<CoreState>> = const { RefCell::new(None) };
}

pub fn install(callbacks: Callbacks) {
    CORE.with_borrow_mut(|core| {
        assert!(core.is_none(), "mini_initialize called twice");
        *core = Some(CoreState {
            callbacks,
            tabs: HashMap::new(),
            pending_popups: HashMap::new(),
            download_callbacks: HashMap::new(),
            closing_all: false,
        });
    });
}

pub fn with_core<Output>(action: impl FnOnce(&mut CoreState) -> Output) -> Output {
    CORE.with_borrow_mut(|core| {
        action(
            core.as_mut()
                .expect("Mini core used before mini_initialize or on a non-main thread"),
        )
    })
}

pub fn callbacks() -> Callbacks {
    with_core(|core| core.callbacks)
}

pub fn with_tab<Output>(tab: MiniTabId, action: impl FnOnce(&mut TabState) -> Output) -> Output {
    with_core(|core| {
        let state = core
            .tabs
            .get_mut(&tab)
            .unwrap_or_else(|| panic!("tab {tab} has no browser (not created or already closed)"));
        action(state)
    })
}

pub fn tab_is_live(tab: MiniTabId) -> bool {
    with_core(|core| core.tabs.contains_key(&tab))
}

pub fn next_request_id() -> u64 {
    NEXT_REQUEST_ID.fetch_add(1, Ordering::Relaxed)
}

pub fn c_string(text: &str) -> CString {
    CString::new(text.replace('\0', "")).expect("NUL bytes were removed")
}
