use cef::*;

use crate::{
    MiniTabId,
    state::{callbacks, tab_is_live},
};

wrap_string_visitor! {
    struct SourceVisitor {
        tab: MiniTabId,
        request: u64,
    }

    impl CefStringVisitor {
        fn visit(&self, string: Option<&CefString>) {
            if !tab_is_live(self.tab) {
                return;
            }
            let source = string.map(CefString::to_string).unwrap_or_default();
            unsafe { (callbacks().source_received)(self.tab, self.request, source.as_ptr(), source.len()) };
        }
    }
}

pub fn request(tab: MiniTabId, browser: &Browser, request: u64) {
    let mut visitor = SourceVisitor::new(tab, request);
    browser
        .main_frame()
        .expect("browser has no main frame")
        .source(Some(&mut visitor));
}
