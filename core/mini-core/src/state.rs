use cef::{Browser, DownloadItemCallback, Registration, RequestContext};
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
    pub notification_show:
        unsafe extern "C" fn(MiniTabId, *const c_char, u32, *const c_char, *const c_char, *const c_char, *const c_char, bool),
    pub notification_close: unsafe extern "C" fn(MiniTabId, *const c_char, u32),
    pub audio_state_changed: unsafe extern "C" fn(MiniTabId, bool, *const c_char, *const c_char),
    pub status_message_changed: unsafe extern "C" fn(MiniTabId, *const c_char),
    pub fullscreen_mode_changed: unsafe extern "C" fn(MiniTabId, bool),
    pub loading_progress_changed: unsafe extern "C" fn(MiniTabId, f64),
    pub theme_color_changed: unsafe extern "C" fn(MiniTabId, u32),
    pub page_background_changed: unsafe extern "C" fn(MiniTabId, u32),
    pub horizontal_scroll_reported: unsafe extern "C" fn(MiniTabId, bool, bool),
    pub context_menu_requested: unsafe extern "C" fn(MiniTabId, *const crate::context_menu::MiniContextMenu),
    pub image_copied: unsafe extern "C" fn(MiniTabId, *const u8, usize),
    pub media_artwork_changed: unsafe extern "C" fn(MiniTabId, *const u8, usize),
    pub video_handed_off: unsafe extern "C" fn(MiniTabId, *const c_char, f64),
    pub source_received: unsafe extern "C" fn(MiniTabId, u64, *const u8, usize),
    pub main_frame_load_failed: unsafe extern "C" fn(MiniTabId, i32, *const c_char),
    pub page_vitals_changed: unsafe extern "C" fn(MiniTabId, f64, f64, f64, f64, f64),
    pub main_frame_headers_received: unsafe extern "C" fn(MiniTabId, *const c_char),
    pub link_preview_reported: unsafe extern "C" fn(MiniTabId, *const crate::link_preview::MiniLinkPreview),
    pub page_snapshot_received: unsafe extern "C" fn(MiniTabId, u64, *const u8, usize, *const crate::screenshot::MiniElementBox),
    pub browser_closed: unsafe extern "C" fn(MiniTabId),
    pub all_browsers_closed: unsafe extern "C" fn(),
    pub app_relaunched: unsafe extern "C" fn(*const *const c_char, usize),
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
            notification_show: table
                .notification_show
                .expect("MiniCallbacks.notification_show is null"),
            notification_close: table
                .notification_close
                .expect("MiniCallbacks.notification_close is null"),
            audio_state_changed: table
                .audio_state_changed
                .expect("MiniCallbacks.audio_state_changed is null"),
            status_message_changed: table
                .status_message_changed
                .expect("MiniCallbacks.status_message_changed is null"),
            fullscreen_mode_changed: table
                .fullscreen_mode_changed
                .expect("MiniCallbacks.fullscreen_mode_changed is null"),
            loading_progress_changed: table
                .loading_progress_changed
                .expect("MiniCallbacks.loading_progress_changed is null"),
            theme_color_changed: table
                .theme_color_changed
                .expect("MiniCallbacks.theme_color_changed is null"),
            page_background_changed: table
                .page_background_changed
                .expect("MiniCallbacks.page_background_changed is null"),
            horizontal_scroll_reported: table
                .horizontal_scroll_reported
                .expect("MiniCallbacks.horizontal_scroll_reported is null"),
            context_menu_requested: table
                .context_menu_requested
                .expect("MiniCallbacks.context_menu_requested is null"),
            image_copied: table
                .image_copied
                .expect("MiniCallbacks.image_copied is null"),
            media_artwork_changed: table
                .media_artwork_changed
                .expect("MiniCallbacks.media_artwork_changed is null"),
            video_handed_off: table
                .video_handed_off
                .expect("MiniCallbacks.video_handed_off is null"),
            source_received: table
                .source_received
                .expect("MiniCallbacks.source_received is null"),
            main_frame_load_failed: table
                .main_frame_load_failed
                .expect("MiniCallbacks.main_frame_load_failed is null"),
            page_vitals_changed: table
                .page_vitals_changed
                .expect("MiniCallbacks.page_vitals_changed is null"),
            main_frame_headers_received: table
                .main_frame_headers_received
                .expect("MiniCallbacks.main_frame_headers_received is null"),
            link_preview_reported: table
                .link_preview_reported
                .expect("MiniCallbacks.link_preview_reported is null"),
            page_snapshot_received: table
                .page_snapshot_received
                .expect("MiniCallbacks.page_snapshot_received is null"),
            browser_closed: table
                .browser_closed
                .expect("MiniCallbacks.browser_closed is null"),
            all_browsers_closed: table
                .all_browsers_closed
                .expect("MiniCallbacks.all_browsers_closed is null"),
            app_relaunched: table
                .app_relaunched
                .expect("MiniCallbacks.app_relaunched is null"),
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
    pub playing_frames: std::collections::BTreeMap<String, crate::media::PlayingFrame>,
    pub media_title: String,
    pub media_video: String,
    pub artwork_url: String,
    pub artwork_generation: u64,
    pub site_data_observer: Option<Registration>,
    pub snapshot_observer: Option<Registration>,
    pub editable_focus: crate::editable_focus::EditableFocus,
    pub pending_error_page: Option<String>,
}

pub struct CoreState {
    pub callbacks: Callbacks,
    pub tabs: HashMap<MiniTabId, TabState>,
    pub pending_popups: HashMap<i32, MiniTabId>,
    pub download_callbacks: HashMap<u32, DownloadItemCallback>,
    pub request_contexts: HashMap<String, RequestContext>,
    pub pending_save_paths: HashMap<String, String>,
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
            request_contexts: HashMap::new(),
            pending_save_paths: HashMap::new(),
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
