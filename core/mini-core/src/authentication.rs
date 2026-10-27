use cef::*;
use std::{
    collections::HashMap,
    sync::{LazyLock, Mutex},
};

use crate::{
    MiniTabId,
    state::{c_string, callbacks, next_request_id, tab_is_live},
};

struct PendingAuthentication {
    tab: MiniTabId,
    callback: AuthCallback,
}

// CEF callbacks are thread-safe ref-counted objects; the generated Rust wrapper only lacks the marker.
unsafe impl Send for PendingAuthentication {}

static PENDING: LazyLock<Mutex<HashMap<u64, PendingAuthentication>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn take(request: u64) -> Option<PendingAuthentication> {
    PENDING
        .lock()
        .expect("authentication lock poisoned")
        .remove(&request)
}

pub fn request_from_io_thread(
    tab: MiniTabId,
    host: String,
    realm: String,
    is_proxy: bool,
    callback: AuthCallback,
) {
    let request = next_request_id();
    PENDING
        .lock()
        .expect("authentication lock poisoned")
        .insert(request, PendingAuthentication { tab, callback });
    let mut task = AuthenticationPrompt::new(tab, request, host, realm, is_proxy);
    assert_eq!(
        post_task(ThreadId::UI, Some(&mut task)),
        1,
        "cannot post the authentication prompt to the UI thread"
    );
}

pub fn respond(request: u64, credentials: Option<(&str, &str)>) {
    let Some(pending) = take(request) else {
        return;
    };
    match credentials {
        Some((username, password)) => pending.callback.cont(
            Some(&CefString::from(username)),
            Some(&CefString::from(password)),
        ),
        None => pending.callback.cancel(),
    }
}

pub fn cancel_for_tab(tab: MiniTabId) {
    let cancelled: Vec<PendingAuthentication> = {
        let mut pending = PENDING.lock().expect("authentication lock poisoned");
        let requests: Vec<u64> = pending
            .iter()
            .filter(|(_, entry)| entry.tab == tab)
            .map(|(request, _)| *request)
            .collect();
        requests
            .into_iter()
            .map(|request| pending.remove(&request).expect("request listed above"))
            .collect()
    };
    for entry in cancelled {
        entry.callback.cancel();
    }
}

wrap_task! {
    struct AuthenticationPrompt {
        tab: MiniTabId,
        request: u64,
        host: String,
        realm: String,
        is_proxy: bool,
    }

    impl Task {
        fn execute(&self) {
            if !tab_is_live(self.tab) {
                if let Some(pending) = take(self.request) {
                    pending.callback.cancel();
                }
                return;
            }
            let host = c_string(&self.host);
            let realm = c_string(&self.realm);
            unsafe {
                (callbacks().auth_requested)(self.tab, self.request, host.as_ptr(), realm.as_ptr(), self.is_proxy)
            };
        }
    }
}
