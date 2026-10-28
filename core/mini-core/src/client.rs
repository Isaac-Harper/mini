use cef::*;
use std::ffi::c_void;

use crate::{
    MiniTabId, ad_blocking, authentication, downloads, favicon, login, permissions,
    resource_requests::MiniResourceRequestHandler,
    state::{TabState, c_string, callbacks, with_core},
};

pub fn alloy_window_info(parent_view: *mut c_void) -> WindowInfo {
    WindowInfo {
        parent_view,
        bounds: crate::view_bounds(parent_view),
        runtime_style: RuntimeStyle::ALLOY,
        ..Default::default()
    }
}

fn text(value: Option<&CefString>) -> String {
    value.map(CefString::to_string).unwrap_or_default()
}

pub fn main_frame_url(browser: &Browser) -> String {
    browser
        .main_frame()
        .map(|frame| CefString::from(&frame.url()).to_string())
        .unwrap_or_default()
}

fn browser_host(browser: &Browser) -> BrowserHost {
    browser.host().expect("browser has no host")
}

fn register_created_browser(tab: MiniTabId, browser: Browser) {
    let (pending_url, pending_focus, pending_hidden, pending_close) = with_core(|core| {
        core.pending_popups
            .retain(|_, pending_tab| *pending_tab != tab);
        let state = core
            .tabs
            .get_mut(&tab)
            .unwrap_or_else(|| panic!("browser created for unregistered tab {tab}"));
        assert!(
            state.browser.is_none(),
            "tab {tab} received a second browser"
        );
        state.browser = Some(browser.clone());
        (
            state.pending_url.take(),
            state.pending_focus.take(),
            state.pending_hidden.take(),
            std::mem::take(&mut state.pending_close),
        )
    });
    let host = browser_host(&browser);
    if pending_close {
        host.close_browser(1);
        return;
    }
    if let Some(hidden) = pending_hidden {
        host.was_hidden(hidden.into());
    }
    if let Some(url) = pending_url {
        browser
            .main_frame()
            .expect("browser has no main frame")
            .load_url(Some(&CefString::from(url.as_str())));
    }
    if let Some(focused) = pending_focus {
        host.set_focus(focused.into());
    }
}

fn unregister_closed_browser(tab: MiniTabId) {
    permissions::dismiss_for_tab(tab);
    authentication::cancel_for_tab(tab);
    let all_closed = with_core(|core| {
        core.tabs
            .remove(&tab)
            .unwrap_or_else(|| panic!("closed browser belongs to unregistered tab {tab}"));
        let all_closed = core.closing_all && core.tabs.is_empty();
        if all_closed {
            core.closing_all = false;
        }
        all_closed
    });
    let callbacks = callbacks();
    unsafe { (callbacks.browser_closed)(tab) };
    if all_closed {
        unsafe { (callbacks.all_browsers_closed)() };
    }
}

wrap_client! {
    pub struct MiniClient {
        tab: MiniTabId,
    }

    impl Client {
        fn display_handler(&self) -> Option<DisplayHandler> {
            Some(MiniDisplayHandler::new(self.tab))
        }

        fn load_handler(&self) -> Option<LoadHandler> {
            Some(MiniLoadHandler::new(self.tab))
        }

        fn life_span_handler(&self) -> Option<LifeSpanHandler> {
            Some(MiniLifeSpanHandler::new(self.tab))
        }

        fn request_handler(&self) -> Option<RequestHandler> {
            Some(MiniRequestHandler::new(self.tab))
        }

        fn keyboard_handler(&self) -> Option<KeyboardHandler> {
            Some(MiniKeyboardHandler::new(self.tab))
        }

        fn focus_handler(&self) -> Option<FocusHandler> {
            Some(MiniFocusHandler::new(self.tab))
        }

        fn download_handler(&self) -> Option<DownloadHandler> {
            Some(MiniDownloadHandler::new())
        }

        fn permission_handler(&self) -> Option<PermissionHandler> {
            Some(permissions::MiniPermissionHandler::new(self.tab))
        }
    }
}

wrap_client! {
    pub struct DevToolsClient;

    impl Client {}
}

wrap_display_handler! {
    struct MiniDisplayHandler {
        tab: MiniTabId,
    }

    impl DisplayHandler {
        fn on_address_change(
            &self,
            _browser: Option<&mut Browser>,
            frame: Option<&mut Frame>,
            url: Option<&CefString>,
        ) {
            if frame.expect("address change without a frame").is_main() != 1 {
                return;
            }
            let url = c_string(&text(url));
            unsafe { (callbacks().address_changed)(self.tab, url.as_ptr()) };
        }

        fn on_console_message(
            &self,
            browser: Option<&mut Browser>,
            _level: LogSeverity,
            message: Option<&CefString>,
            _source: Option<&CefString>,
            _line: ::std::os::raw::c_int,
        ) -> ::std::os::raw::c_int {
            let message = text(message);
            if !login::is_signal(&message) {
                return 0;
            }
            login::handle_signal(self.tab, browser.expect("console message without a browser"), &message);
            1
        }

        fn on_title_change(&self, _browser: Option<&mut Browser>, title: Option<&CefString>) {
            let title = c_string(&text(title));
            unsafe { (callbacks().title_changed)(self.tab, title.as_ptr()) };
        }

        fn on_favicon_urlchange(
            &self,
            browser: Option<&mut Browser>,
            icon_urls: Option<&mut CefStringList>,
        ) {
            let first_url = icon_urls
                .and_then(|list| std::mem::take(list).into_iter().next())
                .filter(|url| !url.is_empty());
            favicon::favicon_urls_changed(self.tab, browser.expect("favicon change without a browser"), first_url);
        }
    }
}

wrap_load_handler! {
    struct MiniLoadHandler {
        tab: MiniTabId,
    }

    impl LoadHandler {
        fn on_loading_state_change(
            &self,
            _browser: Option<&mut Browser>,
            is_loading: ::std::os::raw::c_int,
            can_go_back: ::std::os::raw::c_int,
            can_go_forward: ::std::os::raw::c_int,
        ) {
            unsafe {
                (callbacks().loading_state_changed)(
                    self.tab,
                    is_loading != 0,
                    can_go_back != 0,
                    can_go_forward != 0,
                )
            };
        }

        fn on_load_start(
            &self,
            browser: Option<&mut Browser>,
            frame: Option<&mut Frame>,
            _transition_type: TransitionType,
        ) {
            let frame = frame.expect("load start without a frame");
            let frame_url = CefString::from(&frame.url()).to_string();
            let detection = login::detection_script(frame);
            frame.execute_java_script(
                Some(&CefString::from(detection.as_str())),
                Some(&CefString::from(frame_url.as_str())),
                0,
            );
            let top_level_url = if frame.is_main() == 1 {
                frame_url.clone()
            } else {
                main_frame_url(browser.expect("load start without a browser"))
            };
            if let Some(script) = ad_blocking::cosmetic_script(&frame_url, &top_level_url) {
                frame.execute_java_script(Some(&CefString::from(script.as_str())), Some(&CefString::from(frame_url.as_str())), 0);
            }
        }
    }
}

wrap_life_span_handler! {
    struct MiniLifeSpanHandler {
        tab: MiniTabId,
    }

    impl LifeSpanHandler {
        fn on_before_popup(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            popup_id: ::std::os::raw::c_int,
            target_url: Option<&CefString>,
            _target_frame_name: Option<&CefString>,
            _target_disposition: WindowOpenDisposition,
            _user_gesture: ::std::os::raw::c_int,
            _popup_features: Option<&PopupFeatures>,
            window_info: Option<&mut WindowInfo>,
            client: Option<&mut Option<Client>>,
            _settings: Option<&mut BrowserSettings>,
            _extra_info: Option<&mut Option<DictionaryValue>>,
            _no_javascript_access: Option<&mut ::std::os::raw::c_int>,
        ) -> ::std::os::raw::c_int {
            let url = c_string(&text(target_url));
            let target = unsafe { (callbacks().popup_requested)(self.tab, url.as_ptr()) };
            if target.tab == 0 {
                return 1;
            }
            assert!(!target.parent_view.is_null(), "popup_requested returned tab {} without a parent view", target.tab);
            *window_info.expect("popup without window info") = alloy_window_info(target.parent_view);
            *client.expect("popup without client slot") = Some(MiniClient::new(target.tab));
            with_core(|core| {
                let previous = core.tabs.insert(target.tab, TabState::default());
                assert!(previous.is_none(), "popup_requested returned existing tab {}", target.tab);
                core.pending_popups.insert(popup_id, target.tab);
            });
            0
        }

        fn on_before_popup_aborted(&self, _browser: Option<&mut Browser>, popup_id: ::std::os::raw::c_int) {
            let Some(tab) = with_core(|core| core.pending_popups.remove(&popup_id)) else {
                return;
            };
            unregister_closed_browser(tab);
        }

        fn on_after_created(&self, browser: Option<&mut Browser>) {
            register_created_browser(self.tab, browser.expect("on_after_created without a browser").clone());
        }

        fn do_close(&self, browser: Option<&mut Browser>) -> ::std::os::raw::c_int {
            // Returning 0 makes CEF performClose: the whole host NSWindow; detaching the view destroys only this browser.
            let browser = browser.expect("do_close without a browser");
            let browser_view = browser_host(browser).window_handle().cast::<objc2_app_kit::NSView>();
            unsafe { browser_view.as_ref() }
                .expect("browser has no native view")
                .removeFromSuperview();
            1
        }

        fn on_before_close(&self, _browser: Option<&mut Browser>) {
            unregister_closed_browser(self.tab);
        }
    }
}

wrap_request_handler! {
    struct MiniRequestHandler {
        tab: MiniTabId,
    }

    impl RequestHandler {
        fn on_open_urlfrom_tab(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            target_url: Option<&CefString>,
            target_disposition: WindowOpenDisposition,
            _user_gesture: ::std::os::raw::c_int,
        ) -> ::std::os::raw::c_int {
            let url = c_string(&text(target_url));
            let foreground = target_disposition == WindowOpenDisposition::NEW_FOREGROUND_TAB;
            unsafe { (callbacks().open_tab_requested)(self.tab, url.as_ptr(), foreground) };
            1
        }

        fn resource_request_handler(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            _request: Option<&mut Request>,
            _is_navigation: ::std::os::raw::c_int,
            _is_download: ::std::os::raw::c_int,
            _request_initiator: Option<&CefString>,
            _disable_default_handling: Option<&mut ::std::os::raw::c_int>,
        ) -> Option<ResourceRequestHandler> {
            ad_blocking::is_active().then(MiniResourceRequestHandler::new)
        }

        fn on_render_process_terminated(
            &self,
            _browser: Option<&mut Browser>,
            status: TerminationStatus,
            _error_code: ::std::os::raw::c_int,
            _error_string: Option<&CefString>,
        ) {
            let reason = *status.as_ref() as i32;
            unsafe { (callbacks().render_process_terminated)(self.tab, reason) };
        }

        fn auth_credentials(
            &self,
            _browser: Option<&mut Browser>,
            _origin_url: Option<&CefString>,
            is_proxy: ::std::os::raw::c_int,
            host: Option<&CefString>,
            _port: ::std::os::raw::c_int,
            realm: Option<&CefString>,
            _scheme: Option<&CefString>,
            callback: Option<&mut AuthCallback>,
        ) -> ::std::os::raw::c_int {
            authentication::request_from_io_thread(
                self.tab,
                text(host),
                text(realm),
                is_proxy != 0,
                callback.expect("authentication without a callback").clone(),
            );
            1
        }
    }
}

wrap_keyboard_handler! {
    struct MiniKeyboardHandler {
        tab: MiniTabId,
    }

    impl KeyboardHandler {
        fn on_pre_key_event(
            &self,
            _browser: Option<&mut Browser>,
            event: Option<&KeyEvent>,
            os_event: *mut u8,
            _is_keyboard_shortcut: Option<&mut ::std::os::raw::c_int>,
        ) -> ::std::os::raw::c_int {
            let event = event.expect("pre key event without an event");
            let shortcut_modifiers = sys::cef_event_flags_t::EVENTFLAG_COMMAND_DOWN.0
                | sys::cef_event_flags_t::EVENTFLAG_CONTROL_DOWN.0;
            if event.type_ != KeyEventType::RAWKEYDOWN || event.modifiers & shortcut_modifiers == 0 {
                return 0;
            }
            let consumed = unsafe { (callbacks().pre_key_event)(self.tab, os_event.cast()) };
            consumed.into()
        }
    }
}

wrap_focus_handler! {
    struct MiniFocusHandler {
        tab: MiniTabId,
    }

    impl FocusHandler {
        fn on_set_focus(&self, _browser: Option<&mut Browser>, _source: FocusSource) -> ::std::os::raw::c_int {
            let allowed = unsafe { (callbacks().focus_requested)(self.tab) };
            (!allowed).into()
        }

        fn on_got_focus(&self, _browser: Option<&mut Browser>) {
            unsafe { (callbacks().web_got_focus)(self.tab) };
        }
    }
}

wrap_download_handler! {
    struct MiniDownloadHandler;

    impl DownloadHandler {
        fn can_download(
            &self,
            _browser: Option<&mut Browser>,
            _url: Option<&CefString>,
            _request_method: Option<&CefString>,
        ) -> ::std::os::raw::c_int {
            1
        }

        fn on_before_download(
            &self,
            _browser: Option<&mut Browser>,
            _download_item: Option<&mut DownloadItem>,
            suggested_name: Option<&CefString>,
            callback: Option<&mut BeforeDownloadCallback>,
        ) -> ::std::os::raw::c_int {
            let destination = downloads::unique_destination(&downloads::downloads_directory(), &text(suggested_name));
            let destination = destination.to_str().expect("download path is not UTF-8");
            callback
                .expect("before download without a callback")
                .cont(Some(&CefString::from(destination)), 0);
            1
        }

        fn on_download_updated(
            &self,
            _browser: Option<&mut Browser>,
            download_item: Option<&mut DownloadItem>,
            callback: Option<&mut DownloadItemCallback>,
        ) {
            let item = download_item.expect("download update without an item");
            let download = item.id();
            let is_complete = item.is_complete() == 1;
            let is_canceled = item.is_canceled() == 1 || item.is_interrupted() == 1;
            with_core(|core| {
                if is_complete || is_canceled {
                    core.download_callbacks.remove(&download);
                } else if let Some(callback) = callback {
                    core.download_callbacks.insert(download, callback.clone());
                }
            });
            let full_path = CefString::from(&item.full_path()).to_string();
            let file_name = std::path::Path::new(&full_path)
                .file_name()
                .and_then(|name| name.to_str())
                .map(str::to_owned)
                .unwrap_or_else(|| CefString::from(&item.suggested_file_name()).to_string());
            let file_name = c_string(&file_name);
            let path = c_string(&full_path);
            unsafe {
                (callbacks().download_updated)(
                    download,
                    file_name.as_ptr(),
                    path.as_ptr(),
                    item.received_bytes(),
                    item.total_bytes(),
                    is_complete,
                    is_canceled,
                )
            };
        }
    }
}
