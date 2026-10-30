use cef::*;

use crate::{
    MiniTabId,
    state::{next_request_id, with_tab},
};

wrap_dev_tools_message_observer! {
    struct StorageClearObserver {
        message_id: i32,
        origin: String,
    }

    impl DevToolsMessageObserver {
        fn on_dev_tools_method_result(
            &self,
            browser: Option<&mut Browser>,
            message_id: ::std::os::raw::c_int,
            _success: ::std::os::raw::c_int,
            _result: Option<&[u8]>,
        ) {
            if message_id != self.message_id {
                return;
            }
            let browser = browser.expect("devtools result without a browser").clone();
            delete_cookies_then_reload(browser, &self.origin);
        }
    }
}

wrap_delete_cookies_callback! {
    struct ReloadAfterDeletion {
        browser: Browser,
    }

    impl DeleteCookiesCallback {
        fn on_complete(&self, _num_deleted: ::std::os::raw::c_int) {
            self.browser.reload();
        }
    }
}

fn delete_cookies_then_reload(browser: Browser, origin: &str) {
    let cookie_manager = browser
        .host()
        .expect("browser has no host")
        .request_context()
        .expect("browser has no request context")
        .cookie_manager(None)
        .expect("request context has no cookie manager");
    let mut callback = ReloadAfterDeletion::new(browser);
    let started =
        cookie_manager.delete_cookies(Some(&CefString::from(origin)), None, Some(&mut callback));
    assert_eq!(started, 1, "cookie deletion was refused for {origin}");
}

pub fn clear(tab: MiniTabId, browser: &Browser, origin: &str) {
    let host = browser.host().expect("browser has no host");
    let message_id =
        i32::try_from(next_request_id() % i32::MAX as u64).expect("message id fits i32");
    let mut observer = StorageClearObserver::new(message_id, origin.to_owned());
    let registration = host
        .add_dev_tools_message_observer(Some(&mut observer))
        .expect("CEF refused the devtools observer");
    with_tab(tab, |state| state.site_data_observer = Some(registration));
    let mut params = dictionary_value_create().expect("cannot create a dictionary value");
    params.set_string(
        Some(&CefString::from("origin")),
        Some(&CefString::from(origin)),
    );
    params.set_string(
        Some(&CefString::from("storageTypes")),
        Some(&CefString::from("all")),
    );
    let sent = host.execute_dev_tools_method(
        message_id,
        Some(&CefString::from("Storage.clearDataForOrigin")),
        Some(&mut params),
    );
    assert_eq!(sent, message_id, "Storage.clearDataForOrigin was not sent");
}
